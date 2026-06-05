# Codex 插件修复脚本

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

修复 Codex Desktop 更新、重启后出现的本地插件状态异常，重点覆盖 **Computer Use**、**Chrome**、**Browser** 这些 bundled 插件。

> 非官方社区修复脚本，不是 OpenAI 官方工具。脚本会先备份 `~/.codex/config.toml`，再修改配置和插件缓存。

## 快速修复

按下面 4 步操作即可：

1. 先完全退出 Codex Desktop。
2. 复制并运行对应平台的一行命令。
3. 看到语言选择时输入 `1` 使用中文，或输入 `2` 使用英文。
4. 看完脚本说明后，输入 `y` 或 `yes` 开始修复；输入 `n` 或 `no` 会退出且不修改任何文件。

脚本会先检查是否有常见 Codex/插件进程正在运行；如果检测到 Codex Desktop，会询问你是否先关闭它。脚本会备份 `~/.codex/config.toml`，再修复本地插件配置和 cache。脚本不会删除浏览器数据，不会修改浏览器 Profile，也不会在未经确认时结束进程。

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.3.13/scripts/Fix-CodexPlugins.ps1 | iex
```

完成后重新打开 Codex Desktop。

### macOS / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.3.13/scripts/fix-codex-plugins.sh)
```

macOS 执行后重启 Codex Desktop。Linux 执行后启动新的 Codex CLI 会话。

## 想先检查脚本内容

如果你想先阅读脚本，或者公司环境不允许 `curl | bash` / `irm | iex`，用 clone 后运行的方式。

Bash 版本需要本机有 `python3`。如果没有，脚本会停止并输出诊断日志，不会继续修改配置。

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

所有平台都会先提示可能占用插件文件的常见进程，例如 Codex、`extension-host`、`codex-computer-use`。如果检测到 Codex Desktop，脚本会询问是否先关闭它；只有你输入 `y` 或 `yes` 才会尝试关闭。其他插件进程只做预警，不会自动结束。

脚本不会：

- 删除 Chrome / Edge 用户数据
- 修改浏览器 Profile
- 强行安装浏览器扩展
- 启用随机插件
- 未经确认就关闭应用或结束进程
- 删除当前有效的 `config.toml`

## 怎么验证

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

脚本末尾会输出中英文插件覆盖报告。你可以用它判断哪些 marketplace 已配置、哪些插件 cache 存在、哪些已启用插件还需要处理：

```text
插件覆盖报告 / Plugin coverage report:
Marketplaces / 插件市场:
KNOWN openai-bundled table=true source=true cache=true
UNKNOWN openai-unknown table=false source=false cache=true
Enabled plugins / 已启用插件:
OK chrome@openai-bundled marketplace=true source=true cache=true
MISSING example@marketplace marketplace=true source=false cache=false
```

重点看这三项：

- `marketplace=false`：`config.toml` 缺少对应 marketplace。
- `cache=false`：持久 cache 缺失。
- `source=false`：marketplace 源目录里找不到该插件，脚本无法复制。

如果脚本以错误状态退出，还会在 `~/.codex/` 下写入诊断日志，例如：

```text
~/.codex/codex-plugin-repair-diagnostics-YYYYMMDDHHMMSS-PID.log
```

你可以把这份日志粘贴到 Agents / Codex 软件中，让它继续帮你排查下一步。

如果 Windows 上 Chrome 仍无法连接，先在 Codex Desktop 里重新走一次 Chrome 插件安装流程，让 Windows native messaging 注册刷新。

## 回滚

脚本每次运行都会备份配置文件，路径类似：

```text
~/.codex/config.toml.bak-plugin-repair-YYYYMMDDHHMMSS-PID
```

Windows 下重建 bundled marketplace 或残缺 cache 时，也会给旧目录添加 `.bak-plugin-repair-...` 备份后缀。需要回退时，关闭 Codex Desktop，再把对应备份恢复到原路径。

## 相关问题

- https://github.com/openai/codex/issues/25813
- https://github.com/openai/codex/issues/25809
- https://github.com/openai/codex/issues/21936
- https://github.com/openai/codex/issues/21579
