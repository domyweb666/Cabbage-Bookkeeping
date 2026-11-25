import FinanceCore
import SwiftUI

/// 要補的是哪一段。
struct EstimateTarget: Identifiable {
    let range: DayRange

    var id: String { range.from }
}

/// 補一個大概的數字。日期系統帶好，打一個總數就好。
struct EstimateSheet: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let range: DayRange

    @State private var text = ""
    @State private var saveFailed = false
    @FocusState private var focused: Bool

    private var amount: Int? { Money.parse(text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Gap.group) {
                    Text(AnalysisText.estimateTitle(range))
                        .font(Typo.body.font.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Gap.item) {
                        Text(Words.currency).foregroundStyle(Theme.secondaryText)
                        TextField(Words.Analysis.estimateAmount, text: $text)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .accessibilityIdentifier("estimateAmount")
                    }
                    .font(Typo.title2.font.weight(.regular).monospacedDigit())
                    .card()

                    Text(Words.Analysis.estimateNote)
                        .font(Typo.footnote.font)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Gap.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(AnalysisText.estimateLink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Words.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Words.Analysis.estimateSave) { save() }
                        .fontWeight(.semibold)
                        .disabled(amount == nil)
                        .accessibilityIdentifier("estimateSave")
                }
            }
            .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
                Button(Words.ok, role: .cancel) {}
            } message: {
                Text(Words.Failure.saveMessage)
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(!text.isEmpty)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func save() {
        guard let amount else { return }
        if model.addEstimate(range: range, amount: amount) { dismiss() } else { saveFailed = true }
    }
}
