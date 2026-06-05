# Codex 插件修复脚本

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

修复 Codex Desktop 更新、重启后出现的本地插件状态异常，重点覆盖 **Computer Use**、**Chrome**、**Browser** 这些 bundled 插件。

> 非官方社区修复脚本，不是 OpenAI 官方工具。脚本会先备份 `~/.codex/config.toml`，再修改配置和插件缓存。

## 快速修复

急用时直接执行下面的一行命令。脚本会先备份 `~/.codex/config.toml`，再修复本地插件配置和 cache。

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.3.3/scripts/Fix-CodexPlugins.ps1 | iex
```

执行后完全退出并重新打开 Codex Desktop。

### macOS / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.3.3/scripts/fix-codex-plugins.sh)
```

macOS 执行后重启 Codex Desktop。Linux 执行后启动新的 Codex CLI 会话。

## 想先检查脚本内容

如果你想先阅读脚本，或者公司环境不允许 `curl | bash` / `irm | iex`，用 clone 后运行的方式。

### Windows

```powershell
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1
```

非标准 AppX 安装可以手动指定 bundled 源目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1 -BundledSourceRoot "C:\Path\To\openai-bundled"
```

### macOS

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

### Linux

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

Linux 没有 Codex Desktop + Computer Use 的同款故障模式。脚本只做 CLI-only 修复：修复已经启用插件的 marketplace/cache 一致性，不会强行启用 Desktop 专属插件。

## 什么时候该用

适合这些情况：

- Codex Desktop 里 Computer Use 不可用或消失
- Chrome 插件反复提示重新安装
- `codex mcp list` 看不到 `computer-use`
- Chrome native host 指向临时目录或旧插件路径
- Windows 日志里出现 `helper paths are unavailable` 或 `not_in_bundled_marketplace_plugin_names`
- `~/.codex/plugins/cache/...` 缺少已启用插件
- `~/.codex/config.toml` 缺少 bundled / curated marketplace

不适合这些情况：

- 账号、模型、灰度权限导致工具不可见
- 浏览器扩展本身没有安装或被浏览器禁用
- 公司安全策略阻止 native helper 或 named pipe
- Codex Desktop 安装包本身损坏，且没有可用 bundled 源目录

## 脚本会改什么

| 平台 | 行为 |
| --- | --- |
| Windows | 启用 `browser` / `chrome` / `computer-use`，从 AppX 源重建 bundled marketplace，重建残缺 cache，刷新 `latest` junction，修正 Computer Use `notify` helper 路径。 |
| macOS | 启用 `browser` / `chrome` / `computer-use`，修复 bundled / curated marketplace 和持久 cache，刷新 bundled 插件 `latest` 软链接。 |
| Linux | 不强行启用 Desktop 插件，只修复当前配置里已经 `enabled=true` 的插件 marketplace/cache。 |

脚本不会：

- 删除 Chrome / Edge 用户数据
- 修改浏览器 Profile
- 强行安装浏览器扩展
- 启用随机插件
- 删除当前有效的 `config.toml`

## 怎么验证

通用检查：

```bash
codex mcp list
```

如果 Computer Use 已启用，应能看到 `computer-use`。

macOS Chrome native host：

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

期望看到：

```text
Correct: yes
```

Windows Computer Use named pipe：

```powershell
Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -like "codex-computer-use-*" }
```

Windows Codex Desktop 日志关键词：

```powershell
$logRoot = "$env:LOCALAPPDATA\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs"
Get-ChildItem -Path $logRoot -Recurse -Filter "codex-desktop-*.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 |
  Select-String -Pattern "computer-use native pipe startup ready|helper paths are unavailable|not_in_bundled_marketplace_plugin_names"
```

## 失败时看哪里

脚本末尾会输出每个已启用插件的一致性检查：

```text
OK chrome@openai-bundled marketplace=True cache=True source=True
MISSING example@marketplace marketplace=True cache=False source=False
```

重点看这三项：

- `marketplace=false`：`config.toml` 缺少对应 marketplace。
- `cache=false`：持久 cache 缺失。
- `source=false`：marketplace 源目录里找不到该插件，脚本无法复制。

如果 Windows 上 Chrome 仍无法连接，先在 Codex Desktop 里重新走一次 Chrome 插件安装流程，让 Windows native messaging 注册刷新。

## 回滚

脚本每次运行都会备份配置文件，路径类似：

```text
~/.codex/config.toml.bak-plugin-repair-YYYYMMDDHHMMSS
```

Windows 下重建 bundled marketplace 或残缺 cache 时，也会给旧目录添加 `.bak-plugin-repair-...` 备份后缀。需要回退时，关闭 Codex Desktop，再把对应备份恢复到原路径。

## 相关问题

- https://github.com/openai/codex/issues/25813
- https://github.com/openai/codex/issues/25809
- https://github.com/openai/codex/issues/21936
- https://github.com/openai/codex/issues/21579
