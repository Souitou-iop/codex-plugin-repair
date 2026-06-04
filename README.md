# Codex Plugin Repair

[![English](https://img.shields.io/badge/Language-English-blue)](./README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-green)](./README.zh-CN.md)

Repair local Codex plugin state after Codex Desktop updates or restarts, especially for bundled plugins such as **Computer Use**, **Chrome**, and **Browser**.

> This is an unofficial community workaround, not an OpenAI-maintained tool. The script backs up `~/.codex/config.toml` before editing config or plugin cache state.

## Which Command Should I Run?

The recommended path is to clone the repository first so you can inspect the script.

### Windows

```powershell
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1
```

Fully quit and reopen Codex Desktop after the script finishes.

If your install is not the standard AppX package, pass the bundled source manually:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Fix-CodexPlugins.ps1 -BundledSourceRoot "C:\Path\To\openai-bundled"
```

### macOS

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

Restart Codex Desktop after the script finishes.

### Linux

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

Linux does not have the same Codex Desktop + Computer Use failure mode. The script runs in CLI-only mode: it repairs marketplace/cache consistency for plugins that are already enabled, and it does not force-enable Desktop-only plugins.

## One-Line Usage

Use this form when you need a quick repair. Inspecting the script first is still the safer default.

macOS / Linux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.3.3/scripts/fix-codex-plugins.sh)
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/v0.3.3/scripts/Fix-CodexPlugins.ps1 | iex
```

## When To Use It

Use this script when you see symptoms like:

- Computer Use is unavailable or disappears in Codex Desktop
- Chrome asks to reinstall repeatedly
- `computer-use` is missing from `codex mcp list`
- Chrome native host points at a temporary or stale plugin path
- Windows logs contain `helper paths are unavailable` or `not_in_bundled_marketplace_plugin_names`
- `~/.codex/plugins/cache/...` is missing enabled plugins
- `~/.codex/config.toml` is missing bundled or curated marketplace entries

This script is not meant for:

- account, model, rollout, or entitlement issues
- browser extensions that are not installed or are disabled by the browser
- security policy blocking native helpers or named pipes
- a corrupted Codex Desktop install with no usable bundled source directory

## What It Changes

| Platform | Behavior |
| --- | --- |
| Windows | Enables `browser`, `chrome`, and `computer-use`; rebuilds the bundled marketplace from the AppX source; rebuilds incomplete cache directories; refreshes `latest` junctions; updates the Computer Use `notify` helper path. |
| macOS | Enables `browser`, `chrome`, and `computer-use`; repairs bundled/curated marketplace entries and persistent cache; refreshes bundled plugin `latest` symlinks. |
| Linux | Does not force-enable Desktop plugins. It only repairs marketplace/cache state for plugins already marked `enabled=true`. |

The script does not:

- delete Chrome or Edge user data
- edit browser profiles
- force-install browser extensions
- enable random plugins
- delete the active `config.toml`

## Verify The Repair

Common check:

```bash
codex mcp list
```

You should see `computer-use` when Computer Use is enabled.

macOS Chrome native host check:

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

Expected output:

```text
Correct: yes
```

Windows Computer Use named pipe:

```powershell
Get-ChildItem -Path "\\.\pipe\" | Where-Object { $_.Name -like "codex-computer-use-*" }
```

Windows Codex Desktop log keywords:

```powershell
$logRoot = "$env:LOCALAPPDATA\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs"
Get-ChildItem -Path $logRoot -Recurse -Filter "codex-desktop-*.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 |
  Select-String -Pattern "computer-use native pipe startup ready|helper paths are unavailable|not_in_bundled_marketplace_plugin_names"
```

## If It Still Fails

The script prints a consistency check for every enabled plugin:

```text
OK chrome@openai-bundled marketplace=True cache=True source=True
MISSING example@marketplace marketplace=True cache=False source=False
```

Focus on these fields:

- `marketplace=false`: `config.toml` is missing that marketplace.
- `cache=false`: persistent cache is missing.
- `source=false`: the marketplace source directory does not contain that plugin, so the script cannot copy it.

If Chrome still cannot connect on Windows, rerun the Chrome plugin setup flow from Codex Desktop so Windows native messaging registration is refreshed.

## Roll Back

Each run backs up the config file with a name like:

```text
~/.codex/config.toml.bak-plugin-repair-YYYYMMDDHHMMSS
```

On Windows, rebuilt bundled marketplace or incomplete cache directories are also moved aside with a `.bak-plugin-repair-...` suffix. To roll back, quit Codex Desktop and restore the relevant backup path.

## Related Reports

- https://github.com/openai/codex/issues/25813
- https://github.com/openai/codex/issues/25809
- https://github.com/openai/codex/issues/21936
- https://github.com/openai/codex/issues/21579
