# Makefile —— MLXBinary XCFramework 构建入口
#
# 真正的构建逻辑在 Scripts/build-xcframework.sh；这里只做薄封装，
# 并把默认版本从脚本内置的 "main" 改为 mlx-swift-lm 远程仓库的最新 tag。
#
# 常用用法：
#   make build                     # 构建最新 tag 版本
#   make build VERSION=0.3.0       # 构建指定版本
#   make build VERSION=main        # 跟随主干（联调用）
#   make latest-tag                # 仅查询最新 tag
#   make release TAG=v2.0.2        # 把 output/ 当前产物发到 GitHub Release
#   make resolve | checksum | clean

MLX_SWIFT_LM_REPO := https://github.com/ml-explore/mlx-swift-lm.git

# 在 Make 解析阶段远程查询一次 tag。--refs 去掉 ^{} 解引用条目；
# --sort=-v:refname 让 git 按语义化版本倒序；失败时为空字符串，
# 由下方 build 目标显式报错，避免静默 fallback。
LATEST_TAG := $(shell git ls-remote --tags --refs --sort=-v:refname $(MLX_SWIFT_LM_REPO) 2>/dev/null | awk -F/ 'NR==1 {print $$NF}')

VERSION ?= $(LATEST_TAG)

OUTPUT_DIR := output
BUILD_DIR := .build-xcframework

.DEFAULT_GOAL := build
.PHONY: build latest-tag release resolve checksum clean

build:
	@if [ -z "$(VERSION)" ]; then \
		echo "\033[0;31m[ERROR]\033[0m 未能解析 mlx-swift-lm 最新 tag（可能是网络问题）。"; \
		echo "         请检查网络，或显式指定：make build VERSION=<tag|main>"; \
		exit 1; \
	fi
	@echo "\033[0;34m[INFO]\033[0m 使用 mlx-swift-lm 版本：$(VERSION)"
	./Scripts/build-xcframework.sh $(VERSION)

latest-tag:
	@if [ -z "$(LATEST_TAG)" ]; then \
		echo "\033[0;31m[ERROR]\033[0m 查询远程 tag 失败"; exit 1; \
	fi
	@echo "$(LATEST_TAG)"

resolve:
	swift package resolve

checksum:
	@shopt -s nullglob 2>/dev/null || true; \
	zips=$$(ls $(OUTPUT_DIR)/*.xcframework.zip 2>/dev/null); \
	if [ -z "$$zips" ]; then \
		echo "\033[1;33m[WARNING]\033[0m $(OUTPUT_DIR)/ 下暂无 .xcframework.zip，先运行 make build"; \
		exit 0; \
	fi; \
	for zip in $$zips; do \
		printf '%s  ' "$$zip"; \
		swift package compute-checksum "$$zip"; \
	done

clean:
	rm -rf $(OUTPUT_DIR) $(BUILD_DIR)

# 将 output/ 下的三个 xcframework zip 发到 GitHub Release。
# 适用于本地已跑过 make build、不想推 tag 触发 workflow 重新构建的场景；
# 和 .github/workflows/release.yml 的 v* tag 自动流程互斥，同一 tag 只能走一条路径。
release:
	@if [ -z "$(TAG)" ]; then \
		echo "\033[0;31m[ERROR]\033[0m 请指定 TAG，例如：make release TAG=v2.0.2"; \
		exit 1; \
	fi
	@for m in MLXLMCommon MLXLLM MLXVLM; do \
		zip="$(OUTPUT_DIR)/$$m.xcframework.zip"; \
		sha="$(OUTPUT_DIR)/$$m.xcframework.zip.sha256"; \
		if [ ! -f "$$zip" ] || [ ! -f "$$sha" ]; then \
			echo "\033[0;31m[ERROR]\033[0m 缺少 $$zip 或 $$sha，请先 make build"; \
			exit 1; \
		fi; \
	done
	@command -v gh >/dev/null 2>&1 || { echo "\033[0;31m[ERROR]\033[0m 未安装 gh CLI"; exit 1; }
	@common_sha=$$(cat $(OUTPUT_DIR)/MLXLMCommon.xcframework.zip.sha256); \
	llm_sha=$$(cat $(OUTPUT_DIR)/MLXLLM.xcframework.zip.sha256); \
	vlm_sha=$$(cat $(OUTPUT_DIR)/MLXVLM.xcframework.zip.sha256); \
	notes=$$(printf '## MLXBinary %s\n\nPre-built XCFrameworks for mlx-swift-lm.\n\n### Modules\n- **MLXLLM** - Large Language Model support\n- **MLXVLM** - Vision Language Model support\n- **MLXLMCommon** - Common utilities\n\n### Checksums (SHA256)\n```\nMLXLMCommon: %s\nMLXLLM: %s\nMLXVLM: %s\n```\n' "$(TAG)" "$$common_sha" "$$llm_sha" "$$vlm_sha"); \
	echo "\033[0;34m[INFO]\033[0m 正在创建 release $(TAG) ..."; \
	gh release create "$(TAG)" \
		$(OUTPUT_DIR)/MLXLMCommon.xcframework.zip \
		$(OUTPUT_DIR)/MLXLLM.xcframework.zip \
		$(OUTPUT_DIR)/MLXVLM.xcframework.zip \
		--title "MLXBinary $(TAG)" \
		--notes "$$notes"
