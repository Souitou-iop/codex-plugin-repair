# Tutorial: Repair Codex Desktop Plugin State

## 1. Symptoms

Use this script when Codex Desktop on macOS or Windows shows one or more of these symptoms:

- Computer Use disappears after restart
- Chrome plugin asks to reinstall repeatedly
- `computer-use` does not appear in `codex mcp list`
- Chrome native host manifest exists but points at unstable plugin paths
- bundled plugins are present under `.tmp` but missing from persistent cache

On Linux, use the same script only for Codex CLI plugin marketplace/cache consistency checks. Linux does not have the same Codex Desktop + Computer Use failure mode.

## 2. Run the Repair

macOS or Linux:

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

Windows PowerShell:

```powershell
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1
```

If Codex Desktop is not installed as the normal AppX package, provide the bundled source manually:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1 -BundledSourceRoot "C:\Path\To\openai-bundled"
```

The script asks for a language, explains the planned actions, and waits for `yes` before editing anything. It creates a timestamped backup of `~/.codex/config.toml` before editing, then prints guided progress steps, completion messages, and problem messages.

## 3. Restart Codex Desktop

Quit and reopen Codex Desktop so the app reloads plugin configuration.

On Linux, start a new Codex CLI session instead.

## 4. Optional: Verify MCP State

```bash
codex mcp list
```

Skip this check if the `codex` command is not installed or not available in `PATH`.

Expected:

- `computer-use` is listed when enabled
- `node_repl` remains enabled
- no config parsing error appears

## 5. Verify Chrome Native Host On macOS

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

Expected:

```text
Correct: yes
```

On Windows, the script also repairs the bundled marketplace from the Codex Desktop AppX source when available, rebuilds incomplete bundled cache directories, and updates the Computer Use `notify` helper path. After restarting Codex Desktop, useful checks are:

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

If Chrome still cannot connect, rerun the Chrome plugin setup flow from Codex Desktop so Windows native messaging registration is refreshed.

## 6. What To Do If It Still Fails

Check the bilingual plugin coverage report at the end of the script output. If an enabled plugin cannot be repaired, it will print a `MISSING` line. The most important fields are:

```text
插件覆盖报告 / Plugin coverage report:
Enabled plugins / 已启用插件:
MISSING example@marketplace marketplace=true source=false cache=false
```

- `marketplace=false`: `config.toml` does not contain that marketplace.
- `cache=false`: persistent cache is missing.
- `source=false`: the marketplace source does not contain the plugin, so the script cannot copy it.

On failure, the script writes a diagnostic log named like `codex-plugin-repair-diagnostics-YYYYMMDDHHMMSS.log` under your Codex home directory. Paste that log into Agents / Codex if you want help with the next troubleshooting step.

In that case, reinstall or refresh the affected marketplace, then run the script again.
