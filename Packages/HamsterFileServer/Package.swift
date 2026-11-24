// swift-tools-version: 5.8
import PackageDescription
let package = Package(
  name: "HamsterFileServer",
  platforms: [.iOS(.v14)],
  products: [.library(name: "HamsterFileServer", targets: ["HamsterFileServer"])],
  targets: [
    .target(
      name: "HamsterFileServer",
      path: "Sources",
      exclude: ["Resources"]
    ),
    .testTarget(name: "HamsterFileServerTests", dependencies: ["HamsterFileServer"])
  ]
)
