// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Xvico",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Xvico", targets: ["XvicoApp"])],
    targets: [
        .target(name: "XvicoBluetooth"),
        .executableTarget(
            name: "XvicoApp",
            dependencies: ["XvicoBluetooth"],
            resources: [
                .copy("Resources/SiriRemote.usdz"),
                .copy("Resources/DeveloperWeChatQR.jpg"),
                .process("Resources/Localization"),
                .copy("Resources/VoiceRuntime")
            ]
        ),
        .testTarget(name: "XvicoAppTests", dependencies: ["XvicoApp", "XvicoBluetooth"])
    ]
)
