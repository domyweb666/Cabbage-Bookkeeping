import FinanceCore
import Foundation

/// 直接用 URLSession 呼叫 Supabase 的 Auth、Database API 與 Edge Functions。
/// 只帶 anon key 與使用者的 JWT；AI 金鑰與 service role key 不會出現在 App 裡。
actor SupabaseBackend: Backend {
    nonisolated let isDemo = false

    private struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userId: UUID
        var isAnonymous: Bool
    }

    private struct AuthUser: Decodable {
        let id: UUID
        let isAnonymous: Bool?
    }

    private struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let user: AuthUser
    }

    private static let sessionKey = "session"
    private static let genericMessage = "發生了一點問題，請稍後再試。"

    private let baseURL: URL
    private let anonKey: String
    private let http: URLSession
    private var session: Session?
    private var refreshTask: Task<Session, Error>?

    init(baseURL: URL, anonKey: String) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        self.http = URLSession(configuration: config)
        if let data = KeychainStore.load(Self.sessionKey) {
            self.session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    var isLinked: Bool {
        session.map { !$0.isAnonymous } ?? false
    }

    // MARK: - 登入

    func ensureSession() async throws {
        _ = try await validSession()
    }

    private func store(_ response: AuthResponse) -> Session {
        let s = Session(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            userId: response.user.id,
            isAnonymous: response.user.isAnonymous ?? false
        )
        session = s
        if let data = try? JSONEncoder().encode(s) { KeychainStore.save(data, for: Self.sessionKey) }
        return s
    }

    /// 取得可用的 session：沒有就匿名登入，快過期就換新。同時間只會有一個換新的請求。
    private func validSession() async throws -> Session {
        if let s = session, s.expiresAt.timeIntervalSinceNow > 60 { return s }
        if let task = refreshTask { return try await task.value }

        let current = session
        let task = Task { () throws -> Session in
            if let current {
                do {
                    return try await self.authRequest(
                        path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                        body: ["refresh_token": current.refreshToken], bearer: nil
                    )
                } catch let error as BackendError where !error.isNetwork {
                    // 登入狀態失效，換不了新的。往下重新匿名登入；
                    // 原本綁過 Apple ID 的人，到設定再按一次「透過 Apple 繼續」就能取回資料。
                }
            }
            return try await self.authRequest(path: "auth/v1/signup", query: [], body: [:], bearer: nil)
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func authRequest(path: String, query: [URLQueryItem], body: [String: Any], bearer: String?) async throws -> Session {
        let data = try await raw("POST", path, query: query, body: try JSONSerialization.data(withJSONObject: body), token: bearer ?? anonKey)
        do {
            return store(try JSONCoding.decoder().decode(AuthResponse.self, from: data))
        } catch {
            throw BackendError.server(code: "auth_failed", message: Self.genericMessage)
        }
    }

    func linkApple(idToken: String, rawNonce: String, allowSwitch: Bool) async throws -> Bool {
        let current = try await validSession()
        let query = [URLQueryItem(name: "grant_type", value: "id_token")]
        do {
            // 把 Apple 身分掛到目前的匿名帳號上，資料不用搬。
            _ = try await authRequest(
                path: "auth/v1/token", query: query,
                body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce, "link_identity": true],
                bearer: current.accessToken
            )
            return false
        } catch let error as BackendError where !error.isNetwork {
            // 掛不上去，多半是這個 Apple ID 已經綁過另一個帳號（換手機或重裝）。
            guard allowSwitch else {
                throw BackendError.server(code: "apple_already_linked", message: "這個 Apple ID 已經有一份備份了。")
            }
            // 改成直接登入那個帳號，取回原本的資料。
            _ = try await authRequest(
                path: "auth/v1/token", query: query,
                body: ["provider": "apple", "id_token": idToken, "nonce": rawNonce], bearer: nil
            )
            return true
        }
    }

    // MARK: - HTTP

    private func raw(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        token: String, prefer: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw BackendError.network
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw BackendError.network }
        if (200..<300).contains(status) { return data }

        // Edge Function 的錯誤帶有給使用者看的中文訊息；其他來源的錯誤不外露細節。
        if let envelope = try? JSONCoding.decoder().decode(APIEnvelope<EmptyData>.self, from: data), let error = envelope.error {
            throw BackendError.server(code: error.code, message: error.message)
        }
        if status == 401 { throw BackendError.server(code: "unauthorized", message: "登入已過期，請重新開啟 App 再試一次。") }
        throw BackendError.server(code: "http_\(status)", message: Self.genericMessage)
    }

    private struct EmptyData: Decodable {}

    /// 帶著使用者 JWT 的請求。遇到 401 會換一次 token 再試。
    private func call(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil
    ) async throws -> Data {
        let s = try await validSession()
        do {
            return try await raw(method, path, query: query, body: body, token: s.accessToken, prefer: prefer)
        } catch BackendError.server(let code, _) where code == "unauthorized" {
            session?.expiresAt = .distantPast
            let fresh = try await validSession()
            return try await raw(method, path, query: query, body: body, token: fresh.accessToken, prefer: prefer)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONCoding.decoder().decode(type, from: data)
        } catch {
            throw BackendError.server(code: "bad_response", message: Self.genericMessage)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONCoding.encoder().encode(value)
    }

    /// 呼叫 Edge Function 並拆開統一回傳格式。
    private func function<T: Decodable, B: Encodable>(_ name: String, body: B, as type: T.Type) async throws -> T {
        let data = try await call("POST", "functions/v1/\(name)", body: try encode(body))
        let envelope = try decode(APIEnvelope<T>.self, from: data)
        if let error = envelope.error { throw BackendError.server(code: error.code, message: error.message) }
        guard let value = envelope.data else { throw BackendError.server(code: "bad_response", message: Self.genericMessage) }
        return value
    }

    private func eq(_ id: UUID) -> String { "eq.\(id.uuidString.lowercased())" }

    // MARK: - 記與問

    private struct RecordBody: Encodable {
        let entryId: String
        let rawText: String
        let source: String
        let clientCreatedAt: String
    }

    private struct ConfirmBody: Encodable {
        let entryId: String
        var transactions: [Draft]?
        var cancel: Bool?
    }

    private struct AskBody: Encodable {
        let question: String
    }

    func record(entryId: UUID, rawText: String, source: String, clientCreatedAt: String) async throws -> RecordResult {
        try await function(
            "record",
            body: RecordBody(entryId: entryId.uuidString.lowercased(), rawText: rawText, source: source, clientCreatedAt: clientCreatedAt),
            as: RecordResult.self
        )
    }

    func confirm(entryId: UUID, drafts: [Draft]) async throws -> RecordResult {
        try await function(
            "record/confirm",
            body: ConfirmBody(entryId: entryId.uuidString.lowercased(), transactions: drafts, cancel: nil),
            as: RecordResult.self
        )
    }

    func cancelConfirm(entryId: UUID) async throws {
        _ = try await function(
            "record/confirm",
            body: ConfirmBody(entryId: entryId.uuidString.lowercased(), transactions: nil, cancel: true),
            as: RecordResult.self
        )
    }

    func ask(question: String) async throws -> AskAnswer {
        try await function("ask", body: AskBody(question: question), as: AskAnswer.self)
    }

    // MARK: - 交易讀寫（Database API + RLS）

    func fetchCategories() async throws -> [TxCategory] {
        let data = try await call("GET", "rest/v1/categories", query: [
            URLQueryItem(name: "select", value: "id,name,kind,icon,sort_order"),
            URLQueryItem(name: "order", value: "sort_order"),
        ])
        return try decode([TxCategory].self, from: data)
    }

    func fetchTransactions() async throws -> [Txn] {
        // Database API 一次最多回 1000 筆，分頁讀完。
        let pageSize = 1000
        var all: [Txn] = []
        for page in 0..<20 {
            let data = try await call("GET", "rest/v1/transactions", query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "occurred_on.desc,created_at.desc,id.desc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(page * pageSize)),
            ])
            let rows = try decode([Txn].self, from: data)
            all += rows
            if rows.count < pageSize { break }
        }
        return all
    }

    func createTransaction(_ fields: TxnFields) async throws -> Txn {
        let data = try await call("POST", "rest/v1/transactions", body: try encode(fields), prefer: "return=representation")
        guard let row = try decode([Txn].self, from: data).first else {
            throw BackendError.server(code: "bad_response", message: Self.genericMessage)
        }
        return row
    }

    func updateTransaction(id: UUID, fields: TxnFields) async throws -> Txn {
        let data = try await call(
            "PATCH", "rest/v1/transactions", query: [URLQueryItem(name: "id", value: eq(id))],
            body: try encode(fields), prefer: "return=representation"
        )
        guard let row = try decode([Txn].self, from: data).first else {
            throw BackendError.server(code: "not_found", message: "找不到這筆紀錄，可能已經被刪除。")
        }
        return row
    }

    func setDeleted(id: UUID, deleted: Bool) async throws {
        let value: Any = deleted ? ISO8601DateFormatter().string(from: Date()) : NSNull()
        _ = try await call(
            "PATCH", "rest/v1/transactions", query: [URLQueryItem(name: "id", value: eq(id))],
            body: try JSONSerialization.data(withJSONObject: ["deleted_at": value])
        )
    }

    func fetchRawText(entryId: UUID) async throws -> String? {
        struct Row: Decodable { let rawText: String }
        let data = try await call("GET", "rest/v1/entries", query: [
            URLQueryItem(name: "select", value: "raw_text"),
            URLQueryItem(name: "id", value: eq(entryId)),
        ])
        return try decode([Row].self, from: data).first?.rawText
    }

    // MARK: - 概覽、設定、帳號

    func monthlyOverview(monthOf day: String) async throws -> MonthlyOverview {
        let data = try await call("POST", "rest/v1/rpc/monthly_overview", body: try JSONSerialization.data(withJSONObject: ["month": day]))
        return try decode(MonthlyOverview.self, from: data)
    }

    func fetchProfile() async throws -> Profile {
        let data = try await call("GET", "rest/v1/profiles", query: [URLQueryItem(name: "select", value: "auto_commit,auto_commit_max")])
        return try decode([Profile].self, from: data).first ?? Profile()
    }

    func updateProfile(_ profile: Profile) async throws {
        let s = try await validSession()
        let body: [String: Any] = [
            "auto_commit": profile.autoCommit,
            "auto_commit_max": profile.autoCommitMax.map { $0 as Any } ?? NSNull(),
        ]
        _ = try await call(
            "PATCH", "rest/v1/profiles", query: [URLQueryItem(name: "id", value: eq(s.userId))],
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    func deleteAllData() async throws {
        _ = try await call("POST", "rest/v1/rpc/delete_all_my_data", body: Data("{}".utf8))
    }
}
