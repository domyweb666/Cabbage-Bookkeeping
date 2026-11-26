import Charts
import FinanceCore
import SwiftUI

/// 看法「圓餅」：這個月支出各類佔多少。多米 2026-11-26 要的（.analytics/06-08 原本不放圓餅，改成可選的看法）。
/// 前 5 類各一塊，其他合成一塊；點一塊或一列進那一類的明細，點合起來的那塊就分開看全部。
struct PieModeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let report: MonthReport
    let onPick: (CategoryPick) -> Void

    @State private var showAll = false
    @State private var picked: Int?

    var body: some View {
        let slices = Analysis.slices(
            of: report.categories, top: showAll ? report.categories.count : Analysis.pieTop
        )
        let colors = Self.colors(for: slices)
        VStack(alignment: .leading, spacing: Gap.group) {
            AnalysisCardTitle(Words.AnalysisModes.pieTitle)
            if slices.isEmpty {
                AnalysisAnswer(AnalysisText.headline(report), id: "pieAnswer")
            } else {
                AnalysisAnswer(AnalysisText.categoryAnswer(report) ?? AnalysisText.headline(report), id: "pieAnswer")
                chart(slices, colors: colors)
                VStack(spacing: 0) {
                    ForEach(slices) { slice in
                        row(slice, color: colors[slice.id] ?? Theme.band)
                    }
                }
                if showAll, report.categories.count - 1 > Analysis.pieTop {
                    Button(Words.AnalysisModes.showTop) { showAll = false }
                        .font(Typo.subheadline.font.weight(.semibold))
                        .frame(minHeight: Metric.touch)
                        .accessibilityIdentifier("pieShowTop")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onChange(of: report.month) { showAll = false }
    }

    // MARK: - 圖

    private func chart(_ slices: [PieSlice], colors: [String: Color]) -> some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("金額", slice.amount),
                innerRadius: .ratio(PieSize.inner),
                angularInset: PieSize.inset
            )
            .foregroundStyle(colors[slice.id] ?? Theme.band)
            .cornerRadius(PieSize.corner)
            .accessibilityLabel(name(of: slice))
            .accessibilityValue(Words.AnalysisModes.slice(name: name(of: slice), amount: slice.amount, percent: slice.percent))
        }
        .chartLegend(.hidden)
        .chartAngleSelection(value: $picked)
        .frame(height: PieSize.height)
        .onChange(of: picked) { _, value in
            guard let value, let slice = Self.slice(at: value, in: slices) else { return }
            picked = nil
            open(slice)
        }
        .accessibilityIdentifier("pieChart")
    }

    // MARK: - 下面的列

    private func row(_ slice: PieSlice, color: Color) -> some View {
        Button {
            open(slice)
        } label: {
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: Gap.group) {
                Circle()
                    .fill(color)
                    .frame(width: PieSize.swatch, height: PieSize.swatch)
                    .accessibilityHidden(true)
                if typeSize.isAccessibilitySize {
                    // 字放大時名字一行、金額和佔比一行，不擠在同一排。
                    VStack(alignment: .leading, spacing: Gap.tight) {
                        Text(name(of: slice)).foregroundStyle(Theme.primaryText)
                        figures(slice)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(name(of: slice)).foregroundStyle(Theme.primaryText)
                    Spacer(minLength: Gap.item)
                    figures(slice)
                }
                Image(systemName: "chevron.right")
                    .font(Typo.caption.font)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            .font(Typo.subheadline.font)
            .frame(minHeight: Metric.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Words.AnalysisModes.slice(name: name(of: slice), amount: slice.amount, percent: slice.percent))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("slice_\(name(of: slice))")
    }

    private func figures(_ slice: PieSlice) -> some View {
        HStack(spacing: Gap.item) {
            AmountText(text: Money.format(slice.amount), font: Typo.subheadline.font.weight(.medium))
            Text(Words.AnalysisModes.percent(slice.percent))
                .font(Typo.subheadline.font.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - 動作與小工具

    private func open(_ slice: PieSlice) {
        if let category = slice.category {
            onPick(CategoryPick(month: report.month, categoryId: category.id))
        } else {
            showAll = true
        }
    }

    private func name(of slice: PieSlice) -> String {
        slice.category?.name ?? AnalysisText.restSlice(slice.merged)
    }

    /// 點到的位置（從 0 累加的金額）落在哪一塊。
    private static func slice(at value: Int, in slices: [PieSlice]) -> PieSlice? {
        var start = 0
        for slice in slices {
            if value < start + slice.amount { return slice }
            start += slice.amount
        }
        return slices.last
    }

    /// 顏色照分類的大組（Theme.tint）。同一組出現第二次以後變淡，相鄰兩塊才分得開。合起來的那塊用灰色。
    private static func colors(for slices: [PieSlice]) -> [String: Color] {
        var seen: [CategoryTint: Int] = [:]
        var result: [String: Color] = [:]
        for slice in slices {
            guard let category = slice.category else {
                result[slice.id] = Theme.band
                continue
            }
            let count = seen[category.tint, default: 0]
            seen[category.tint] = count + 1
            let opacity = PieSize.repeatOpacity[min(count, PieSize.repeatOpacity.count - 1)]
            result[slice.id] = Theme.tint(category.tint).opacity(opacity)
        }
        return result
    }
}

/// 圓餅的尺寸，只有這個檔用。
private enum PieSize {
    static let height: CGFloat = 220
    /// 中間挖空的比例（甜甜圈）。
    static let inner: CGFloat = 0.58
    /// 兩塊之間的縫。
    static let inset: CGFloat = 1.5
    static let corner: CGFloat = 4
    static let swatch: CGFloat = 12
    /// 同一組的第幾塊用多深。
    static let repeatOpacity: [Double] = [1, 0.62, 0.38]
}
