// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// 版本配置
let version = "0.3.0"
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
      checksum: "1cf79f64d3a4357dc6c3923ecbc29d29edb49a31e7d3fa405db45c6e9aba7d61"
    ),
    .binaryTarget(
      name: "MLXLLM",
      url: "\(baseURL)/\(version)/MLXLLM.xcframework.zip",
      checksum: "bc8c939ae85be90bde45d85a9daaf70a3522492eb6511df85b630e9a47183189"
    ),
    .binaryTarget(
      name: "MLXVLM",
      url: "\(baseURL)/\(version)/MLXVLM.xcframework.zip",
      checksum: "c88b9646bb1f5b60982aa76b582429d9242b62ad0ebae86766df8e4c1d6850a1"
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
