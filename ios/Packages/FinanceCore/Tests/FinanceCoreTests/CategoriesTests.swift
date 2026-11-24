import FinanceCore
import XCTest
#if canImport(AppKit)
import AppKit
#endif

/// 內建分類一定有編號。
private struct Numbered {
    let number: Int
    let kind: TxType

    init?(_ category: TxCategory) {
        guard let number = category.number else { return nil }
        self.number = number
        kind = category.kind
    }
}

final class CategoriesTests: XCTestCase {
    /// 最早的 16 類：編號、名字、順序都不准變，舊紀錄靠它。
    private let original: [(Int, String)] = [
        (1, "飲食"), (2, "交通"), (3, "購物"), (4, "日用"), (5, "居住"), (6, "娛樂"),
        (7, "醫療"), (8, "學習"), (9, "訂閱"), (10, "旅行"), (11, "人情"), (12, "其他"),
        (21, "薪水"), (22, "獎金"), (23, "投資"), (24, "其他收入"),
    ]

    func testOriginalCategoriesNeverChange() {
        for (number, name) in original {
            let category = Categories.named(name)
            XCTAssertEqual(category.number, number)
            XCTAssertEqual(category.id.uuidString, String(format: "BA1CA100-0000-4000-8000-%012d", number))
            XCTAssertEqual(category.kind, number < 20 ? .expense : .income)
        }
        XCTAssertEqual(Categories.standardNumbers, original.map { $0.0 })
    }

    func testNumbersIdsAndNamesAreUnique() {
        let all = Categories.all
        XCTAssertEqual(Set(all.compactMap(\.number)).count, all.count)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.name)).count, all.count)
        XCTAssertFalse(all.contains { $0.name.isEmpty || $0.name.count > 4 }, "格子放不下太長的名字")
    }

    func testNewNumbersStayInTheirRange() {
        let known = Set(original.map { $0.0 })
        for category in Categories.all.compactMap(Numbered.init) where !known.contains(category.number) {
            XCTAssertTrue((category.kind == .expense ? 101...199 : 201...299).contains(category.number))
        }
    }

    func testEveryCategoryIsInANonEmptyGroup() {
        for kind in TxType.allCases {
            let groups = Categories.groups(kind)
            XCTAssertFalse(groups.contains { $0.items.isEmpty })
            XCTAssertEqual(Set(groups.map(\.name)).count, groups.count)
            XCTAssertEqual(
                Set(groups.flatMap(\.items).map(\.id)), Set(Categories.of(kind).map(\.id)), "有分類沒被分到組"
            )
        }
    }

    func testIconListHasNoDuplicates() {
        XCTAssertEqual(Set(Categories.icons).count, Categories.icons.count)
        XCTAssertTrue(Set(Categories.all.map(\.icon)).isSubset(of: Categories.icons))
    }

    func testIconsAreDifferentWithinAKind() {
        for kind in TxType.allCases {
            let icons = Categories.of(kind).map(\.icon)
            XCTAssertEqual(Set(icons).count, icons.count)
        }
    }

    #if canImport(AppKit)
    /// 圖示名字打錯不會編譯失敗，畫面上會是一塊空白，所以在這裡問系統有沒有這個圖示。
    func testEveryIconExists() {
        for icon in Categories.icons {
            XCTAssertNotNil(NSImage(systemSymbolName: icon, accessibilityDescription: nil), "圖示 \(icon) 不存在")
        }
    }
    #endif
}
