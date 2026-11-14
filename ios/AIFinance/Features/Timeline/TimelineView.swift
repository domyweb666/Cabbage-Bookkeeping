import FinanceCore
import SwiftUI

/// 唯一的主要畫面（規格 7.2）：頂部本月支出、中間時間軸、底部輸入列。不使用底部分頁。
struct TimelineView: View {
    @Environment(TimelineViewModel.self) private var model
    @Environment(SpeechService.self) private var speech
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKeys.autoKeyboard) private var autoKeyboard = true
    @AppStorage(SettingsKeys.voiceAutoSend) private var voiceAutoSend = false

    @State private var editing: Txn?
    @State private var showNew = false
    @State private var showOverview = false
    @State private var showSettings = false
    @State private var evidence: AnswerCard?
    @State private var inputFromVoice = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header
            if !model.isOnline { offlineBanner }

            if model.isEmpty {
                emptyState
            } else {
                timeline
            }

            VStack(spacing: Theme.unit) {
                if let toast = model.toast { ToastBar(toast: toast) { Task { await model.undo(toast) } } }
                if let hint = model.hint { hintBar(hint) }
                if case .unavailable(let message) = speech.status { hintBar(message) { speech.clearError() } }
                InputBar(
                    text: $model.inputText,
                    isListening: speech.isListening,
                    focused: $inputFocused,
                    onSend: send,
                    onMic: toggleMic,
                    onManualAdd: { if model.isOnline { showNew = true } }
                )
            }
            .padding(.horizontal, Theme.spacing(2))
            .padding(.top, Theme.unit)
            .padding(.bottom, Theme.unit)
            .background(Theme.background)
            .animation(.easeOut(duration: 0.2), value: model.toast)
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            await model.start()
            if autoKeyboard { inputFocused = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.becameActive() } }
        }
        .onChange(of: speech.transcript) { _, text in
            if speech.isListening { model.inputText = text }
        }
        .sheet(item: $editing) { item in
            EditorView(mode: .edit(item))
        }
        .sheet(isPresented: $showNew) {
            EditorView(mode: .new)
        }
        .sheet(isPresented: $showOverview) {
            OverviewView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $evidence) { card in
            EvidenceListView(card: card)
        }
        .sheet(item: Binding(get: { model.confirmQueue.first }, set: { _ in })) { request in
            ConfirmSheet(request: request)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
        }
    }

    // MARK: - 頂部

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                showOverview = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("本月支出")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    AmountText(text: Money.format(model.monthExpense), font: .system(size: 34, weight: .bold, design: .rounded))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("monthTotal")
            .accessibilityLabel("本月支出 \(Money.format(model.monthExpense))，點一下看本月概覽")

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("設定")
        }
        .padding(.horizontal, Theme.spacing(2.5))
        .padding(.top, Theme.unit)
        .padding(.bottom, Theme.spacing(1.5))
    }

    private var offlineBanner: some View {
        HStack(spacing: Theme.unit) {
            Image(systemName: "wifi.slash")
            Text("離線中。照常輸入就好，連上網路後會自動處理；編輯、刪除和提問要等連線。")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.spacing(1.5))
        .padding(.horizontal, Theme.spacing(2))
        .padding(.bottom, Theme.unit)
    }

    // MARK: - 首次開啟

    private var emptyState: some View {
        VStack(spacing: Theme.spacing(2)) {
            Spacer()
            if model.isLoading {
                ProgressView()
            } else {
                Text("講一句就記好了")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("點一句試試看")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(TimelineViewModel.examples, id: \.self) { example in
                    Button {
                        model.useExample(example)
                        inputFocused = true
                    } label: {
                        Text(example)
                            .font(.body)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .card(padding: Theme.spacing(1.75))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.spacing(4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
    }

    // MARK: - 時間軸

    private var timeline: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                if model.isOnline { editing = item }
                            } label: {
                                TransactionRow(item: item, category: model.category(item.categoryId))
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if model.isOnline {
                                    Button(role: .destructive) {
                                        Task { await model.delete(item) }
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(model.title(for: section.day))
                            Spacer()
                            if section.incomeTotal > 0 {
                                Text("+" + Money.grouped(section.incomeTotal)).foregroundStyle(Theme.income)
                            }
                            if section.expenseTotal > 0 {
                                Text("-" + Money.grouped(section.expenseTotal))
                            }
                        }
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(nil)
                    }
                }

                if !model.answers.isEmpty {
                    Section {
                        ForEach(model.answers) { card in
                            AnswerCardView(card: card) { evidence = card }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        model.dismissAnswer(card)
                                    } label: {
                                        Label("移除", systemImage: "xmark")
                                    }
                                }
                        }
                    }
                }

                if !model.pending.isEmpty {
                    Section {
                        ForEach(model.pending) { entry in
                            PendingRow(entry: entry, onRetry: { model.retry(entry) }, onDiscard: { model.discard(entry) })
                        }
                    }
                }

                Color.clear
                    .frame(height: 1)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .id("bottom")
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: model.transactions.count + model.pending.count + model.answers.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // 鍵盤升起後清單變矮，要等它升完再捲一次，最新的幾筆才不會被擋住。
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - 輸入列上方的提示

    private func hintBar(_ text: String, onClose: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: Theme.unit) {
            Image(systemName: "info.circle")
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if let onClose { onClose() } else { model.clearHint() }
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("關閉提示")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
        .card(padding: Theme.spacing(1.5))
    }

    // MARK: - 動作

    private func send() {
        if speech.isListening { speech.stop() }
        model.submit(source: inputFromVoice ? "voice" : "text")
        inputFromVoice = false
    }

    private func toggleMic() {
        if speech.isListening {
            speech.stop()
            return
        }
        inputFocused = false
        Task {
            await speech.start { text in
                guard !text.isEmpty else { return }
                model.inputText = text
                inputFromVoice = true
                // 預設停止後文字留在輸入框讓使用者修改；設定中可改成自動送出。
                if voiceAutoSend { send() }
            }
        }
    }
}

// MARK: - 元件

struct TransactionRow: View {
    let item: Txn
    let category: TxCategory?

    var body: some View {
        HStack(spacing: Theme.spacing(1.5)) {
            Image(systemName: category?.icon ?? "questionmark.circle")
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.item)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.unit)

            AmountText(
                text: Money.signed(item.amount, type: item.type),
                color: item.type == .income ? Theme.income : Theme.primaryText,
                font: .body.weight(.medium)
            )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.item)，\(category?.name ?? "未分類")，\(item.type.label) \(Money.format(item.amount))")
    }

    private var subtitle: String {
        ([category?.name ?? "未分類"] + item.tags.prefix(2)).joined(separator: " · ")
    }
}

/// 待處理的原話：淡色顯示。
struct PendingRow: View {
    let entry: PendingEntry
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            HStack(spacing: Theme.unit) {
                if entry.state == .sending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: entry.state == .failed ? "exclamationmark.circle" : "clock")
                }
                Text(entry.rawText).lineLimit(2)
                Spacer()
                Text(label).font(.caption)
            }
            .foregroundStyle(Theme.secondaryText)

            if entry.state == .failed {
                if let message = entry.message {
                    Text(message).font(.caption).foregroundStyle(Theme.expense)
                }
                HStack(spacing: Theme.spacing(2)) {
                    Button("再試一次", action: onRetry)
                    Button("不記了", role: .destructive, action: onDiscard)
                }
                .font(.footnote.weight(.medium))
                .buttonStyle(.borderless)
            }
        }
        .opacity(entry.state == .failed ? 1 : 0.6)
    }

    private var label: String {
        switch entry.state {
        case .waiting: return "待處理"
        case .sending: return "整理中"
        case .failed: return "沒記成"
        }
    }
}

struct ToastBar: View {
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer()
            if toast.canUndo {
                Button("復原", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("undoButton")
            }
        }
        .padding(.horizontal, Theme.spacing(2))
        .padding(.vertical, Theme.spacing(1.5))
        .background(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// 底部輸入列：文字框、麥克風鍵、送出鍵。長按送出鍵是手動新增。
struct InputBar: View {
    @Binding var text: String
    let isListening: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onMic: () -> Void
    let onManualAdd: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.unit) {
            TextField("麥當勞 188，或問：這個月花多少？", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .focused(focused)
                .submitLabel(.send)
                .onChange(of: text) { _, value in
                    // 多行輸入框按 return 會換行；把它當成送出。
                    if value.hasSuffix("\n") {
                        text = String(value.dropLast())
                        onSend()
                    }
                }
                .padding(.horizontal, Theme.spacing(1.75))
                .padding(.vertical, Theme.spacing(1.25))
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .accessibilityIdentifier("inputField")

            Button(action: onMic) {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isListening ? .white : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(isListening ? Theme.expense : Theme.card)
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("micButton")
            .accessibilityLabel(isListening ? "停止語音輸入" : "語音輸入")

            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(canSend ? Theme.accent : Theme.secondaryText.opacity(0.4))
                .clipShape(Circle())
                .contentShape(Circle())
                .onTapGesture { if canSend { onSend() } }
                .onLongPressGesture(minimumDuration: 0.4) { onManualAdd() }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("sendButton")
                .accessibilityLabel("送出")
                .accessibilityHint("長按可以手動新增一筆")
                .accessibilityAction { if canSend { onSend() } }
                .accessibilityAction(named: "手動新增") { onManualAdd() }
        }
    }
}
