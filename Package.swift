// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SelectTranslate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SelectTranslate", targets: ["SelectTranslate"]),
        .executable(name: "models-list", targets: ["ModelsList"])
    ],
    targets: [
        .executableTarget(
            name: "SelectTranslate",
            path: "Sources/SelectTranslate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ModelsList",
            path: "Sources/ModelsList",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)