# Codex Plugin Repair

A small recovery script for Codex Desktop plugin state issues on macOS.

It is intended for cases where Codex updates or restarts cause bundled plugins such as **Computer Use** or **Chrome** to disappear, reinstall repeatedly, or stop attaching their MCP/native-host integration.

> This is an unofficial community workaround. It is not maintained by OpenAI.

## What It Fixes

The script repairs the local Codex plugin state by:

- backing up `~/.codex/config.toml`
- ensuring `browser@openai-bundled`, `chrome@openai-bundled`, and `computer-use@openai-bundled` are enabled
- ensuring the bundled and curated marketplaces exist in `config.toml`
- copying enabled plugins from their marketplace source into persistent `~/.codex/plugins/cache/...`
- refreshing `latest` symlinks for bundled plugins
- checking every `enabled=true` plugin for both marketplace and cache presence

It does **not** enable random plugins, delete browser profiles, edit Chrome/Edge user data, or install browser extensions into your profile.

## Quick Start

```bash
git clone https://github.com/Souitou-iop/codex-plugin-repair.git
cd codex-plugin-repair
./scripts/fix-codex-plugins.sh
```

Restart Codex Desktop after running the script.

## One-Line Usage

Review the script before using this form:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Souitou-iop/codex-plugin-repair/main/scripts/fix-codex-plugins.sh)
```

## Verify

After running:

```bash
codex mcp list
```

You should see `computer-use` listed when the Computer Use plugin is enabled.

For Chrome native host state:

```bash
/Applications/Codex.app/Contents/Resources/node \
  ~/.codex/plugins/cache/openai-bundled/chrome/latest/scripts/check-native-host-manifest.js
```

The expected result is `Correct: yes`.

## Related Reports

These upstream issues describe similar plugin persistence and bundled marketplace symptoms:

- https://github.com/openai/codex/issues/25813
- https://github.com/openai/codex/issues/25809
- https://github.com/openai/codex/issues/21936
- https://github.com/openai/codex/issues/21579

## Chinese Documentation

中文说明见 [README.zh-CN.md](./README.zh-CN.md).
