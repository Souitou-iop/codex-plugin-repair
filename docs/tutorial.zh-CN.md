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

如果 Codex Desktop 不是标准 AppX 安装，可以手动指定 bundled 源目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1 -BundledSourceRoot "C:\Path\To\openai-bundled"
```

脚本会先让你选择语言，说明计划执行的操作，并等待你输入 `y` 或 `yes` 后才会开始修改。修改前会给 `~/.codex/config.toml` 创建带时间戳的备份；运行时会显示步骤进度，执行完成或遇到问题时，终端会输出提示。

## 3. 重启 Codex Desktop

执行完成后，退出并重新打开 Codex Desktop，让桌面端重新加载插件配置。

Linux 下执行完成后，启动新的 Codex CLI 会话即可。

## 4. 在 macOS 下验证 Chrome Native Host

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

预期结果：

```text
Correct: yes
```

Windows 下脚本还会在可用时从 Codex Desktop AppX 源重建 bundled marketplace，重建残缺的 bundled cache，并修正 Computer Use 的 `notify` 辅助程序路径。重启 Codex Desktop 后，可以用这些命令辅助验证：

```powershell
Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -like "codex-computer-use-*" }
```

```powershell
$logRoot = "$env:LOCALAPPDATA\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs"
Get-ChildItem -Path $logRoot -Recurse -Filter "codex-desktop-*.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 |
  Select-String -Pattern "computer-use native pipe startup ready|helper paths are unavailable|not_in_bundled_marketplace_plugin_names"
```

如果 Chrome 仍然连不上，重新在 Codex Desktop 里走一遍 Chrome 插件安装流程，让 Windows native messaging 注册刷新。

## 5. 如果仍然失败

看脚本末尾的中英文插件覆盖报告。如果某个已启用插件无法修复，脚本会输出 `MISSING` 行。重点看这些字段：

```text
插件覆盖报告 / Plugin coverage report:
Enabled plugins / 已启用插件:
MISSING example@marketplace marketplace=true source=false cache=false
```

- `marketplace=false`：`config.toml` 里没有对应 marketplace。
- `cache=false`：持久 cache 缺失。
- `source=false`：marketplace 源里找不到这个插件，所以脚本无法复制。

失败时，脚本会在 Codex home 目录下写入类似 `codex-plugin-repair-diagnostics-YYYYMMDDHHMMSS-PID.log` 的诊断日志。你可以把这份日志粘贴到 Agents / Codex 软件中，让它继续帮你排查下一步。

遇到这种情况，先重新安装或刷新对应 marketplace，然后再运行一次脚本。
