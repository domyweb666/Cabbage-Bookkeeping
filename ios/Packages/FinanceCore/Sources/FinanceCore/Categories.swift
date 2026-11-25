import Foundation

public struct TxCategory: Identifiable, Hashable, Sendable {
    /// 內建分類固定不變的編號。1 到 12、21 到 24 是最早的 16 類；後來加的支出從 101 起、收入從 201 起。
    /// 使用者自己新增的沒有這個編號。
    public let number: Int?
    public let id: UUID
    public let name: String
    public let kind: TxType
    /// 「常用分類」畫面上的分組，其他地方用不到。
    public let group: String
    public let icon: String

    /// 沒動過設定時就顯示的那 16 類。
    var isStandard: Bool { number.map { Categories.standardNumbers.contains($0) } ?? false }
}

/// 分類色塊的顏色，照大組分。使用者自己新增的、舊紀錄對不到分組的都算 other。
public enum CategoryTint: CaseIterable, Sendable {
    case food, transport, home, shopping, other, income
}

extension TxCategory {
    public var tint: CategoryTint {
        if kind == .income { return .income }
        switch group {
        case "吃喝": return .food
        case "交通": return .transport
        case "住家": return .home
        case "購物", "玩樂": return .shopping
        default: return .other
        }
    }
}

/// 常用分類畫面上的一組。
public struct CategoryGroup: Identifiable, Hashable, Sendable {
    public let name: String
    public let items: [TxCategory]

    public var id: String { name }
}

/// 內建分類的目錄。編號固定不變，紀錄靠編號引用。使用者改過的名字、自己新增的分類在 CategoryBook。
public enum Categories {
    /// 最早的 16 類在前面，「其他」永遠最後。新增的只能往後加，不能改既有的編號和名字。
    public static let all: [TxCategory] = expenses + incomes

    private static let expenses: [TxCategory] = [
        make(1, "飲食", .expense, "吃喝", "fork.knife"),
        make(2, "交通", .expense, "交通", "car.fill"),
        make(3, "購物", .expense, "購物", "bag.fill"),
        make(4, "日用", .expense, "住家", "basket.fill"),
        make(5, "居住", .expense, "住家", "house.fill"),
        make(6, "娛樂", .expense, "玩樂", "gamecontroller.fill"),
        make(7, "醫療", .expense, "身體", "cross.case.fill"),
        make(8, "學習", .expense, "學習與工作", "book.fill"),
        make(9, "訂閱", .expense, "玩樂", "repeat"),
        make(10, "旅行", .expense, "玩樂", "airplane"),
        make(11, "人情", .expense, "家人與人情", "gift.fill"),

        make(101, "早餐", .expense, "吃喝", "sunrise.fill"),
        make(102, "午餐", .expense, "吃喝", "sun.max.fill"),
        make(103, "晚餐", .expense, "吃喝", "sunset.fill"),
        make(104, "宵夜", .expense, "吃喝", "moon.stars.fill"),
        make(105, "飲料", .expense, "吃喝", "takeoutbag.and.cup.and.straw.fill"),
        make(106, "咖啡", .expense, "吃喝", "cup.and.saucer.fill"),
        make(107, "點心", .expense, "吃喝", "birthday.cake.fill"),
        make(108, "食材", .expense, "吃喝", "carrot.fill"),
        make(109, "聚餐", .expense, "吃喝", "person.3.fill"),
        make(110, "酒", .expense, "吃喝", "wineglass.fill"),

        // 叫「油錢」不叫「加油」：「加油」是文案的禁用字，單元測試會掃。
        make(111, "油錢", .expense, "交通", "fuelpump.fill"),
        make(112, "停車", .expense, "交通", "parkingsign.circle.fill"),
        make(113, "大眾運輸", .expense, "交通", "bus.fill"),
        make(114, "計程車", .expense, "交通", "car.side.fill"),
        make(115, "高鐵火車", .expense, "交通", "tram.fill"),
        make(116, "機票", .expense, "交通", "airplane.departure"),
        make(117, "保養維修", .expense, "交通", "wrench.and.screwdriver.fill"),

        make(118, "房租", .expense, "住家", "key.fill"),
        make(119, "水費", .expense, "住家", "drop.fill"),
        make(120, "電費", .expense, "住家", "bolt.fill"),
        make(121, "瓦斯", .expense, "住家", "flame.fill"),
        make(122, "網路", .expense, "住家", "wifi"),
        make(123, "電話費", .expense, "住家", "phone.fill"),
        make(124, "管理費", .expense, "住家", "building.2.fill"),
        make(125, "家具", .expense, "住家", "sofa.fill"),
        make(126, "家電", .expense, "住家", "refrigerator.fill"),
        make(127, "修繕", .expense, "住家", "hammer.fill"),

        make(128, "衣服", .expense, "購物", "tshirt.fill"),
        make(129, "鞋包", .expense, "購物", "handbag.fill"),
        make(130, "美妝", .expense, "購物", "paintbrush.pointed.fill"),
        make(131, "3C", .expense, "購物", "laptopcomputer"),

        make(132, "住宿", .expense, "玩樂", "bed.double.fill"),
        make(133, "電影", .expense, "玩樂", "film.fill"),
        make(134, "遊戲", .expense, "玩樂", "dice.fill"),
        make(135, "運動", .expense, "玩樂", "figure.run"),
        make(136, "音樂", .expense, "玩樂", "music.note"),
        make(137, "興趣", .expense, "玩樂", "paintpalette.fill"),

        make(138, "藥品", .expense, "身體", "pills.fill"),
        make(139, "保健", .expense, "身體", "leaf.fill"),
        make(140, "美髮", .expense, "身體", "scissors"),
        make(141, "健身", .expense, "身體", "dumbbell.fill"),

        make(142, "孝親", .expense, "家人與人情", "person.2.fill"),
        make(143, "孩子", .expense, "家人與人情", "figure.and.child.holdinghands"),
        make(144, "寵物", .expense, "家人與人情", "pawprint.fill"),
        make(145, "禮物", .expense, "家人與人情", "balloon.fill"),
        make(146, "捐款", .expense, "家人與人情", "heart.fill"),

        make(147, "書", .expense, "學習與工作", "books.vertical.fill"),
        make(148, "課程", .expense, "學習與工作", "graduationcap.fill"),
        make(149, "文具", .expense, "學習與工作", "pencil"),
        make(150, "辦公", .expense, "學習與工作", "briefcase.fill"),

        make(151, "保險", .expense, "錢", "umbrella.fill"),
        make(152, "稅", .expense, "錢", "building.columns.fill"),
        make(153, "手續費", .expense, "錢", "creditcard.fill"),
        make(154, "貸款利息", .expense, "錢", "percent"),
        make(155, "罰款", .expense, "錢", "exclamationmark.triangle.fill"),

        make(12, "其他", .expense, "錢", "ellipsis.circle.fill"),
    ]

    private static let incomes: [TxCategory] = [
        make(21, "薪水", .income, "工作", "banknote.fill"),
        make(22, "獎金", .income, "工作", "star.fill"),
        make(23, "投資", .income, "理財", "chart.line.uptrend.xyaxis"),

        make(201, "加班費", .income, "工作", "clock.fill"),
        make(202, "兼職", .income, "工作", "calendar.badge.clock"),
        make(203, "接案", .income, "工作", "doc.text.fill"),

        make(204, "股利", .income, "理財", "chart.pie.fill"),
        make(205, "利息", .income, "理財", "arrow.up.right.circle.fill"),
        make(206, "租金", .income, "理財", "building.fill"),

        make(207, "退款", .income, "退回與補助", "arrow.uturn.backward.circle.fill"),
        make(208, "退稅", .income, "退回與補助", "arrow.down.doc.fill"),
        make(209, "補助", .income, "退回與補助", "hand.thumbsup.fill"),

        make(210, "紅包", .income, "其他來源", "envelope.fill"),
        make(211, "零用錢", .income, "其他來源", "wallet.pass.fill"),
        make(212, "賣東西", .income, "其他來源", "tag.fill"),
        make(213, "中獎", .income, "其他來源", "trophy.fill"),

        make(24, "其他收入", .income, "其他來源", "ellipsis.circle.fill"),
    ]

    /// 使用者自己新增的那一組。
    public static let customGroup = "自己新增的"

    /// 挑圖示的清單：內建用到的，加上一些常用的。
    public static let icons: [String] = {
        var seen = Set<String>()
        return (all.map(\.icon) + extraIcons).filter { seen.insert($0).inserted }
    }()

    private static let extraIcons = [
        "cart.fill", "ticket.fill", "camera.fill", "headphones", "tv.fill", "desktopcomputer", "printer.fill",
        "gearshape.fill", "lightbulb.fill", "globe", "map.fill", "bicycle", "scooter", "ferry.fill", "sparkles",
        "bell.fill", "flag.fill", "trash.fill", "bandage.fill", "eye.fill", "ear.fill", "hare.fill", "tortoise.fill",
        "ladybug.fill", "crown.fill", "theatermasks.fill", "guitars.fill", "mic.fill", "snowflake", "circle.fill",
    ]

    /// 分組在「常用分類」畫面上的順序。
    private static let groupOrder = [
        "吃喝", "交通", "住家", "購物", "玩樂", "身體", "家人與人情", "學習與工作", "錢",
        "工作", "理財", "退回與補助", "其他來源",
    ]

    /// 沒動過設定時，記帳畫面顯示的就是最早的 16 類。
    public static let standardNumbers: [Int] = Array(1...12) + Array(21...24)

    public static func of(_ kind: TxType) -> [TxCategory] {
        all.filter { $0.kind == kind }
    }

    /// 某一種的所有分組，組裡照目錄順序。
    public static func groups(_ kind: TxType) -> [CategoryGroup] {
        let items = of(kind)
        return groupOrder.compactMap { name in
            let members = items.filter { $0.group == name }
            return members.isEmpty ? nil : CategoryGroup(name: name, items: members)
        }
    }

    public static func find(_ id: UUID?) -> TxCategory? {
        guard let id else { return nil }
        return byID[id]
    }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// 找不到分類的紀錄算在這一類。
    static func fallback(_ kind: TxType) -> TxCategory {
        named(kind == .expense ? "其他" : "其他收入")
    }

    /// 測試與示範資料用：照名字找。
    public static func named(_ name: String) -> TxCategory {
        all.first { $0.name == name }!
    }

    private static func make(
        _ number: Int, _ name: String, _ kind: TxType, _ group: String, _ icon: String
    ) -> TxCategory {
        let id = UUID(uuidString: String(format: "BA1CA100-0000-4000-8000-%012d", number))!
        return TxCategory(number: number, id: id, name: name, kind: kind, group: group, icon: icon)
    }
}
