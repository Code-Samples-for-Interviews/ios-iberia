// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlbumSearchKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Data", targets: ["Data"]),
        .library(name: "Presentation", targets: ["Presentation"])
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Data", dependencies: ["Domain"]),
        .target(name: "Presentation", dependencies: ["Domain"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "DataTests", dependencies: ["Data", "Domain"]),
        .testTarget(name: "PresentationTests", dependencies: ["Presentation", "Domain"])
    ]
)
