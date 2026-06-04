#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="$CONFIG.bak-plugin-repair-$STAMP"

if [[ ! -f "$CONFIG" ]]; then
  echo "Missing Codex config: $CONFIG" >&2
  exit 1
fi

cp "$CONFIG" "$BACKUP"
echo "Backed up config to: $BACKUP"

python3 - "$CODEX_HOME" "$CONFIG" <<'PY'
import json
import os
import pathlib
import platform
import re
import shutil
import sys

codex_home = pathlib.Path(sys.argv[1]).expanduser()
config_path = pathlib.Path(sys.argv[2]).expanduser()
text = config_path.read_text()

def table_exists(kind, name):
    return re.search(rf'^\[{re.escape(kind)}\.{re.escape(name)}\]\s*$', text, re.M) is not None

def plugin_table_exists(plugin_id):
    return re.search(rf'^\[plugins\."{re.escape(plugin_id)}"\]\s*$', text, re.M) is not None

def set_plugin_enabled(src, plugin_id, enabled=True):
    block_re = re.compile(
        rf'(^\[plugins\."{re.escape(plugin_id)}"\]\n)(.*?)(?=^\[|\Z)',
        re.M | re.S,
    )
    m = block_re.search(src)
    value = "true" if enabled else "false"
    if m:
        body = m.group(2)
        if re.search(r'^enabled\s*=', body, re.M):
            body = re.sub(r'^enabled\s*=.*$', f'enabled = {value}', body, flags=re.M)
        else:
            body = f'enabled = {value}\n' + body
        return src[:m.start()] + m.group(1) + body + src[m.end():]

    insert_at = None
    first_plugin = re.search(r'^\[plugins\.', src, re.M)
    if first_plugin:
        insert_at = first_plugin.start()
    else:
        insert_at = len(src)
    block = f'\n[plugins."{plugin_id}"]\nenabled = {value}\n'
    return src[:insert_at].rstrip() + "\n" + block + "\n" + src[insert_at:].lstrip()

def ensure_marketplace(src, name, source):
    block_re = re.compile(rf'(^\[marketplaces\.{re.escape(name)}\]\n)(.*?)(?=^\[|\Z)', re.M | re.S)
    m = block_re.search(src)
    body = f'last_updated = "{os.environ.get("CODEX_PLUGIN_REPAIR_TIMESTAMP", "2026-06-04T00:00:00Z")}"\nsource_type = "local"\nsource = "{source}"\n'
    if m:
        old = m.group(2)
        old = re.sub(r'^last_updated\s*=.*$', body.splitlines()[0], old, flags=re.M) if re.search(r'^last_updated\s*=', old, re.M) else body.splitlines()[0] + "\n" + old
        old = re.sub(r'^source_type\s*=.*$', 'source_type = "local"', old, flags=re.M) if re.search(r'^source_type\s*=', old, re.M) else old + 'source_type = "local"\n'
        old = re.sub(r'^source\s*=.*$', f'source = "{source}"', old, flags=re.M) if re.search(r'^source\s*=', old, re.M) else old + f'source = "{source}"\n'
        return src[:m.start()] + m.group(1) + old + src[m.end():]

    first_market = re.search(r'^\[marketplaces\.', src, re.M)
    if not first_market:
        return src.rstrip() + f'\n\n[marketplaces.{name}]\n{body}\n'

    # Keep openai-curated next to the other marketplace declarations.
    market_blocks = list(re.finditer(r'^\[marketplaces\.[^\]]+\]\n.*?(?=^\[|\Z)', src, re.M | re.S))
    insert_at = market_blocks[-1].end() if market_blocks else first_market.end()
    return src[:insert_at].rstrip() + f'\n\n[marketplaces.{name}]\n{body}' + "\n" + src[insert_at:].lstrip()

def get_marketplace_source(src, name, default):
    m = re.search(rf'^\[marketplaces\.{re.escape(name)}\]\n(.*?)(?=^\[|\Z)', src, re.M | re.S)
    if not m:
        return pathlib.Path(default)
    s = re.search(r'^source\s*=\s*"([^"]+)"', m.group(1), re.M)
    return pathlib.Path(s.group(1)).expanduser() if s else pathlib.Path(default)

# Current Codex CLI rejects service_tier = "default"; this can prevent all plugin config from loading.
text = re.sub(r'^service_tier\s*=\s*"default"\s*$', 'service_tier = "fast"', text, flags=re.M)
detected_platform = os.environ.get("CODEX_PLUGIN_REPAIR_PLATFORM", platform.system())
system_name = detected_platform.lower()

bundled_source = str(codex_home / ".tmp" / "bundled-marketplaces" / "openai-bundled")
curated_source = str(codex_home / ".tmp" / "plugins")
primary_runtime_source = str(pathlib.Path.home() / ".cache" / "codex-runtimes" / "codex-primary-runtime" / "plugins" / "openai-primary-runtime")

known_marketplaces = {
    "openai-bundled": bundled_source,
    "openai-curated": curated_source,
    "openai-primary-runtime": primary_runtime_source,
}

text = ensure_marketplace(text, "openai-bundled", bundled_source)
if pathlib.Path(curated_source, ".agents", "plugins", "marketplace.json").exists():
    text = ensure_marketplace(text, "openai-curated", curated_source)
if pathlib.Path(primary_runtime_source, ".agents", "plugins", "marketplace.json").exists():
    text = ensure_marketplace(text, "openai-primary-runtime", primary_runtime_source)

if system_name == "darwin":
    for plugin_id in (
        "browser@openai-bundled",
        "chrome@openai-bundled",
        "computer-use@openai-bundled",
    ):
        text = set_plugin_enabled(text, plugin_id, True)
else:
    print(f"Platform detected: {detected_platform}. Skipping macOS Desktop bundled plugin auto-enable.")

config_path.write_text(text)

def plugin_version(plugin_root):
    plugin_json = plugin_root / ".codex-plugin" / "plugin.json"
    if not plugin_json.exists():
        return None
    with plugin_json.open() as f:
        return json.load(f).get("version")

def cached_plugin_dirs(dst_base):
    if not dst_base.exists():
        return []
    return sorted(
        p for p in dst_base.iterdir()
        if p.is_dir() and not p.is_symlink() and (p / ".codex-plugin" / "plugin.json").exists()
    )

def update_latest_link(dst_base, target):
    latest = dst_base / "latest"
    if latest.is_symlink() or latest.exists():
        if latest.is_dir() and not latest.is_symlink():
            shutil.rmtree(latest)
        else:
            latest.unlink()
    latest.symlink_to(target)
    print(f"Updated latest link: {latest} -> {target}")

def copy_plugin(marketplace, plugin_name):
    src_market = get_marketplace_source(config_path.read_text(), marketplace, known_marketplaces.get(marketplace, ""))
    if not str(src_market):
        print(f"Skip {plugin_name}@{marketplace}: marketplace source is unknown")
        return False

    src = src_market / "plugins" / plugin_name
    dst_base = codex_home / "plugins" / "cache" / marketplace / plugin_name
    existing = cached_plugin_dirs(dst_base)
    if not src.exists():
        if existing:
            print(f"Cache already valid for {plugin_name}@{marketplace}: {existing[-1]}")
            if marketplace == "openai-bundled":
                update_latest_link(dst_base, existing[-1])
            return True
        print(f"Skip {plugin_name}@{marketplace}: marketplace plugin source missing: {src}")
        return False

    version = plugin_version(src)
    if not version:
        if existing:
            print(f"Cache already valid for {plugin_name}@{marketplace}: {existing[-1]}")
            if marketplace == "openai-bundled":
                update_latest_link(dst_base, existing[-1])
            return True
        print(f"Skip {plugin_name}@{marketplace}: missing version in {src / '.codex-plugin/plugin.json'}")
        return False

    dst = dst_base / version
    dst_base.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        print(f"Cache exists for {plugin_name}@{marketplace}: {dst}")
    else:
        shutil.copytree(src, dst, symlinks=True)
        print(f"Copied {plugin_name}@{marketplace} -> {dst}")

    if marketplace == "openai-bundled":
        update_latest_link(dst_base, dst)
    return True

def enabled_plugins(src):
    for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\n(.*?)(?=^\[|\Z)', src, re.M | re.S):
        name, market, body = m.group(1), m.group(2), m.group(3)
        if re.search(r'^enabled\s*=\s*true\s*$', body, re.M):
            yield name, market

# Repair every already-enabled plugin that can be resolved from its marketplace.
for name, market in enabled_plugins(config_path.read_text()):
    copy_plugin(market, name)

print("\nEnabled plugin consistency:")
cfg = config_path.read_text()
markets = set(re.findall(r'^\[marketplaces\.([^\]]+)\]', cfg, re.M))
missing = []
for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S):
    name, market, body = m.group(1), m.group(2), m.group(3)
    if not re.search(r'^enabled\s*=\s*true\s*$', body, re.M):
        continue
    cache = codex_home / "plugins" / "cache" / market / name
    ok_market = market in markets
    ok_cache = cache.exists()
    src_market = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
    src = src_market / "plugins" / name if str(src_market) else None
    source_exists = bool(src and src.exists())
    status = "OK" if ok_market and ok_cache else "MISSING"
    print(f"{status} {name}@{market} marketplace={ok_market} cache={ok_cache} source={source_exists}")
    if status != "OK":
        missing.append(f"{name}@{market}")

if missing:
    print("\nStill missing: " + ", ".join(missing), file=sys.stderr)
    sys.exit(2)
PY

echo
echo "Repair complete."
PLATFORM_NAME="${CODEX_PLUGIN_REPAIR_PLATFORM:-$(uname -s)}"
case "$PLATFORM_NAME" in
  Darwin)
    echo "If Codex Desktop is open, restart it once so it reloads config.toml."
    ;;
  Linux)
    echo "Start a new Codex CLI session so it reloads config.toml."
    ;;
  *)
    echo "Restart Codex or start a new Codex session so it reloads config.toml."
    ;;
esac
