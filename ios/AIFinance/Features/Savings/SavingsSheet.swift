import FinanceCore
import SwiftUI

/// 開始存錢、改存錢（K14）：想存多少、在哪天前、存來做什麼（可以不填）。下面直接算好一個月要存多少。
/// goal 是 nil 代表開始一個新的（這本原本有的會換掉）。
struct SavingsSheet: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal?

    @State private var amountText = ""
    @State private var endDate = Date()
    @State private var name = ""
    @State private var opened: String?
    @State private var saveFailed = false
    @State private var confirmStop = false
    @FocusState private var focus: Field?

    private enum Field { case amount, name }

    private var amount: Int? { Money.parse(amountText).flatMap { $0 > 0 ? $0 : nil } }
    private var endsOn: String { model.days.day(of: endDate) }
    /// 最早可以選明天。
    private var earliest: Date { Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() }
    private var snapshot: String { "\(amountText)|\(endsOn)|\(name)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Gap.group) {
                    amountPart
                    datePart
                    namePart
                    if let amount, let line = SavingsText.preview(target: amount, today: model.today, endsOn: endsOn) {
                        Text(line)
                            .font(Typo.headline.font.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, Gap.cardPad)
                            .accessibilityIdentifier("savingsPreview")
                    }
                    Text(SavingsText.howItWorks)
                        .font(Typo.footnote.font)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, Gap.cardPad)
                        .fixedSize(horizontal: false, vertical: true)
                    if goal != nil {
                        Button(Words.Saving.stop, role: .destructive) { confirmStop = true }
                            .frame(minHeight: Metric.touch)
                            .padding(.top, Gap.section)
                            .accessibilityIdentifier("savingsStop")
                    }
                }
                .padding(.horizontal, Gap.screenMargin)
                .padding(.vertical, Gap.group)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { saveButton }
            .navigationTitle(goal == nil ? Words.Saving.title : Words.Saving.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Words.cancel) { dismiss() }
                        .accessibilityIdentifier("savingsCancel")
                }
            }
            .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
                Button(Words.ok, role: .cancel) {}
            } message: {
                Text(Words.Failure.saveMessage)
            }
            .alert(Words.Saving.stopTitle, isPresented: $confirmStop) {
                Button(Words.Saving.stop, role: .destructive) {
                    if let goal, model.stopSavings(goal) { dismiss() } else { saveFailed = true }
                }
                Button(Words.cancel, role: .cancel) {}
            } message: {
                Text(Words.Saving.stopMessage)
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(opened.map { $0 != snapshot } ?? false)
        .onAppear(perform: load)
    }

    private var amountPart: some View {
        VStack(alignment: .leading, spacing: Gap.tight) {
            Text(Words.Saving.amount)
                .font(Typo.footnote.font)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: Gap.tight) {
                Text(Words.currency)
                    .font(Typo.subheadline.font)
                    .foregroundStyle(Theme.secondaryText)
                TextField(Words.Saving.amount, text: $amountText)
                    .font(Typo.largeTitle.font.monospacedDigit())
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .amount)
                    .accessibilityIdentifier("savingsAmount")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var datePart: some View {
        DatePicker(Words.Saving.deadline, selection: $endDate, in: earliest..., displayedComponents: .date)
            .font(Typo.body.font)
            .foregroundStyle(Theme.primaryText)
            .frame(minHeight: Metric.touch)
            .card()
            .accessibilityIdentifier("savingsDate")
    }

    private var namePart: some View {
        TextField(
            Words.Saving.name, text: $name,
            prompt: Text(Words.Saving.name).foregroundStyle(Theme.secondaryText)
        )
        .font(Typo.body.font)
        .focused($focus, equals: .name)
        .submitLabel(.done)
        .onSubmit { focus = nil }
        .frame(minHeight: Metric.row)
        .padding(.horizontal, Gap.cardPad)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityIdentifier("savingsName")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(goal == nil ? Words.Saving.start : Words.Saving.save)
                .frame(maxWidth: .infinity, minHeight: Metric.button)
                .primaryFill()
                .clipShape(Capsule())
        }
        .buttonStyle(.press)
        .disabled(amount == nil || model.loadFailed)
        .accessibilityIdentifier("savingsSave")
        .padding(.horizontal, Gap.screenMargin)
        .padding(.vertical, Gap.group)
        .background(Theme.background)
    }

    private func load() {
        guard opened == nil else { return }
        if let goal {
            amountText = String(goal.target)
            endDate = model.days.date(of: goal.endsOn) ?? endDate
            name = goal.name
        } else {
            // 先給三個月後，大多數人改日子就好。
            endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
            focus = .amount
        }
        opened = snapshot
    }

    private func save() {
        guard let amount else { return }
        let ok: Bool
        if let goal {
            ok = model.updateSavings(goal, name: name, target: amount, endsOn: endsOn)
        } else {
            ok = model.startSavings(name: name, target: amount, endsOn: endsOn)
        }
        if ok { dismiss() } else { saveFailed = true }
    }
}
