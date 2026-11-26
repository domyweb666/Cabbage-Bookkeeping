import GoogleMobileAds
import SwiftUI
import UIKit

/// 明細、分析頁最下面的橫幅廣告（多米 2026-11-27 選的推薦方案）。
/// - 記一筆頁不放，那頁要一直順手。
/// - 只放非個人化廣告：不看使用者是誰、不跳「允許追蹤」（.uiux/廣告方案-2026-11-26.md）。
/// - 還沒拿到廣告、或拿不到，就不佔位置，不留一塊空白。
struct AdSlot: View {
    @State private var height: CGFloat = 0

    var body: some View {
        if let unitID = Ads.bannerUnitID {
            GeometryReader { proxy in
                AdBanner(unitID: unitID, width: proxy.size.width, height: $height)
                    .frame(width: proxy.size.width, height: height)
            }
            .frame(height: height)
            .clipped()
            .accessibilityIdentifier("adBanner")
        }
    }
}

/// 廣告用到的編號與開關。
enum Ads {
    /// Google 公開的測試橫幅編號，Debug 版一律用它，不會算到真的點擊。
    private static let testBannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    /// 這次要放的橫幅編號；nil 就不放。
    /// Release 版讀 Info.plist 的 BaicaiBannerUnitID，多米還沒給正式編號前是空的，正式版就不出廣告。
    static let bannerUnitID: String? = {
        guard AppConfig.current.showsAds else { return nil }
        #if DEBUG
        return testBannerUnitID
        #else
        let value = Bundle.main.object(forInfoDictionaryKey: "BaicaiBannerUnitID") as? String ?? ""
        return value.isEmpty ? nil : value
        #endif
    }()

    /// 開 app 時叫一次。沒有要放廣告就不啟動 SDK。
    @MainActor
    static func start() {
        guard bannerUnitID != nil else { return }
        MobileAds.shared.start(completionHandler: nil)
    }

    /// 每次要廣告都帶 npa=1：只要非個人化廣告。
    static func request() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }
}

/// 包 Google 的 BannerView。寬度跟著畫面，高度由廣告決定，拿到才回報。
private struct AdBanner: UIViewRepresentable {
    let unitID: String
    let width: CGFloat
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: max(width, 320)))
        banner.adUnitID = unitID
        banner.delegate = context.coordinator
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        // 寬度量到了、或變了才要一次廣告，不每次畫面更新都重要。
        guard width > 0, context.coordinator.loadedWidth != width else { return }
        context.coordinator.loadedWidth = width
        banner.adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
        banner.rootViewController = Self.rootViewController
        banner.load(Ads.request())
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        var loadedWidth: CGFloat = 0
        private let height: Binding<CGFloat>

        init(height: Binding<CGFloat>) { self.height = height }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            height.wrappedValue = bannerView.adSize.size.height
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // 沒網路或沒廣告可放：收起來，不留空白。
            height.wrappedValue = 0
        }
    }
}
