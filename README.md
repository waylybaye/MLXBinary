# MLXBinary

Pre-built XCFrameworks for [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), distributed via Swift Package Manager.

## Features

- Pre-compiled binary frameworks (no build time for mlx-swift dependencies)
- Supports macOS 14+ and iOS 16+
- Includes all dependencies (mlx-swift, swift-transformers, etc.)

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/waylybaye/MLXBinary.git", from: "0.3.0")
]
```

Then add the desired products to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MLXLLM", package: "MLXBinary"),      // For LLM only
        .product(name: "MLXVLM", package: "MLXBinary"),      // For VLM only
        .product(name: "MLXBinary", package: "MLXBinary"),   // For both LLM and VLM
    ]
)
```

## Available Products

| Product | Description |
|---------|-------------|
| `MLXLLM` | Large Language Model support |
| `MLXVLM` | Vision Language Model support |
| `MLXLMCommon` | Common utilities (included automatically) |
| `MLXBinary` | Both MLXLLM and MLXVLM |

## Requirements

- macOS 14.0+ / iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Important Notes

- Do NOT add `mlx-swift` or `mlx-swift-lm` as dependencies alongside this package (symbol conflicts will occur)
- All mlx-swift dependencies are bundled into the XCFrameworks

---

# For Maintainers

## Building XCFrameworks

```bash
# Build with latest mlx-swift-lm main branch
./Scripts/build-xcframework.sh

# Build with specific version
./Scripts/build-xcframework.sh 0.3.0
```

The script will:
1. Clone mlx-swift-lm
2. Build for all platforms (macOS, iOS, iOS Simulator)
3. Create XCFrameworks with all dependencies
4. Generate zip files and checksums
5. Automatically update `Package.swift` with new checksums

## Creating a Release

### Option A: GitHub Actions (Recommended)

```bash
# Commit changes
git add .
git commit -m "Release v0.3.0"

# Create and push tag
git tag v0.3.0
git push origin main
git push origin v0.3.0
```

GitHub Actions will automatically build and upload to Releases.

### Option B: Manual Release

```bash
# 1. Build locally
./Scripts/build-xcframework.sh

# 2. Create GitHub Release
gh release create v0.3.0 \
    output/MLXLMCommon.xcframework.zip \
    output/MLXLLM.xcframework.zip \
    output/MLXVLM.xcframework.zip \
    --title "v0.3.0" \
    --notes "Release notes here"
```

## Syncing mlx-swift-lm Updates

```bash
# 1. Build with new version
./Scripts/build-xcframework.sh 0.4.0

# 2. Commit and release
git add .
git commit -m "Update to mlx-swift-lm 0.4.0"
git tag v0.4.0
git push origin main --tags
```

## License

This project distributes pre-built binaries of [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), which is licensed under the MIT License.
