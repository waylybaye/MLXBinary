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
#   make resolve | checksum | clean
#
# 发版流程：
#   make build VERSION=<mlx-tag>   # 1) 构建产物到 output/
#   make release RELEASE=2.0.2     # 2) 改 Package.swift + commit + 打 tag（不 push）
#   make push                      # 3) push 到 origin + gh release create 上传 zip

MLX_SWIFT_LM_REPO := https://github.com/ml-explore/mlx-swift-lm.git

# 在 Make 解析阶段远程查询一次 tag。--refs 去掉 ^{} 解引用条目；
# --sort=-v:refname 让 git 按语义化版本倒序；失败时为空字符串，
# 由下方 build 目标显式报错，避免静默 fallback。
LATEST_TAG := $(shell git ls-remote --tags --refs --sort=-v:refname $(MLX_SWIFT_LM_REPO) 2>/dev/null | awk -F/ 'NR==1 {print $$NF}')

VERSION ?= $(LATEST_TAG)

OUTPUT_DIR := output
BUILD_DIR := .build-xcframework

MODULES := MLXLMCommon MLXLLM MLXVLM

.DEFAULT_GOAL := build
.PHONY: build latest-tag resolve checksum clean release push

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

# ---------------------------------------------------------------------------
# release —— 固化一版 Package.swift + 打本地 tag，不跑 build、不 push、不联网。
# 用法：make release RELEASE=2.0.2
#
# 前置条件：
#   1) output/ 下存在三个 .xcframework.zip（由 make build 产出）。
#   2) 工作区干净（Package.swift 不应有未提交改动，避免搭车进 release commit）。
# ---------------------------------------------------------------------------
release:
	@if [ -z "$(RELEASE)" ]; then \
		echo "\033[0;31m[ERROR]\033[0m 未指定 RELEASE。用法：make release RELEASE=2.0.2"; \
		exit 1; \
	fi
	@if ! echo "$(RELEASE)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "\033[0;31m[ERROR]\033[0m RELEASE 必须是语义化版本（x.y.z），得到：$(RELEASE)"; \
		exit 1; \
	fi
	@for m in $(MODULES); do \
		if [ ! -f "$(OUTPUT_DIR)/$$m.xcframework.zip" ]; then \
			echo "\033[0;31m[ERROR]\033[0m 缺少 $(OUTPUT_DIR)/$$m.xcframework.zip，先跑 make build"; \
			exit 1; \
		fi; \
	done
	@if ! git diff --quiet -- Package.swift; then \
		echo "\033[0;31m[ERROR]\033[0m Package.swift 有未提交改动，请先清理工作区"; \
		exit 1; \
	fi
	@if git rev-parse -q --verify "refs/tags/v$(RELEASE)" >/dev/null; then \
		echo "\033[0;31m[ERROR]\033[0m tag v$(RELEASE) 已存在"; \
		exit 1; \
	fi
	@echo "\033[0;34m[INFO]\033[0m 写入 Package.swift: version=$(RELEASE)"
	@sed -i '' -E 's/^let version = "[^"]*"/let version = "$(RELEASE)"/' Package.swift
	@for m in $(MODULES); do \
		new_sum=$$(swift package compute-checksum "$(OUTPUT_DIR)/$$m.xcframework.zip"); \
		echo "\033[0;34m[INFO]\033[0m 更新 checksum: $$m -> $$new_sum"; \
		sed -i '' -E "s|(mlxBinaryTarget\\(name: \"$$m\",[[:space:]]*checksum: \")[^\"]+(\")|\\1$$new_sum\\2|" Package.swift; \
	done
	@if git diff --quiet -- Package.swift; then \
		echo "\033[1;33m[WARNING]\033[0m Package.swift 无变化（version 和 checksum 都没变），退出"; \
		exit 1; \
	fi
	@git add Package.swift
	@git commit -m "chore: release v$(RELEASE)"
	@git tag "v$(RELEASE)"
	@echo ""
	@echo "\033[0;32m[SUCCESS]\033[0m 已创建 commit + tag v$(RELEASE)（未 push）"
	@echo "           下一步：make push"

# ---------------------------------------------------------------------------
# push —— 把 make release 产出的 commit + tag 推到 origin，并用 gh 上传 zip。
# 用法：make push
# ---------------------------------------------------------------------------
push:
	@RELEASE=$$(grep -E '^let version = ' Package.swift | sed -E 's/.*"([^"]+)".*/\1/'); \
	if [ -z "$$RELEASE" ]; then \
		echo "\033[0;31m[ERROR]\033[0m 无法从 Package.swift 解析 let version"; \
		exit 1; \
	fi; \
	if ! git rev-parse -q --verify "refs/tags/v$$RELEASE" >/dev/null; then \
		echo "\033[0;31m[ERROR]\033[0m 本地不存在 tag v$$RELEASE，先跑 make release RELEASE=$$RELEASE"; \
		exit 1; \
	fi; \
	for m in $(MODULES); do \
		if [ ! -f "$(OUTPUT_DIR)/$$m.xcframework.zip" ]; then \
			echo "\033[0;31m[ERROR]\033[0m 缺少 $(OUTPUT_DIR)/$$m.xcframework.zip，无法上传"; \
			exit 1; \
		fi; \
	done; \
	echo "\033[0;34m[INFO]\033[0m 推送 commit + tag v$$RELEASE"; \
	git push origin HEAD --follow-tags; \
	echo "\033[0;34m[INFO]\033[0m 创建 GitHub Release v$$RELEASE 并上传 zip"; \
	gh release create "v$$RELEASE" \
		$(OUTPUT_DIR)/MLXLMCommon.xcframework.zip \
		$(OUTPUT_DIR)/MLXLLM.xcframework.zip \
		$(OUTPUT_DIR)/MLXVLM.xcframework.zip \
		--title "v$$RELEASE" \
		--generate-notes; \
	echo "\033[0;32m[SUCCESS]\033[0m Release v$$RELEASE 发布完成"
