// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeanutGallery",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PeanutGallery", targets: ["PeanutGallery"])],
    targets: [.executableTarget(name: "PeanutGallery", path: "Sources/PeanutGallery")]
)
