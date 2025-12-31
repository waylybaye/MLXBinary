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
  targets: [
    // ===== Binary Targets =====
    // 这些是预编译的 XCFramework，从 GitHub Releases 下载
    .binaryTarget(
      name: "MLXLMCommon",
      url: "\(baseURL)/\(version)/MLXLMCommon.xcframework.zip",
      checksum: "7424eff08ecd7ef0ac781bc1c06b24667d90b4268a3ab87c94450a068b51afc8"
    ),
    .binaryTarget(
      name: "MLXLLM",
      url: "\(baseURL)/\(version)/MLXLLM.xcframework.zip",
      checksum: "d4550a8baed0d1056c0addd8d15356d387c00faff54d5b9c93b91363339eb39f"
    ),
    .binaryTarget(
      name: "MLXVLM",
      url: "\(baseURL)/\(version)/MLXVLM.xcframework.zip",
      checksum: "bce20ced0c78c23e38767ecf9fc025103215a04fa1d332f8a34daaf1082d03e7"
    ),

    // ===== Wrapper Targets =====
    // Wrapper targets 用于解决 binaryTarget 无法声明依赖的问题
    .target(
      name: "MLXLMCommonWrapper",
      dependencies: ["MLXLMCommon"],
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
