# Codex 插件修复脚本

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

这是一个用于修复 Codex 插件状态异常的小脚本。

主要适用于 macOS Codex Desktop 更新或重启后，**Computer Use**、**Chrome** 等 bundled 插件消失、反复要求重新安装、MCP 没挂上、Chrome native host 配置不稳定。Linux 下脚本会以 CLI-only 模式运行，只修复已经启用插件的 marketplace/cache 一致性，不会强行启用 Desktop 专属插件。

> 这是非官方社区临时修复方案，不是 OpenAI 官方工具。

## 它会修复什么

脚本会修复本机 Codex 插件状态：

- 先备份 `~/.codex/config.toml`
- 确保 `browser@openai-bundled`、`chrome@openai-bundled`、`computer-use@openai-bundled` 都是 `enabled=true`
- 确保 `config.toml` 里有 bundled / curated marketplace
- 把已启用插件从 marketplace source 复制到持久 cache：`~/.codex/plugins/cache/...`
- 刷新 bundled 插件的 `latest` 软链接
- 检查所有 `enabled=true` 插件是否同时具备 marketplace 和 cache

它不会启用随机插件，不会删除浏览器 Profile，不会修改 Chrome/Edge 用户数据，也不会把扩展强行装进浏览器 Profile。

## 平台说明

- **macOS：** 完整修复模式。脚本会启用并修复 bundled 的 `browser`、`chrome`、`computer-use` 插件。
- **Linux：** CLI-only 修复模式。Codex CLI 支持 Linux，但 Codex Desktop 和 Computer Use 不是 Linux Desktop 功能。脚本不会强行启用 `chrome` 或 `computer-use`，只会在 marketplace source 存在时修复 `config.toml` 里已经启用的插件。
- **Windows：** 暂时不是这个脚本的目标平台。

## 快速使用

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

执行完成后，重启 Codex Desktop。

Linux 下执行完成后，重开 shell 或启动新的 Codex CLI 会话。

## 一行命令

使用前建议先阅读脚本内容：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.2.0/scripts/fix-codex-plugins.sh)
```

## 验证

执行后运行：

```bash
codex mcp list
```

如果 Computer Use 已启用，应该能看到 `computer-use`。

macOS 下检查 Chrome native host：

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

期望结果是 `Correct: yes`。

## 相关上游问题

这些 issue 描述了类似的插件持久化和 bundled marketplace 问题：

- https://github.com/openai/codex/issues/25813
- https://github.com/openai/codex/issues/25809
- https://github.com/openai/codex/issues/21936
- https://github.com/openai/codex/issues/21579

## 英文说明

English documentation: [README.md](./README.md).
