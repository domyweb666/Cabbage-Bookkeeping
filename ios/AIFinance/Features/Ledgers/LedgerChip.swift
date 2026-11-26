import FinanceCore
import SwiftUI

/// 記帳頁月份旁邊的「帳本名 ▾」（K4、K5）。點下去是系統選單：每本這個月花多少，打勾的是現在這本，最下面新增帳本。
/// 只有一本時不放這顆（由 LedgerView 決定）。
struct LedgerChip: View {
    @Environment(LedgerModel.self) private var model

    let onAdd: () -> Void

    var body: some View {
        let current = model.currentLedger
        Menu {
            ForEach(model.ledgerList) { ledger in
                let spent = Money.format(model.monthExpense(of: ledger.id))
                if ledger.id == model.currentLedgerId {
                    Button {} label: {
                        Label(ledger.name, systemImage: "checkmark")
                        Text(spent)
                    }
                } else {
                    Button {
                        model.switchLedger(to: ledger.id)
                    } label: {
                        Text(ledger.name)
                        Text(spent)
                    }
                }
            }
            Divider()
            Button(action: onAdd) {
                Label(Words.Ledgers.add, systemImage: "plus")
            }
        } label: {
            HStack(spacing: Gap.item) {
                Circle()
                    .fill(current.color.color)
                    .frame(width: Gap.group, height: Gap.group)
                Text(current.name)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(Typo.footnote.font.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .font(Typo.subheadline.font.weight(.medium))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, Gap.group)
            .frame(minHeight: Metric.pickerHeight)
            .background(Theme.card, in: Capsule())
            .frame(minHeight: Metric.touch)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Words.Ledgers.chipSpoken(current.name))
        .accessibilityIdentifier("ledgerChip")
    }
}
