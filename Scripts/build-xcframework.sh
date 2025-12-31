#!/bin/bash
set -eo pipefail

# ============================================================================
# MLXBinary XCFramework Build Script
# ============================================================================

# 配置
MLX_SWIFT_LM_VERSION="${1:-main}"
MLX_SWIFT_LM_REPO="https://github.com/ml-explore/mlx-swift-lm.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/.build-xcframework"
OUTPUT_DIR="${PROJECT_ROOT}/output"
DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData/MLXBinary-Agent"

MODULES="MLXLMCommon MLXLLM MLXVLM"

# 颜色输出
log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

cleanup() {
  log_info "清理旧的构建目录..."
  rm -rf "$BUILD_DIR"
  rm -rf "$OUTPUT_DIR"
  rm -rf "$DERIVED_DATA"
  mkdir -p "$BUILD_DIR/libs"
  mkdir -p "$BUILD_DIR/headers"
  mkdir -p "$BUILD_DIR/modules"
  mkdir -p "$OUTPUT_DIR"
}

clone_source() {
  log_info "克隆 mlx-swift-lm (版本: $MLX_SWIFT_LM_VERSION)..."
  if [[ "$MLX_SWIFT_LM_VERSION" == "main" ]]; then
    git clone --depth 1 "$MLX_SWIFT_LM_REPO" "$BUILD_DIR/mlx-swift-lm"
  else
    git clone --depth 1 --branch "$MLX_SWIFT_LM_VERSION" "$MLX_SWIFT_LM_REPO" "$BUILD_DIR/mlx-swift-lm" 2>/dev/null || \
    git clone --depth 1 "$MLX_SWIFT_LM_REPO" "$BUILD_DIR/mlx-swift-lm"
  fi
  log_success "源码克隆完成"
}

build_platform() {
  local platform="$1"
  local destination="$2"

  log_info "构建平台: $platform"

  cd "$BUILD_DIR/mlx-swift-lm"

  for module in $MODULES; do
    log_info "  构建模块: $module"

    xcodebuild build \
      -scheme "$module" \
      -destination "$destination" \
      -derivedDataPath "$DERIVED_DATA" \
      -configuration Release \
      ONLY_ACTIVE_ARCH=NO \
      2>&1 | tail -3

    log_success "  $module 构建完成"
  done

  log_success "平台 $platform 构建完成"
}

build_all_platforms() {
  log_info "开始构建所有平台..."

  build_platform "macos" "generic/platform=macOS"
  build_platform "ios" "generic/platform=iOS"
  build_platform "ios-simulator" "generic/platform=iOS Simulator"

  log_success "所有平台构建完成"
}

collect_build_artifacts() {
  log_info "收集构建产物..."

  for module in $MODULES; do
    log_info "  收集 $module 产物..."

    # 创建模块目录
    mkdir -p "$BUILD_DIR/libs/$module"
    mkdir -p "$BUILD_DIR/headers/$module"
    mkdir -p "$BUILD_DIR/modules/$module"

    # 收集每个平台的静态库
    for platform in macos ios ios-simulator; do
      case "$platform" in
        macos) product_dir="Release" ;;
        ios) product_dir="Release-iphoneos" ;;
        ios-simulator) product_dir="Release-iphonesimulator" ;;
      esac

      local obj_file="$DERIVED_DATA/Build/Products/$product_dir/${module}.o"
      if [[ -f "$obj_file" ]]; then
        local lib_file="$BUILD_DIR/libs/$module/${module}-${platform}.a"
        libtool -static -o "$lib_file" "$obj_file" 2>/dev/null
        log_success "    创建 ${module}-${platform}.a"
      fi
    done

    # 创建简单的头文件
    cat > "$BUILD_DIR/headers/$module/${module}.h" << EOF
// ${module} - MLXBinary XCFramework
// Auto-generated header file

#import <Foundation/Foundation.h>

//! Project version number for ${module}.
FOUNDATION_EXPORT double ${module}VersionNumber;

//! Project version string for ${module}.
FOUNDATION_EXPORT const unsigned char ${module}VersionString[];
EOF

    # 收集 swiftmodule 文件
    for platform in macos ios ios-simulator; do
      case "$platform" in
        macos)
          archs="arm64 x86_64"
          triple_suffix="macos"
          build_config="Release"
          ;;
        ios)
          archs="arm64"
          triple_suffix="ios"
          build_config="Release-iphoneos"
          ;;
        ios-simulator)
          archs="arm64 x86_64"
          triple_suffix="ios-simulator"
          build_config="Release-iphonesimulator"
          ;;
      esac

      for arch in $archs; do
        local module_base="$DERIVED_DATA/Build/Intermediates.noindex/mlx-swift-lm.build/${build_config}/${module}.build/Objects-normal/${arch}"
        if [[ -d "$module_base" ]]; then
          mkdir -p "$BUILD_DIR/modules/$module/${platform}"

          for ext in swiftmodule swiftdoc abi.json; do
            local src_file="$module_base/${module}.${ext}"
            if [[ -f "$src_file" ]]; then
              cp "$src_file" "$BUILD_DIR/modules/$module/${platform}/${arch}-apple-${triple_suffix}.${ext}" 2>/dev/null || true
            fi
          done
        fi
      done
    done
  done

  log_success "构建产物收集完成"
}

create_xcframeworks() {
  log_info "创建 XCFrameworks..."

  for module in $MODULES; do
    log_info "  创建 ${module}.xcframework"

    local args=""

    # macOS
    local macos_lib="$BUILD_DIR/libs/$module/${module}-macos.a"
    if [[ -f "$macos_lib" ]]; then
      args="$args -library $macos_lib -headers $BUILD_DIR/headers/$module"
    fi

    # iOS
    local ios_lib="$BUILD_DIR/libs/$module/${module}-ios.a"
    if [[ -f "$ios_lib" ]]; then
      args="$args -library $ios_lib -headers $BUILD_DIR/headers/$module"
    fi

    # iOS Simulator
    local sim_lib="$BUILD_DIR/libs/$module/${module}-ios-simulator.a"
    if [[ -f "$sim_lib" ]]; then
      args="$args -library $sim_lib -headers $BUILD_DIR/headers/$module"
    fi

    if [[ -n "$args" ]]; then
      rm -rf "$OUTPUT_DIR/${module}.xcframework"
      xcodebuild -create-xcframework \
        $args \
        -output "$OUTPUT_DIR/${module}.xcframework" 2>&1 || {
          log_error "创建 ${module}.xcframework 失败"
          continue
        }

      # 复制 swiftmodule 到 xcframework
      for platform in macos ios ios-simulator; do
        case "$platform" in
          macos) slice_dir="macos-arm64_x86_64" ;;
          ios) slice_dir="ios-arm64" ;;
          ios-simulator) slice_dir="ios-arm64_x86_64-simulator" ;;
        esac

        local xcf_modules_dir="$OUTPUT_DIR/${module}.xcframework/${slice_dir}/Modules"
        if [[ -d "$OUTPUT_DIR/${module}.xcframework/${slice_dir}" ]]; then
          mkdir -p "$xcf_modules_dir/${module}.swiftmodule"
          cp -r "$BUILD_DIR/modules/$module/${platform}/"* "$xcf_modules_dir/${module}.swiftmodule/" 2>/dev/null || true
        fi
      done

      log_success "  ${module}.xcframework 创建成功"
    fi
  done
}

package_and_checksum() {
  log_info "打包 XCFrameworks..."

  cd "$OUTPUT_DIR"

  for module in $MODULES; do
    if [[ -d "${module}.xcframework" ]]; then
      log_info "  打包 ${module}.xcframework"

      zip -r -X "${module}.xcframework.zip" "${module}.xcframework"
      rm -rf "${module}.xcframework"

      local checksum
      checksum=$(swift package compute-checksum "${module}.xcframework.zip")
      echo "$checksum" > "${module}.xcframework.zip.sha256"

      log_success "  ${module}: $checksum"
    fi
  done

  log_success "打包完成"
}

print_results() {
  echo ""
  echo "============================================================================"
  echo -e "\033[0;32m构建完成!\033[0m"
  echo "============================================================================"
  echo ""
  echo "输出目录: $OUTPUT_DIR"
  echo ""
  echo "文件列表:"
  ls -lh "$OUTPUT_DIR" 2>/dev/null || echo "  (无文件)"
  echo ""
  echo "校验和:"
  for module in $MODULES; do
    local checksum_file="$OUTPUT_DIR/${module}.xcframework.zip.sha256"
    if [[ -f "$checksum_file" ]]; then
      echo "  ${module}: $(cat "$checksum_file")"
    fi
  done
  echo ""
  echo "请将这些校验和更新到 Package.swift 中"
  echo "============================================================================"
}

main() {
  echo ""
  echo "============================================================================"
  echo "MLXBinary XCFramework Build Script"
  echo "============================================================================"
  echo "版本: $MLX_SWIFT_LM_VERSION"
  echo "输出目录: $OUTPUT_DIR"
  echo "============================================================================"
  echo ""

  cleanup
  clone_source
  build_all_platforms
  collect_build_artifacts
  create_xcframeworks
  package_and_checksum
  print_results
}

main
