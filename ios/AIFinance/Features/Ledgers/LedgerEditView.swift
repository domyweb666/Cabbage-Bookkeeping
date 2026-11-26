import FinanceCore
import SwiftUI

/// 新增或改一本帳（K10）：只問名字和顏色。新增的按「建立帳本」就換過去。
/// ledger 是 nil 代表新增。
struct LedgerEditView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let ledger: Ledger?

    @State private var name = ""
    @State private var color = LedgerColor.blue
    @State private var opened: (String, LedgerColor)?
    @State private var saveFailed = false
    @FocusState private var focused: Bool

    private var problem: Ledgers.Problem? { model.ledgerProblem(name, excluding: ledger?.id) }
    private var isDirty: Bool { opened.map { $0.0 != name || $0.1 != color } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Gap.section) {
                    namePart
                    colorPart
                    Text(Words.Ledgers.note)
                        .font(Typo.footnote.font)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Gap.screenMargin)
                .padding(.vertical, Gap.group)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { saveButton }
            .navigationTitle(ledger == nil ? Words.Ledgers.add : Words.Ledgers.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Words.cancel) { dismiss() }
                        .accessibilityIdentifier("ledgerCancel")
                }
            }
            .alert(Words.Failure.saveTitle, isPresented: $saveFailed) {
                Button(Words.ok, role: .cancel) {}
            } message: {
                Text(Words.Failure.saveMessage)
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(isDirty)
        .onAppear(perform: load)
    }

    private var namePart: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            Text(Words.Ledgers.name)
                .font(Typo.footnote.font)
                .foregroundStyle(Theme.secondaryText)
            TextField(
                Words.Ledgers.name, text: $name,
                prompt: Text(Words.Ledgers.namePrompt).foregroundStyle(Theme.secondaryText)
            )
            .font(Typo.body.font)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit { focused = false }
            .frame(minHeight: Metric.row)
            .padding(.horizontal, Gap.cardPad)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityIdentifier("ledgerName")
            if problem == .duplicate {
                Text(Words.Ledgers.duplicate)
                    .font(Typo.footnote.font)
                    .foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("ledgerDuplicate")
            }
        }
    }

    private var colorPart: some View {
        VStack(alignment: .leading, spacing: Gap.item) {
            Text(Words.Ledgers.color)
                .font(Typo.footnote.font)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 0) {
                ForEach(LedgerColor.allCases, id: \.self) { option in
                    Button {
                        color = option
                        Haptics.selected()
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: Metric.pickerHeight, height: Metric.pickerHeight)
                            .overlay {
                                if option == color {
                                    Image(systemName: "checkmark")
                                        .font(Typo.footnote.font.weight(.bold))
                                        .foregroundStyle(Theme.onTint)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: Metric.touch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(Words.Ledgers.colorName(option))
                    .accessibilityAddTraits(option == color ? .isSelected : [])
                    .accessibilityIdentifier("ledgerColor_\(option.rawValue)")
                }
            }
            .padding(.vertical, Gap.item)
            .padding(.horizontal, Gap.item)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(ledger == nil ? Words.Ledgers.create : Words.Ledgers.save)
                .frame(maxWidth: .infinity, minHeight: Metric.button)
                .primaryFill()
                .clipShape(Capsule())
        }
        .buttonStyle(.press)
        .disabled(problem != nil)
        .accessibilityIdentifier("ledgerSave")
        .padding(.horizontal, Gap.screenMargin)
        .padding(.vertical, Gap.group)
        .background(Theme.background)
    }

    private func load() {
        guard opened == nil else { return }
        if let ledger {
            name = ledger.name
            color = ledger.color
        } else {
            // 新的一本先給一個跟現在不同的顏色，一眼分得出來。
            let used = Set(model.ledgerList.map(\.color))
            color = LedgerColor.allCases.first { !used.contains($0) } ?? .blue
            focused = true
        }
        opened = (name, color)
    }

    private func save() {
        let ok: Bool
        if let ledger {
            ok = model.updateLedger(ledger, name: name, color: color)
        } else {
            ok = model.addLedger(name: name, color: color)
        }
        if ok { dismiss() } else { saveFailed = true }
    }
}
