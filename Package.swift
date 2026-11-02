// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuLite",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MenuLite",
            path: "Sources/MenuLite"
        )
    ],
    // Pragmatic: use the Swift 6 compiler but the Swift 5 language mode, so the
    // C-interop bits (CGEventTap callbacks, mach stats) stay clean and readable.
    swiftLanguageModes: [.v5]
)
