---
name: market-skill-installation
description: Install zip skills into ~/.hermes/skills; verify assets.
---

# Market Skill Installation（从 zip 安装技能）

触发：用户给出 `SKILL_NAME` + 远程 zip `DOWNLOAD_URL`（OSS/市场链接）要求"下载并安装技能"。用户会重复发起此类任务（qoderwork-ppt、ui-designer 均为实例）。

## 标准流程

1. **找目录**：检查 `~/.hermes/skills`（本机实际为 `~/.hermes/skills`；按脚本先探测 USER/PROJECT 目录，两者都有时问用户全局/项目）
2. **检查**：`[ -f "$INSTALL_DIR/SKILL.md" ]` → EXISTS 时询问是否覆盖；NEW 直接继续
3. **下载**：`curl -fSL -o "$TMP/skill.zip" "$URL"`（本机 curl 不受代理影响；失败再试 wget）
4. **解压**：`unzip -o ... -d "$TMP/ext"`，找 `SKILL_PATH=$(find "$TMP/ext" -maxdepth 2 -name SKILL.md | head -1)`，`cp -R "$(dirname "$SKILL_PATH")"/. "$INSTALL_DIR"/`
5. **验证**：`head -5 SKILL.md` 非空
6. **⚠️ 资产完整性检查（关键，易漏）**：grep SKILL.md 引用的 `assets/`、`scripts/`、`rules/`、`templates/` 文件，逐一 `[ -f ]` 确认存在。实例：ui-designer 官方 zip 只有 SKILL.md（2,967 字节），3 个模板资产缺失——发布包本身不完整，不是下载问题
7. **读 SKILL.md 并完成用户任务**

## 缺资产处理

- 先确认是发布包问题而非下载问题：`unzip -l` 列出 zip 内容（对比正常包，如 qoderwork-ppt 含 31 文件）
- **模板类资产可从 SKILL.md 描述重建**：SKILL.md 通常含每个模板的 section 构成（如 "Includes sections for: color palette / typography / ..."），据此写回 `assets/<name>.md` 即恢复完整功能
- 探测其他路径：`{dir}/{name}.zip`、`{dir}/latest.zip`（实例均 403）；OSS ListObjects（`?list-type=2&prefix=...`）通常也 403（Bucket 未开放）
- 无法补齐时如实报告，让用户联系发布方

## 依赖安装（npm 技能）

```bash
npm install --registry=https://registry.npmmirror.com   # 国内镜像
PUPPETEER_SKIP_DOWNLOAD=true npm install                # 免 Chromium 下载
export PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

## 注意

- 本技能与 bundled `hermes-skill-installation`（GitHub 场景）重叠：本技能针对远程 zip/OSS 市场 + 资产验证，彼针对 GitHub 仓库。由 curator 决定是否合并。
- 安装后若技能引用的脚本需 npm 依赖，先装依赖再声称"可用"（end-to-end 验证原则）。
