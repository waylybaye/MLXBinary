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
      checksum: "991cf53d9f0ee82d0f2f723b2b9c5c89f99f7b015fe123db1d46f5dc2b50d2ea"
    ),
    .binaryTarget(
      name: "MLXLLM",
      url: "\(baseURL)/\(version)/MLXLLM.xcframework.zip",
      checksum: "da97397c25ba64a81f130fe3a45b240d5dd9b116bd41cd98a1319751e885417c"
    ),
    .binaryTarget(
      name: "MLXVLM",
      url: "\(baseURL)/\(version)/MLXVLM.xcframework.zip",
      checksum: "243accb6199db19fc713d1f47af8da553acb3ee00060bc8575bb0c512ca898c6"
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
