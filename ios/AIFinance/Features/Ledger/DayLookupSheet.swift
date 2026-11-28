import FinanceCore
import SwiftUI

/// 明細頁點月份跳出來：上面月曆點一天，下面就是那天的每一筆和總共花多少（多米 2026-11-28）。
/// 點一筆可以改。日期最多選到今天。
struct DayLookupSheet: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var editing: Txn?

    private var latest: Date { model.days.date(of: model.today) ?? Date() }
    private var day: String { model.days.day(of: date) }

    var body: some View {
        let section = model.sections.first { $0.day == day }
        let items = section?.items ?? []
        NavigationStack {
            List {
                Section {
                    DatePicker(Words.DayLookup.pick, selection: $date, in: ...latest, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.accent)
                        .accessibilityIdentifier("dayLookupPicker")
                }
                Section {
                    if items.isEmpty {
                        Text(Words.DayLookup.empty)
                            .font(Typo.subheadline.font)
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("dayLookupEmpty")
                    } else {
                        ForEach(items) { item in
                            Button {
                                editing = item
                            } label: {
                                TxnRow(item: item)
                            }
                            .buttonStyle(.row)
                        }
                    }
                } header: {
                    Text(Words.DayLookup.header(day: model.title(for: day), count: items.count, total: section?.expenseTotal ?? 0))
                        .font(Typo.footnote.font.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(nil)
                        .accessibilityIdentifier("dayLookupHeader")
                }
            }
            .ledgerList()
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(Words.DayLookup.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Words.done) { dismiss() }
                        .accessibilityIdentifier("dayLookupDone")
                }
            }
            .sheet(item: $editing) { EntrySheet(mode: .edit($0)) }
        }
        .tint(Theme.accent)
        .presentationDragIndicator(.visible)
        .onAppear { date = latest }
    }
}

extension Words {
    enum DayLookup {
        static let title = "查某一天"
        static let pick = "日期"
        static let empty = "這天沒有紀錄。"
        static let openHint = "點一下用月曆查某一天花了多少"

        static func header(day: String, count: Int, total: Int) -> String {
            count == 0 ? day : "\(day)　\(count) 筆，花了 \(Money.grouped(total))"
        }
    }
}
