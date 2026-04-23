// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// 版本配置
let version = "3.31.4"
let baseURL = "https://github.com/waylybaye/MLXBinary/releases/download"

// 默认使用远端 Release 里的 xcframework.zip + checksum。
// 本地联调时设置环境变量 MLX_BINARY_LOCAL=1，改走 output/ 下的本地 zip。
// 例如：MLX_BINARY_LOCAL=1 swift package resolve
let useLocalBinaries = ProcessInfo.processInfo.environment["MLX_BINARY_LOCAL"] != nil

// 统一的 binaryTarget 工厂：根据 useLocalBinaries 决定走 path 还是 url+checksum。
// checksum 只有远端模式生效，本地模式忽略；新发版时由 `make release` 刷新。
func mlxBinaryTarget(name: String, checksum: String) -> Target {
  if useLocalBinaries {
    return .binaryTarget(
      name: name,
      path: "output/\(name).xcframework.zip"
    )
  }
  return .binaryTarget(
    name: name,
    url: "\(baseURL)/v\(version)/\(name).xcframework.zip",
    checksum: checksum
  )
}

let package = Package(
  name: "MLXBinary",
  platforms: [
    .macOS(.v14),
    .iOS(.v17)
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
    // 默认远端；设 MLX_BINARY_LOCAL=1 走 output/ 下的本地 zip（联调用）。
    // checksum 由 `make release` 自动刷新，不要手工编辑。
    mlxBinaryTarget(name: "MLXLMCommon", checksum: "2842643188f97cde20be2ae0ceecd6a2162450bb654d761aae4b3f8d8029371c"),
    mlxBinaryTarget(name: "MLXLLM",      checksum: "ed057a4bd47d14197ee3ed3ad6f920790110c2c0405a0e9038bb83a620c70fec"),
    mlxBinaryTarget(name: "MLXVLM",      checksum: "f4a2f371dfd2f1e16caf77ef1db26139190a2bd2b77a911243190e88fd7ec67a"),

    // ===== Metal Library Resource Targets =====
    // mlx-swift 在源码构建时由 SwiftPM 把 Cmlx 的 Metal shaders 打成 `mlx-swift_Cmlx.bundle`。
    // 二进制分发时 .xcframework 只带 .a，不带这个资源 bundle。
    // 这里用两个按平台条件生效的 resource-only target 把 metallib 带回去。
    // 消费侧 SPM 会把它们产出到 `MLXBinary_MLXMetalLib<Platform>.bundle` 里，
    // OpenCat 的 `MLXClient.swift` 会扫描嵌套的 `mlx-swift_Cmlx.bundle/default.metallib` 并加载。
    .target(
      name: "MLXMetalLibMacOS",
      path: "Sources/MLXMetalLibMacOS",
      resources: [.copy("Resources/mlx-swift_Cmlx.bundle")]
    ),
    .target(
      name: "MLXMetalLibIOS",
      path: "Sources/MLXMetalLibIOS",
      resources: [.copy("Resources/mlx-swift_Cmlx.bundle")]
    ),

    // ===== Wrapper Targets =====
    // Wrapper targets 用于解决 binaryTarget 无法声明依赖的问题
    .target(
      name: "MLXLMCommonWrapper",
      dependencies: [
        "MLXLMCommon",
        .product(name: "Numerics", package: "swift-numerics"),
        .product(name: "Collections", package: "swift-collections"),
        .target(name: "MLXMetalLibMacOS", condition: .when(platforms: [.macOS])),
        .target(name: "MLXMetalLibIOS", condition: .when(platforms: [.iOS])),
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
