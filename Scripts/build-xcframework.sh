#!/bin/bash
set -eo pipefail

# ============================================================================
# MLXBinary XCFramework Build Script (完整打包版)
# ============================================================================
# 构建 mlx-swift-lm 的 XCFramework，包含所有依赖
# ============================================================================

MLX_SWIFT_LM_VERSION="${1:-main}"
MLX_SWIFT_LM_REPO="https://github.com/ml-explore/mlx-swift-lm.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/.build-xcframework"
OUTPUT_DIR="${PROJECT_ROOT}/output"
DERIVED_DATA="${BUILD_DIR}/DerivedData"

MODULES="MLXLMCommon MLXLLM MLXVLM"

# 所有依赖模块（按依赖顺序）
ALL_DEPS="_NumericsShims RealModule ComplexModule Numerics InternalCollectionsUtilities OrderedCollections Jinja Hub Tokenizers Generation Models Cmlx MLX MLXRandom MLXNN MLXOptimizers MLXFast MLXLinalg"

# Swift 依赖模块（需要复制 swiftmodule）
# 注意：不包含公共依赖（swift-collections, swift-numerics），因为 OpenCat 可能已经依赖它们
# 只包含 mlx-swift 和 swift-transformers 特有的模块
SWIFT_DEPS="Jinja Hub Tokenizers Generation Models MLX MLXRandom MLXNN MLXOptimizers MLXFast MLXLinalg"

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

  # 测试阶段：只构建 arm64 macOS
  build_platform "macos" "platform=macOS,arch=arm64"
  # build_platform "ios" "generic/platform=iOS"
  # build_platform "ios-simulator" "generic/platform=iOS Simulator"

  log_success "所有平台构建完成"
}

get_deps_for_module() {
  local module="$1"
  case "$module" in
    MLXLMCommon)
      echo "$ALL_DEPS MLXLMCommon"
      ;;
    MLXLLM)
      echo "$ALL_DEPS MLXLMCommon MLXLLM"
      ;;
    MLXVLM)
      echo "$ALL_DEPS MLXLMCommon MLXVLM"
      ;;
  esac
}

get_swift_deps_for_module() {
  local module="$1"
  case "$module" in
    MLXLMCommon)
      # MLXLMCommon 包含所有公共依赖的 swiftmodule
      echo "$SWIFT_DEPS MLXLMCommon"
      ;;
    MLXLLM)
      # MLXLLM 只包含自己的 swiftmodule，避免与 MLXLMCommon 冲突
      echo "MLXLLM"
      ;;
    MLXVLM)
      # MLXVLM 只包含自己的 swiftmodule，避免与 MLXLMCommon 冲突
      echo "MLXVLM"
      ;;
  esac
}

collect_build_artifacts() {
  log_info "收集构建产物..."

  for module in $MODULES; do
    log_info "  收集 $module 产物..."

    mkdir -p "$BUILD_DIR/libs/$module"
    mkdir -p "$BUILD_DIR/headers/$module"
    mkdir -p "$BUILD_DIR/modules/$module"

    local deps=$(get_deps_for_module "$module")

    # 收集每个平台的静态库
    for platform in macos ios ios-simulator; do
      case "$platform" in
        macos) product_dir="Release" ;;
        ios) product_dir="Release-iphoneos" ;;
        ios-simulator) product_dir="Release-iphonesimulator" ;;
      esac

      local obj_files=""
      local obj_count=0

      for dep in $deps; do
        local obj_file="$DERIVED_DATA/Build/Products/$product_dir/${dep}.o"
        if [[ -f "$obj_file" ]]; then
          obj_files="$obj_files $obj_file"
          obj_count=$((obj_count + 1))
        fi
      done

      if [[ $obj_count -gt 0 ]]; then
        local lib_file="$BUILD_DIR/libs/$module/lib${module}-${platform}.a"
        libtool -static -o "$lib_file" $obj_files 2>/dev/null
        local size=$(du -h "$lib_file" | cut -f1)
        log_success "    创建 lib${module}-${platform}.a ($obj_count 模块, $size)"
      fi
    done

    # 收集 C 模块头文件（仅 MLXLMCommon 包含公共头文件）
    # MLXLLM 和 MLXVLM 不包含头文件，避免与 MLXLMCommon 冲突
    # 直接放在 Headers 根目录（它们有唯一目录名不会冲突）
    if [[ "$module" == "MLXLMCommon" ]]; then
      # Cmlx 头文件
      local cmlx_include="$DERIVED_DATA/SourcePackages/checkouts/mlx-swift/Source/Cmlx/include"
      if [[ -d "$cmlx_include" ]]; then
        mkdir -p "$BUILD_DIR/headers/$module/Cmlx"
        cp -r "$cmlx_include/"* "$BUILD_DIR/headers/$module/Cmlx/"
        chmod -R u+w "$BUILD_DIR/headers/$module/Cmlx/"

        # 创建自定义 modulemap
        cat > "$BUILD_DIR/headers/$module/Cmlx/module.modulemap" << 'MODULEMAP'
module Cmlx [system] {
    textual header "mlx.h"
    textual header "mlx/c/mlx.h"
    textual header "mlx/c/array.h"
    textual header "mlx/c/closure.h"
    textual header "mlx/c/compile.h"
    textual header "mlx/c/device.h"
    textual header "mlx/c/distributed.h"
    textual header "mlx/c/distributed_group.h"
    textual header "mlx/c/error.h"
    textual header "mlx/c/export.h"
    textual header "mlx/c/fast.h"
    textual header "mlx/c/fft.h"
    textual header "mlx/c/half.h"
    textual header "mlx/c/io.h"
    textual header "mlx/c/io_types.h"
    textual header "mlx/c/linalg.h"
    textual header "mlx/c/map.h"
    textual header "mlx/c/memory.h"
    textual header "mlx/c/metal.h"
    textual header "mlx/c/ops.h"
    textual header "mlx/c/optional.h"
    textual header "mlx/c/random.h"
    textual header "mlx/c/stream.h"
    textual header "mlx/c/string.h"
    textual header "mlx/c/transforms.h"
    textual header "mlx/c/transforms_impl.h"
    textual header "mlx/c/vector.h"
    textual header "mlx/c/version.h"
    export *
}
MODULEMAP
        log_success "    复制 Cmlx 头文件"
      fi

      # 注意：不复制 _NumericsShims 头文件
      # 因为 Package.swift 已经声明了对 swift-numerics 的依赖
      # 由 swift-numerics 包自己提供这些头文件，避免重复定义
    fi

    # 收集 swiftmodule 文件（主模块）
    for platform in macos ios ios-simulator; do
      case "$platform" in
        macos)
          archs="arm64"  # arm64 only for testing
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

          for ext in swiftmodule swiftdoc swiftinterface abi.json; do
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

    for platform in macos ios ios-simulator; do
      local lib_file="$BUILD_DIR/libs/$module/lib${module}-${platform}.a"
      if [[ -f "$lib_file" ]]; then
        # 只有 MLXLMCommon 有 C 头文件，其他模块不传 -headers 避免冲突
        if [[ "$module" == "MLXLMCommon" ]]; then
          args="$args -library $lib_file -headers $BUILD_DIR/headers/$module"
        else
          args="$args -library $lib_file"
        fi
      fi
    done

    if [[ -n "$args" ]]; then
      rm -rf "$OUTPUT_DIR/${module}.xcframework"
      xcodebuild -create-xcframework \
        $args \
        -output "$OUTPUT_DIR/${module}.xcframework" 2>&1 || {
          log_error "创建 ${module}.xcframework 失败"
          continue
        }

      # 复制所有依赖的 swiftmodule 到 xcframework
      # 关键：swiftmodule 必须放在 slice 根目录（与 .a 同级），不能放在 Headers 子目录
      # 因为 Xcode 的 ProcessXCFramework 会把 Headers 内容复制到 include/
      # 但 Swift 编译器的 -I 搜索路径不包含 include/，只包含根目录
      local swift_deps=$(get_swift_deps_for_module "$module")

      for platform in macos ios ios-simulator; do
        case "$platform" in
          macos) slice_dir="macos-arm64_x86_64" ;;  # xcodebuild 生成的实际目录名
          ios) slice_dir="ios-arm64" ;;
          ios-simulator) slice_dir="ios-arm64_x86_64-simulator" ;;
        esac

        local xcf_slice="$OUTPUT_DIR/${module}.xcframework/${slice_dir}"
        if [[ -d "$xcf_slice" ]]; then
          # swiftmodule 放在 slice 根目录（与 .a 库同级）
          # 这样 ProcessXCFramework 会把它们复制到 .../Debug/ 而不是 .../Debug/include/

          # 复制主模块的 swiftmodule
          mkdir -p "$xcf_slice/${module}.swiftmodule"
          if [[ -d "$BUILD_DIR/modules/$module/${platform}" ]]; then
            cp -r "$BUILD_DIR/modules/$module/${platform}/"* "$xcf_slice/${module}.swiftmodule/" 2>/dev/null || true
          fi

          # 复制所有依赖的 swiftmodule
          local dep_count=0
          for dep in $swift_deps; do
            local swiftmodule_dir="$DERIVED_DATA/Build/Products"
            case "$platform" in
              macos) swiftmodule_dir="$swiftmodule_dir/Release" ;;
              ios) swiftmodule_dir="$swiftmodule_dir/Release-iphoneos" ;;
              ios-simulator) swiftmodule_dir="$swiftmodule_dir/Release-iphonesimulator" ;;
            esac
            swiftmodule_dir="$swiftmodule_dir/${dep}.swiftmodule"

            if [[ -d "$swiftmodule_dir" ]]; then
              cp -r "$swiftmodule_dir" "$xcf_slice/" 2>/dev/null || true
              dep_count=$((dep_count + 1))
            fi
          done
          log_success "    ${platform}: 复制 $dep_count 个依赖 swiftmodule 到 slice 根目录"
        fi
      done

      # MLXLLM 和 MLXVLM 没有 C 头文件，不需要 HeadersPath
      # 只有 MLXLMCommon 有 Headers 目录（包含 Cmlx 和 _NumericsShims）

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

      local size=$(du -h "${module}.xcframework.zip" | cut -f1)
      log_success "  ${module}: $size - $checksum"
    fi
  done

  log_success "打包完成"
}

update_package_swift() {
  log_info "更新 Package.swift checksums..."

  local package_file="$PROJECT_ROOT/Package.swift"

  if [[ ! -f "$package_file" ]]; then
    log_error "Package.swift 不存在"
    return 1
  fi

  for module in $MODULES; do
    local checksum_file="$OUTPUT_DIR/${module}.xcframework.zip.sha256"
    if [[ -f "$checksum_file" ]]; then
      local new_checksum
      new_checksum=$(cat "$checksum_file")

      # 使用 sed 替换对应模块的 checksum
      # 匹配模式: name: "MODULE" 后面几行内的 checksum: "..."
      if [[ "$(uname)" == "Darwin" ]]; then
        # macOS sed
        sed -i '' -E "/(name: \"${module}\"|\"${module}.xcframework.zip\")/,/checksum:/ s/(checksum: \")[^\"]*(\")/\1${new_checksum}\2/" "$package_file"
      else
        # GNU sed
        sed -i -E "/(name: \"${module}\"|\"${module}.xcframework.zip\")/,/checksum:/ s/(checksum: \")[^\"]*(\")/\1${new_checksum}\2/" "$package_file"
      fi

      log_success "  ${module}: ${new_checksum}"
    fi
  done

  log_success "Package.swift 更新完成"
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
  ls -lh "$OUTPUT_DIR" 2>/dev/null | grep -v "\.sha256" || echo "  (无文件)"
  echo ""
  echo "Checksums (已自动更新到 Package.swift):"
  for module in $MODULES; do
    local checksum_file="$OUTPUT_DIR/${module}.xcframework.zip.sha256"
    if [[ -f "$checksum_file" ]]; then
      echo "  ${module}: $(cat "$checksum_file")"
    fi
  done
  echo ""
  echo "============================================================================"
}

main() {
  echo ""
  echo "============================================================================"
  echo "MLXBinary XCFramework Build Script (完整打包版)"
  echo "============================================================================"
  echo "版本: $MLX_SWIFT_LM_VERSION"
  echo "输出目录: $OUTPUT_DIR"
  echo "包含所有依赖: mlx-swift, swift-transformers 等"
  echo "============================================================================"
  echo ""

  cleanup
  clone_source
  build_all_platforms
  collect_build_artifacts
  create_xcframeworks
  package_and_checksum
  update_package_swift
  print_results
}

main
