import FinanceCore
import SwiftUI

/// 回答卡（規格 7.4）：答案與「依據：N 筆」。不寫入交易。
struct AnswerCardView: View {
    let card: AnswerCard
    let onEvidence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(card.question)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            Text(card.answer.answer)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if card.answer.evidenceCount > 0 {
                Button(action: onEvidence) {
                    HStack(spacing: 4) {
                        Text("依據：\(card.answer.evidenceCount) 筆")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("evidenceButton")
            }
        }
        .padding(.vertical, 4)
    }
}

/// 點「依據」後列出實際是哪些交易。
struct EvidenceListView: View {
    @Environment(TimelineViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let card: AnswerCard

    var body: some View {
        let ids = card.answer.evidenceIds
        let items = model.transactions(withIds: ids)

        NavigationStack {
            List {
                Section {
                    Text(card.answer.answer)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                } header: {
                    Text(card.question).textCase(nil)
                }

                Section {
                    if items.isEmpty {
                        Text("這些紀錄目前不在手機上，可能已經刪除。")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(items) { item in
                        HStack {
                            TransactionRow(item: item, category: model.category(item.categoryId))
                            Text(shortDay(item.occurredOn))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                } header: {
                    Text("依據的 \(card.answer.evidenceCount) 筆紀錄").textCase(nil)
                } footer: {
                    if items.count < ids.count {
                        Text("有 \(ids.count - items.count) 筆已經刪除或不在手機上。")
                    } else if card.answer.evidenceCount > ids.count {
                        Text("筆數較多，這裡只列出最近的 \(ids.count) 筆。")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("依據")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    /// "2026-11-15" → "11/15"
    private func shortDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return day }
        return "\(m)/\(d)"
    }
}
