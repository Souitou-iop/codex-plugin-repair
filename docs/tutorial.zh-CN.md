# 教程：修复 Codex Desktop 插件状态

## 1. 适用症状

当 macOS 或 Windows 上的 Codex Desktop 出现以下情况时，可以使用这个脚本：

- Computer Use 重启后消失
- Chrome 插件反复要求重新安装
- `codex mcp list` 看不到 `computer-use`
- Chrome native host manifest 存在，但指向不稳定的插件路径
- bundled 插件只在 `.tmp` 里存在，但持久 cache 里缺失

Linux 下只能把这个脚本用于 Codex CLI 插件 marketplace/cache 一致性检查。Linux 没有同款 Codex Desktop + Computer Use 故障模式。

## 2. 执行修复

macOS 或 Linux：

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

Windows PowerShell：

```powershell
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1
```

脚本会先给 `~/.codex/config.toml` 创建带时间戳的备份，再进行修改。

## 3. 重启 Codex Desktop

执行完成后，退出并重新打开 Codex Desktop，让桌面端重新加载插件配置。

Linux 下执行完成后，启动新的 Codex CLI 会话即可。

## 4. 验证 MCP 状态

```bash
codex mcp list
```

预期结果：

- 如果 Computer Use 已启用，应能看到 `computer-use`
- `node_repl` 仍然正常启用
- 不再出现配置解析错误

## 5. 在 macOS 下验证 Chrome Native Host

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

预期结果：

```text
Correct: yes
```

Windows 下脚本主要修复 Codex 插件 config/cache 状态。如果 Chrome 仍然连不上，重新在 Codex Desktop 里走一遍 Chrome 插件安装流程，让 Windows native messaging 注册刷新。

## 6. 如果仍然失败

看脚本输出。如果某个已启用插件无法修复，脚本会输出 `MISSING` 行。重点看这些字段：

- `marketplace=false`：`config.toml` 里没有对应 marketplace。
- `cache=false`：持久 cache 缺失。
- `source=false`：marketplace 源里找不到这个插件，所以脚本无法复制。

遇到这种情况，先重新安装或刷新对应 marketplace，然后再运行一次脚本。
