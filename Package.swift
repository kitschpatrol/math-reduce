// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MathReduce",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "MathReduce", targets: ["MathReduce"])],
  dependencies: [
    // Includes the upstream fixes since 3.1.0, including factorial overflow.
    .package(
      url: "https://github.com/davedelong/DDMathParser.git",
      revision: "2e067fc17c36f4298649b6681d52286fe4ca388e"
    )
  ],
  targets: [
    .target(
      name: "MathReduceCore",
      dependencies: [.product(name: "MathParser", package: "DDMathParser")]
    ),
    .executableTarget(name: "MathReduce", dependencies: ["MathReduceCore"]),
    .testTarget(name: "MathReduceTests", dependencies: ["MathReduceCore"]),
  ]
)
