// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// 版本配置
let version = "2.29.2"
let baseURL = "https://github.com/waylybaye/MLXBinary/releases/download"

let package = Package(
  name: "MLXBinary",
  platforms: [
    .macOS(.v14),
    .iOS(.v16)
  ],
  products: [
    // 单独产品 - 用户可按需引入
    .library(name: "MLXLLM", targets: ["MLXLLMWrapper"]),
    .library(name: "MLXVLM", targets: ["MLXVLMWrapper"]),
    .library(name: "MLXLMCommon", targets: ["MLXLMCommonWrapper"]),

    // 组合产品 - 一次引入 LLM 和 VLM
    .library(name: "MLXBinary", targets: ["MLXLLMWrapper", "MLXVLMWrapper"]),
  ],
  dependencies: [
    // 这些依赖是 mlx-swift-lm 的传递依赖
    // 需要在这里声明以便 MLXLMCommon.swiftmodule 能够找到它们
    .package(url: "https://github.com/apple/swift-numerics", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
  ],
  targets: [
    // ===== Binary Targets =====
    // 本地测试：使用本地 xcframework
    // .binaryTarget(
    //   name: "MLXLMCommon",
    //   path: "output/MLXLMCommon.xcframework.zip"
    // ),
    // .binaryTarget(
    //   name: "MLXLLM",
    //   path: "output/MLXLLM.xcframework.zip"
    // ),
    // .binaryTarget(
    //   name: "MLXVLM",
    //   path: "output/MLXVLM.xcframework.zip"
    // ),
    // 发布时使用远程 URL：
    .binaryTarget(
      name: "MLXLMCommon",
      url: "\(baseURL)/\(version)/MLXLMCommon.xcframework.zip",
      checksum: "2c7d14d809f9ec318b82508d83f73d020f9c60dcffa6f40c115079512024695a"
    ),
    .binaryTarget(
      name: "MLXLLM",
      url: "\(baseURL)/\(version)/MLXLLM.xcframework.zip",
      checksum: "7758100983e72051b88c4cdeab6832a86883aff57ce06187aea36adde605ea0d"
    ),
    .binaryTarget(
      name: "MLXVLM",
      url: "\(baseURL)/\(version)/MLXVLM.xcframework.zip",
      checksum: "f419d1afe9e45cb635eb876438e3dc679444b460baa1e1b4507bdca8143206bf"
    ),

    // ===== Wrapper Targets =====
    // Wrapper targets 用于解决 binaryTarget 无法声明依赖的问题
    .target(
      name: "MLXLMCommonWrapper",
      dependencies: [
        "MLXLMCommon",
        .product(name: "Numerics", package: "swift-numerics"),
        .product(name: "Collections", package: "swift-collections"),
      ],
      path: "Sources/MLXLMCommonWrapper"
    ),
    .target(
      name: "MLXLLMWrapper",
      dependencies: ["MLXLLM", "MLXLMCommonWrapper"],
      path: "Sources/MLXLLMWrapper"
    ),
    .target(
      name: "MLXVLMWrapper",
      dependencies: ["MLXVLM", "MLXLMCommonWrapper"],
      path: "Sources/MLXVLMWrapper"
    ),
  ]
)
