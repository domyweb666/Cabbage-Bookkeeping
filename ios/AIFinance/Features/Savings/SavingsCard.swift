import FinanceCore
import SwiftUI

/// 存錢卡（K12）：第一行直接說還差多少，下面一條進度、已經存多少、哪天前多少，再一句「一個月存多少就到」。
/// 存到了或過了那天，第一行換成結果，按鈕換成「再存一次」。還沒開始存錢時是一列「開始存錢」。
/// 分析頁、記帳頁點那一條打開的頁、設定頁的「存錢」都用這張，資料只看目前這本帳。
struct SavingsCard: View {
    @Environment(LedgerModel.self) private var model

    @State private var editing: SavingsEditTarget?

    var body: some View {
        Group {
            if let goal = model.savingsGoal, let progress = model.savings {
                filled(goal, progress)
            } else {
                startRow
            }
        }
        .sheet(item: $editing) { SavingsSheet(goal: $0.goal) }
    }

    private var startRow: some View {
        Button {
            editing = SavingsEditTarget(goal: nil)
        } label: {
            HStack(spacing: Gap.group) {
                VStack(alignment: .leading, spacing: Gap.tight) {
                    Text(Words.Saving.start)
                        .font(Typo.headline.font)
                        .foregroundStyle(Theme.accent)
                    Text(Words.Saving.startHint)
                        .font(Typo.footnote.font)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Gap.item)
                Image(systemName: "chevron.right")
                    .font(Typo.footnote.font.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .disabled(model.loadFailed)
        .accessibilityIdentifier("savingsStart")
    }

    private func filled(_ goal: SavingsGoal, _ progress: SavingsProgress) -> some View {
        let today = model.today
        let finished = progress.isReached || progress.isOver(today: today)
        return VStack(alignment: .leading, spacing: Gap.group) {
            VStack(alignment: .leading, spacing: Gap.tight) {
                Text(goal.name.isEmpty ? Words.Saving.title : "\(Words.Saving.title)・\(goal.name)")
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.secondaryText)
                Text(SavingsText.headline(progress, today: today))
                    .font(Typo.headline.font)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("savingsHeadline")
            }
            if progress.hasIncome {
                VStack(alignment: .leading, spacing: Gap.item) {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.primaryText)
                        .accessibilityHidden(true)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            caption(SavingsText.saved(progress))
                            Spacer(minLength: Gap.group)
                            caption(SavingsText.deadline(progress))
                        }
                        VStack(alignment: .leading, spacing: Gap.tight) {
                            caption(SavingsText.saved(progress))
                            caption(SavingsText.deadline(progress))
                        }
                    }
                }
            } else {
                caption(SavingsText.deadline(progress))
            }
            if let plan = SavingsText.plan(progress, today: today) {
                Text(plan)
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("savingsPlan")
            }
            RowDivider()
            Button {
                editing = SavingsEditTarget(goal: finished ? nil : goal)
            } label: {
                HStack {
                    Text(finished ? Words.Saving.again : Words.Saving.edit)
                    Spacer(minLength: Gap.item)
                    Image(systemName: "chevron.right")
                        .font(Typo.footnote.font.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(Typo.subheadline.font)
                .foregroundStyle(Theme.accent)
                .frame(minHeight: Metric.touch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.row)
            .disabled(model.loadFailed)
            .accessibilityIdentifier(finished ? "savingsAgain" : "savingsEdit")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("savingsCard")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Typo.footnote.font.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
    }
}

/// 要開的存錢畫面。goal 是 nil 代表開始一個新的。
struct SavingsEditTarget: Identifiable {
    let goal: SavingsGoal?

    var id: String { goal?.id.uuidString ?? "new" }
}

/// 記帳頁那一條（K11）：哪天前存到多少、還差多少，下面一條細的進度。點了打開存錢那一頁。
struct SavingsBar: View {
    @Environment(LedgerModel.self) private var model

    let progress: SavingsProgress
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Gap.item) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Gap.item) {
                        title
                        Spacer(minLength: Gap.item)
                        amount
                    }
                    VStack(alignment: .leading, spacing: Gap.tight) {
                        title
                        amount
                    }
                }
                ProgressView(value: progress.fraction)
                    .tint(Theme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SavingsText.spoken(progress, today: model.today))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("savingsBar")
    }

    private var title: some View {
        Label(SavingsText.barTitle(progress), systemImage: "banknote")
            .font(Typo.subheadline.font)
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
    }

    private var amount: some View {
        Text(SavingsText.short(progress, today: model.today))
            .font(Typo.subheadline.font.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1)
    }
}

/// 存錢那一頁：記帳頁點那一條、設定頁點「存錢」都到這裡。還沒開始時說怎麼開始。
struct SavingsPage: View {
    @Environment(LedgerModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Gap.section) {
                if model.savingsGoal == nil {
                    VStack(alignment: .leading, spacing: Gap.item) {
                        Text(Words.Saving.emptyTitle)
                            .font(Typo.title3.font)
                            .foregroundStyle(Theme.primaryText)
                        Text(Words.Saving.emptyMessage)
                            .font(Typo.subheadline.font)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                SavingsCard()
            }
            .padding(Gap.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Words.Saving.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
