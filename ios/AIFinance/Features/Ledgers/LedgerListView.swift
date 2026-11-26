import FinanceCore
import SwiftUI

/// 要編輯的帳本。ledger 是 nil 代表新增。
struct LedgerTarget: Identifiable {
    let ledger: Ledger?

    var id: String { ledger?.id.uuidString ?? "new" }
}

/// 設定 › 帳本（K7）：一本一列，寫這個月花多少，打勾的是現在這本。
/// 點一下換過去；左滑或按住可以改名字、刪除（最後一本不能刪）；最下面新增帳本。
struct LedgerListView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var target: LedgerTarget?
    @State private var deleting: Ledger?

    var body: some View {
        Group {
            if model.loadFailed {
                EmptyMessage(title: Words.Failure.loadTitle, message: Words.Failure.loadMessage)
            } else {
                List {
                    Section {
                        ForEach(model.ledgerList) { ledger in
                            row(ledger)
                        }
                    } footer: {
                        Text(model.hasManyLedgers ? Words.Ledgers.listHint : Words.Ledgers.note)
                            .font(Typo.footnote.font)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .ledgerList()
                .animation(reduceMotion ? Motion.changeReduced : Motion.change, value: model.ledgerList)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle(Words.Ledgers.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $target) { LedgerEditView(ledger: $0.ledger) }
        .alert(
            Words.Ledgers.deleteTitle(deleting?.name ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button(Words.Ledgers.deleteConfirm, role: .destructive) {
                if let deleting { _ = model.deleteLedger(deleting) }
                deleting = nil
            }
            Button(Words.cancel, role: .cancel) { deleting = nil }
        } message: {
            Text(Words.Ledgers.deleteMessage(records: deleting.map { model.recordCount(of: $0.id) } ?? 0))
        }
    }

    private func row(_ ledger: Ledger) -> some View {
        let isCurrent = ledger.id == model.currentLedgerId
        return Button {
            model.switchLedger(to: ledger.id)
        } label: {
            HStack(spacing: Gap.group) {
                Image(systemName: "book.closed.fill")
                    .font(Typo.body.font)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .foregroundStyle(Theme.onTint)
                    .frame(width: Theme.Part.badge, height: Theme.Part.badge)
                    .background(
                        ledger.color.color,
                        in: RoundedRectangle(cornerRadius: Theme.badgeRadius, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Gap.tight) {
                    Text(ledger.name)
                        .font(Typo.headline.font)
                        .foregroundStyle(Theme.primaryText)
                    Text(Words.Ledgers.monthSpent(model.monthExpense(of: ledger.id)))
                        .font(Typo.footnote.font.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: Gap.item)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(Typo.headline.font)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Metric.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("ledgerRow_\(ledger.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.hasManyLedgers {
                Button(role: .destructive) {
                    deleting = ledger
                } label: {
                    Label(Words.Ledgers.delete, systemImage: "trash")
                }
            }
            Button {
                target = LedgerTarget(ledger: ledger)
            } label: {
                Label(Words.Ledgers.rename, systemImage: "pencil")
            }
            .tint(Theme.accent)
        }
        .contextMenu {
            Button {
                target = LedgerTarget(ledger: ledger)
            } label: {
                Label(Words.Ledgers.rename, systemImage: "pencil")
            }
            if model.hasManyLedgers {
                Button(role: .destructive) {
                    deleting = ledger
                } label: {
                    Label(Words.Ledgers.delete, systemImage: "trash")
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Gap.group) {
            ToastSlot()
            Button {
                target = LedgerTarget(ledger: nil)
            } label: {
                Label(Words.Ledgers.add, systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: Metric.button)
                    .primaryFill()
                    .clipShape(Capsule())
            }
            .buttonStyle(.press)
            .disabled(model.loadFailed)
            .accessibilityIdentifier("ledgerAdd")
        }
        .padding(.horizontal, Gap.screenMargin)
        .padding(.vertical, Gap.group)
        .aboveTabBar()
        .background(Theme.background)
    }
}
