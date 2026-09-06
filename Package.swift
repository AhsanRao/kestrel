// swift-tools-version:5.9
import PackageDescription

// Resources (Prompts/, DefaultMemory.md, Info.plist.template) live at the repo root per spec §7,
// which is outside the target root, so SwiftPM cannot declare them. build.sh copies them into
// Kestrel.app/Contents/Resources instead; BundleResources resolves them at runtime.
let package = Package(
    name: "Kestrel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Kestrel", path: "Sources/Kestrel"),
        .testTarget(name: "KestrelTests", dependencies: ["Kestrel"], path: "Tests/KestrelTests"),
    ]
)
