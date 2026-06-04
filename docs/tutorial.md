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

The script creates a timestamped backup of `~/.codex/config.toml` before editing.

## 3. Restart Codex Desktop

Quit and reopen Codex Desktop so the app reloads plugin configuration.

On Linux, start a new Codex CLI session instead.

## 4. Verify MCP State

```bash
codex mcp list
```

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

On Windows, the script focuses on repairing Codex plugin config/cache state. If Chrome still cannot connect, rerun the Chrome plugin setup flow from Codex Desktop so Windows native messaging registration is refreshed.

## 6. What To Do If It Still Fails

Check the script output. If an enabled plugin cannot be repaired, it will print a `MISSING` line. The most important fields are:

- `marketplace=false`: `config.toml` does not contain that marketplace.
- `cache=false`: persistent cache is missing.
- `source=false`: the marketplace source does not contain the plugin, so the script cannot copy it.

In that case, reinstall or refresh the affected marketplace, then run the script again.
