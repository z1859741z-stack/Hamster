// swift-tools-version: 5.8
import PackageDescription

let package = Package(
  name: "RimeKit",
  platforms: [.iOS(.v15)],
  products: [.library(name: "RimeKit", targets: ["RimeKit"])],
  dependencies: [.package(path: "../HamsterKit")],
  targets: [
    .binaryTarget(name: "librimeStatic", path: "../../Frameworks/librime-static.xcframework"),
    .target(name: "RimeKitObjC", dependencies: ["librimeStatic"], path: "Sources/ObjC", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("c++")]),
    .target(name: "RimeKit", dependencies: ["RimeKitObjC", "HamsterKit"], path: "Sources/Swift"),
    .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "librimeStatic"], path: "Tests")
  ])
