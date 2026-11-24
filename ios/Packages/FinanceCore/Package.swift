// swift-tools-version: 5.9
import PackageDescription

// 純邏輯：只依賴 Foundation，單元測試不需要模擬器。
let package = Package(
    name: "FinanceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FinanceCore", targets: ["FinanceCore"]),
    ],
    targets: [
        .target(name: "FinanceCore"),
        .testTarget(name: "FinanceCoreTests", dependencies: ["FinanceCore"]),
    ]
)
