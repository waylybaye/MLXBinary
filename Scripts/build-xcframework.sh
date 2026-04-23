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
# 注意：不包含 swift-numerics / swift-collections / swift-transformers 的模块
# 它们是 mlx-swift-lm 的传递依赖，通过 Package.swift 的 MLXLMCommonWrapper 由下游源码提供，
# 如果这里再把它们的 .o 塞进 libMLXLMCommon.a 会造成 duplicate symbol
ALL_DEPS="Cmlx MLX MLXRandom MLXNN MLXOptimizers MLXFast MLXLinalg"

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

# ----------------------------------------------------------------------------
# 为 Library Evolution 模式打上游补丁。
#
# 背景：打开 BUILD_LIBRARY_FOR_DISTRIBUTION=YES 后，上游 mlx-swift 的
# public enum `MLXFast.ScaledDotProductAttentionMaskMode` 变成 resilient，
# 外部对它做穷举 switch 的代码必须新增 `@unknown default:` 分支，否则编译失败。
# 这两处都是 mlx-swift-lm 源码里的老代码，上游未兼容 LE，这里手工补。
# ----------------------------------------------------------------------------
patch_source_for_library_evolution() {
  log_info "为 Library Evolution 打上游补丁..."

  local src_root="$BUILD_DIR/mlx-swift-lm"

  # Patch 1: MLXLMCommon/KVCache.swift —— quantizedScaledDotProductAttention 里的 mask switch
  local kvcache="$src_root/Libraries/MLXLMCommon/KVCache.swift"
  if [[ -f "$kvcache" ]] && ! grep -q "@unknown default" "$kvcache"; then
    perl -i -0777 -pe 's/(    case \.none:\n        break\n)(    \})/$1    \@unknown default:\n        break\n$2/' "$kvcache"
    if grep -q "@unknown default" "$kvcache"; then
      log_success "  patched KVCache.swift"
    else
      log_error "  patch KVCache.swift 失败（perl 替换未命中，上游代码可能已变动）"
      exit 1
    fi
  fi

  # Patch 2: MLXVLM/Models/Gemma4.swift —— gemma4AdjustAttentionMask 里的 mask switch
  local gemma4="$src_root/Libraries/MLXVLM/Models/Gemma4.swift"
  if [[ -f "$gemma4" ]] && ! grep -q "@unknown default" "$gemma4"; then
    perl -i -0777 -pe 's/(    case \.arrays, \.causal, \.none:\n        return mask\n)(    \})/$1    \@unknown default:\n        return mask\n$2/' "$gemma4"
    if grep -q "@unknown default" "$gemma4"; then
      log_success "  patched Gemma4.swift"
    else
      log_error "  patch Gemma4.swift 失败（perl 替换未命中，上游代码可能已变动）"
      exit 1
    fi
  fi

  log_success "上游补丁应用完成"
}

build_platform() {
  local platform="$1"
  local destination="$2"

  log_info "构建平台: $platform"

  cd "$BUILD_DIR/mlx-swift-lm"

  for module in $MODULES; do
    log_info "  构建模块: $module"

    # BUILD_LIBRARY_FOR_DISTRIBUTION=YES 让编译器产出 resilient ABI 和 .swiftinterface，
    # 这是分发二进制能跨 Xcode 版本消费的前提（参考 Apple 系统库）。
    # -no-verify-emitted-module-interface 关闭 interface 回环校验：mlx-swift 的 @inlinable
    # 与泛型在严格校验下会报错，先放宽，实际消费侧仍会用 interface 重新编译。
    xcodebuild build \
      -scheme "$module" \
      -destination "$destination" \
      -derivedDataPath "$DERIVED_DATA" \
      -configuration Release \
      ONLY_ACTIVE_ARCH=NO \
      BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
      SWIFT_EMIT_MODULE_INTERFACE=YES \
      OTHER_SWIFT_FLAGS='$(inherited) -no-verify-emitted-module-interface' \
      2>&1 | tail -3

    log_success "  $module 构建完成"
  done

  log_success "平台 $platform 构建完成"
}

build_all_platforms() {
  log_info "开始构建所有平台..."

  # macOS: arm64 + x86_64 (Universal)
  build_platform "macos" "platform=macOS"
  # iOS: arm64
  build_platform "ios" "generic/platform=iOS"
  # iOS Simulator: arm64 + x86_64
  build_platform "ios-simulator" "generic/platform=iOS Simulator"

  log_success "所有平台构建完成"
}

get_deps_for_module() {
  local module="$1"
  case "$module" in
    MLXLMCommon)
      # MLXLMCommon 独家承担所有共享 .o（MLX/Cmlx/Numerics/ComplexModule/MLXNN/MLXOptimizers 等）。
      echo "$ALL_DEPS MLXLMCommon"
      ;;
    MLXLLM)
      # MLXLLM / MLXVLM 只保留自家 .o。共享符号由 libMLXLMCommon.a 提供，
      # MLXLLMWrapper / MLXVLMWrapper 都声明了对 MLXLMCommonWrapper 的依赖，
      # SwiftPM 会把三份 .a 都加进链接命令，避免下游项目同时引用多份库时出现 duplicate symbol。
      echo "MLXLLM"
      ;;
    MLXVLM)
      echo "MLXVLM"
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
        # 直接平铺到 headers/$module/ 根目录，不要多嵌一层 Cmlx/。
        # 因为消费端只把 Headers/ 加到 -I 搜索路径，#include "mlx/c/array.h"
        # 需要在 -I 路径下直接解析到 mlx/c/array.h，多嵌一层就找不到。
        cp -r "$cmlx_include/"* "$BUILD_DIR/headers/$module/"
        chmod -R u+w "$BUILD_DIR/headers/$module/"

        # 使用和上游 mlx-swift 完全一致的 modulemap 形式：单个 umbrella 头。
        # mlx.h 自身 #include 了 mlx/c/mlx.h / transforms_impl.h / linalg.h / fast.h
        # 这四个入口，间接展开全部类型。
        #
        # 注意：历史上这里曾经写成 "textual header"（见 git commit d2dec26）。
        # 那样做在非 LE 模式下能工作 —— Swift 从序列化 swiftmodule 直接拿类型，
        # 不经过 Clang importer。但开了 Library Evolution 后消费端按 .swiftinterface
        # 重新编译，需要通过 Clang importer 按名字 resolve `Cmlx.mlx_dtype` 这类类型，
        # textual 头不会被并入 Clang 模块，类型查不到就会报 "no type named 'mlx_dtype'
        # in module 'Cmlx'"。因此这里必须用普通 `header`。
        cat > "$BUILD_DIR/headers/$module/module.modulemap" << 'MODULEMAP'
module Cmlx [system] {
    header "mlx.h"
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

# ----------------------------------------------------------------------------
# 把 mlx-swift 的 Metal shader 资源 bundle（`mlx-swift_Cmlx.bundle`，内含
# `default.metallib`）从 DerivedData 拷到源码树，随 Package.swift 作为 SPM
# 资源一并分发。不拷这一份的话，消费侧运行时会抛
# `Failed to load the default metallib`（见 mlx/backend/metal/device.cpp）。
# ----------------------------------------------------------------------------
collect_metallibs() {
  log_info "收集 metallib 资源 bundle..."

  # 目标 -> 来源：目标目录下保留 mlx-swift_Cmlx.bundle 原始结构，
  # 以便消费侧（OpenCat MLXClient）按嵌套路径直接查找。
  local pairs=(
    "MLXMetalLibMacOS:Release"
    "MLXMetalLibIOS:Release-iphoneos"
  )

  for pair in "${pairs[@]}"; do
    local target_name="${pair%%:*}"
    local product_dir="${pair##*:}"

    local src_bundle="$DERIVED_DATA/Build/Products/${product_dir}/mlx-swift_Cmlx.bundle"
    local dst_root="$PROJECT_ROOT/Sources/${target_name}/Resources"
    local dst_bundle="$dst_root/mlx-swift_Cmlx.bundle"

    if [[ ! -d "$src_bundle" ]]; then
      log_warning "    找不到 ${product_dir}/mlx-swift_Cmlx.bundle，跳过 $target_name"
      continue
    fi

    mkdir -p "$dst_root"
    rm -rf "$dst_bundle"
    cp -R "$src_bundle" "$dst_root/"
    chmod -R u+w "$dst_bundle"

    # 去掉签名残留，避免 SPM 在消费侧再次签名时冲突
    rm -rf "$dst_bundle/_CodeSignature" "$dst_bundle/Contents/_CodeSignature"

    local metallib
    if [[ -f "$dst_bundle/Contents/Resources/default.metallib" ]]; then
      metallib="$dst_bundle/Contents/Resources/default.metallib"
    elif [[ -f "$dst_bundle/default.metallib" ]]; then
      metallib="$dst_bundle/default.metallib"
    else
      log_warning "    ${target_name}: 复制后找不到 default.metallib"
      continue
    fi

    local size
    size=$(du -h "$metallib" | cut -f1)
    log_success "    ${target_name}: 同步 default.metallib ($size)"
  done

  log_success "metallib 资源同步完成"
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
  echo "Checksums (运行 \`make release RELEASE=<ver>\` 写入 Package.swift):"
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
  patch_source_for_library_evolution
  build_all_platforms
  collect_build_artifacts
  collect_metallibs
  create_xcframeworks
  package_and_checksum
  print_results
}

main
