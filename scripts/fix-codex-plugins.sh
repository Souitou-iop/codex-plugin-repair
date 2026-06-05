#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="$CONFIG.bak-plugin-repair-$STAMP"
LOG="$CODEX_HOME/codex-plugin-repair-diagnostics-$STAMP.log"

select_language() {
  local requested="${CODEX_PLUGIN_REPAIR_LANGUAGE:-}"
  case "$requested" in
    zh|zh-CN|cn|1) echo "zh-CN"; return ;;
    en|en-US|2) echo "en-US"; return ;;
  esac

  echo "请选择语言 / Choose language:" >&2
  echo "1. 简体中文" >&2
  echo "2. English" >&2
  printf "请输入 1 或 2，然后按 Enter / Enter 1 or 2, then press Enter: " >&2
  read -r choice
  if [[ "$choice" == "2" ]]; then
    echo "en-US"
  else
    echo "zh-CN"
  fi
}

LANGUAGE="$(select_language)"

confirm_execution() {
  if [[ "$LANGUAGE" == "en-US" ]]; then
    echo "Codex Plugin Repair"
    echo "This script will:"
    echo "1. Check your Codex config file."
    echo "2. Back up config.toml before changing anything."
    echo "3. Repair known marketplace entries and service_tier when needed."
    echo "4. Repair cache for plugins that are already enabled."
    echo "5. On macOS, enable Browser, Chrome, and Computer Use bundled plugins."
    echo "It will not delete browser data, browser profiles, or the active config.toml."
    echo "It will not close apps or terminate processes automatically. If files are locked, close Codex Desktop and run it again."
    echo
    if [[ "${CODEX_PLUGIN_REPAIR_YES:-}" == "1" ]]; then
      return
    fi
    printf "Type yes to continue, or no to exit: "
  else
    echo "Codex 插件修复脚本"
    echo "这个脚本将执行以下操作："
    echo "1. 检查 Codex 配置文件。"
    echo "2. 修改前先备份 config.toml。"
    echo "3. 按需修复已知 marketplace 配置和 service_tier。"
    echo "4. 修复当前已经启用插件的缓存。"
    echo "5. 在 macOS 上启用 Browser、Chrome、Computer Use bundled 插件。"
    echo "脚本不会删除浏览器数据、浏览器 Profile，也不会删除当前有效的 config.toml。"
    echo "脚本不会自动关闭应用或结束进程；如果文件被占用，请关闭 Codex Desktop 后重新运行。"
    echo
    if [[ "${CODEX_PLUGIN_REPAIR_YES:-}" == "1" ]]; then
      return
    fi
    printf "输入 yes 继续执行，输入 no 退出: "
  fi
  read -r answer
  if [[ "$answer" != "yes" ]]; then
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "Cancelled. No changes were made."
    else
      echo "已取消，未做任何修改。"
    fi
    exit 0
  fi
}

confirm_execution
echo
if [[ "$LANGUAGE" == "en-US" ]]; then
  echo "[1/5] Checking Codex config..."
else
  echo "[1/5] 检查 Codex 配置..."
fi

print_agents_help() {
  local log_path="$1"
  echo "诊断日志 / Diagnostic log: $log_path" >&2
  echo "你可以把这份日志粘贴到 Agents / Codex 软件中继续排查。" >&2
  echo "You can paste this log into Agents / Codex to continue troubleshooting." >&2
}

if [[ ! -f "$CONFIG" ]]; then
  echo "错误：找不到 Codex 配置文件。" >&2
  echo "Error: missing Codex config: $CONFIG" >&2
  if mkdir -p "$CODEX_HOME" 2>/dev/null; then
    {
      echo "Codex Plugin Repair diagnostic log"
      echo "Codex 插件修复诊断日志"
      echo "timestamp=$STAMP"
      echo "codex_home=$CODEX_HOME"
      echo "config=$CONFIG"
      echo "error=missing Codex config"
    } > "$LOG"
    print_agents_help "$LOG"
  fi
  exit 1
fi

echo "[2/5] 备份配置文件 / Backing up config..."
cp "$CONFIG" "$BACKUP"
echo "已备份配置文件。/ Backed up config to: $BACKUP"

python3 - "$CODEX_HOME" "$CONFIG" "$LOG" "$BACKUP" "$STAMP" <<'PY'
import json
import os
import pathlib
import platform
import re
import shutil
import sys
from datetime import datetime, timezone

codex_home = pathlib.Path(sys.argv[1]).expanduser()
config_path = pathlib.Path(sys.argv[2]).expanduser()
log_path = pathlib.Path(sys.argv[3]).expanduser()
backup_path = pathlib.Path(sys.argv[4]).expanduser()
stamp = sys.argv[5]
text = config_path.read_text()
repair_timestamp = os.environ.get(
    "CODEX_PLUGIN_REPAIR_TIMESTAMP",
    datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
)

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
    body = f'last_updated = "{repair_timestamp}"\nsource_type = "local"\nsource = "{source}"\n'
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
verbose_report = os.environ.get("CODEX_PLUGIN_REPAIR_VERBOSE_REPORT") == "1"

print(f"\n[3/5] 检测平台和修复 marketplace / Detecting platform and repairing marketplaces: {detected_platform}")

def yn(value):
    return "true" if value else "false"

def marketplace_tables(src):
    return dict(re.findall(r'^\[marketplaces\.([^\]]+)\]\n(.*?)(?=^\[|\Z)', src, re.M | re.S))

def plugin_tables(src):
    for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\n(.*?)(?=^\[|\Z)', src, re.M | re.S):
        name, market, body = m.group(1), m.group(2), m.group(3)
        enabled = bool(re.search(r'^enabled\s*=\s*true\s*$', body, re.M))
        yield name, market, enabled

def source_plugin_names(source_root):
    plugins_root = pathlib.Path(source_root) / "plugins"
    if not plugins_root.exists():
        return set()
    return {
        p.name for p in plugins_root.iterdir()
        if p.is_dir() and (p / ".codex-plugin" / "plugin.json").exists()
    }

def cache_marketplaces():
    cache_root = codex_home / "plugins" / "cache"
    if not cache_root.exists():
        return set()
    return {p.name for p in cache_root.iterdir() if p.is_dir()}

def has_plugin_cache(dst_base):
    if not dst_base.exists():
        return False
    return any(
        p.is_dir() and not p.is_symlink() and (p / ".codex-plugin" / "plugin.json").exists()
        for p in dst_base.iterdir()
    )

def plugin_coverage_report_lines(cfg):
    lines = ["插件覆盖报告 / Plugin coverage report:"]
    markets = marketplace_tables(cfg)
    cache_markets = cache_marketplaces()
    all_markets = sorted(set(markets) | cache_markets | set(known_marketplaces))

    lines.append("Marketplaces / 插件市场:")
    for market in all_markets:
        source = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
        has_table = market in markets
        has_source = bool(str(source)) and source.exists()
        has_cache = market in cache_markets
        label = "KNOWN" if market in known_marketplaces or has_table else "UNKNOWN"
        lines.append(f"{label} {market} table={yn(has_table)} source={yn(has_source)} cache={yn(has_cache)}")

    lines.append("Enabled plugins / 已启用插件:")
    for name, market, enabled in plugin_tables(cfg):
        if not enabled:
            continue
        cache = codex_home / "plugins" / "cache" / market / name
        source_market = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
        source = source_market / "plugins" / name if str(source_market) else None
        ok_market = market in markets
        ok_cache = has_plugin_cache(cache)
        source_exists = bool(source and source.exists())
        status = "OK" if ok_cache else "MISSING"
        lines.append(f"{status} {name}@{market} marketplace={yn(ok_market)} source={yn(source_exists)} cache={yn(ok_cache)}")

    if verbose_report:
        enabled_ids = {f"{name}@{market}" for name, market, enabled in plugin_tables(cfg) if enabled}
        lines.append("Available but not enabled / 可用但未启用:")
        found = 0
        for market in all_markets:
            source = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
            if not str(source) or not source.exists():
                continue
            for name in sorted(source_plugin_names(source)):
                plugin_id = f"{name}@{market}"
                if plugin_id not in enabled_ids:
                    lines.append(plugin_id)
                    found += 1
        if found == 0:
            lines.append("none / 无")
    return lines

def print_plugin_coverage_report(cfg):
    print()
    for line in plugin_coverage_report_lines(cfg):
        print(line)

def write_diagnostic_log(cfg, missing):
    lines = [
        "Codex Plugin Repair diagnostic log",
        "Codex 插件修复诊断日志",
        f"timestamp={stamp}",
        f"platform={detected_platform}",
        f"codex_home={codex_home}",
        f"config={config_path}",
        f"backup={backup_path}",
        "missing=" + ", ".join(missing),
        "",
    ]
    lines.extend(plugin_coverage_report_lines(cfg))
    log_path.write_text("\n".join(lines) + "\n")

def print_agents_help():
    print(f"诊断日志 / Diagnostic log: {log_path}", file=sys.stderr)
    print("你可以把这份日志粘贴到 Agents / Codex 软件中继续排查。", file=sys.stderr)
    print("You can paste this log into Agents / Codex to continue troubleshooting.", file=sys.stderr)

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
    print(f"检测到平台：{detected_platform}。跳过 macOS Desktop bundled 插件自动启用。/ Platform detected: {detected_platform}. Skipping macOS Desktop bundled plugin auto-enable.")

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
    print(f"已更新 latest 链接 / Updated latest link: {latest} -> {target}")

def copy_plugin(marketplace, plugin_name):
    src_market = get_marketplace_source(config_path.read_text(), marketplace, known_marketplaces.get(marketplace, ""))
    if not str(src_market):
        print(f"跳过 {plugin_name}@{marketplace}：marketplace 源未知 / Skip {plugin_name}@{marketplace}: marketplace source is unknown")
        return False

    src = src_market / "plugins" / plugin_name
    dst_base = codex_home / "plugins" / "cache" / marketplace / plugin_name
    existing = cached_plugin_dirs(dst_base)
    if not src.exists():
        if existing:
            print(f"缓存已有效 / Cache already valid for {plugin_name}@{marketplace}: {existing[-1]}")
            if marketplace == "openai-bundled":
                update_latest_link(dst_base, existing[-1])
            return True
        print(f"跳过 {plugin_name}@{marketplace}：marketplace 插件源缺失 / Skip {plugin_name}@{marketplace}: marketplace plugin source missing: {src}")
        return False

    version = plugin_version(src)
    if not version:
        if existing:
            print(f"缓存已有效 / Cache already valid for {plugin_name}@{marketplace}: {existing[-1]}")
            if marketplace == "openai-bundled":
                update_latest_link(dst_base, existing[-1])
            return True
        print(f"跳过 {plugin_name}@{marketplace}：plugin.json 缺少版本号 / Skip {plugin_name}@{marketplace}: missing version in {src / '.codex-plugin/plugin.json'}")
        return False

    dst = dst_base / version
    dst_base.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        print(f"缓存已存在 / Cache exists for {plugin_name}@{marketplace}: {dst}")
    else:
        shutil.copytree(src, dst, symlinks=True)
        print(f"已复制插件 / Copied {plugin_name}@{marketplace} -> {dst}")

    if marketplace == "openai-bundled":
        update_latest_link(dst_base, dst)
    return True

def enabled_plugins(src):
    for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\n(.*?)(?=^\[|\Z)', src, re.M | re.S):
        name, market, body = m.group(1), m.group(2), m.group(3)
        if re.search(r'^enabled\s*=\s*true\s*$', body, re.M):
            yield name, market

# Repair every already-enabled plugin that can be resolved from its marketplace.
print("\n[4/5] 修复已启用插件缓存 / Repairing enabled plugin cache...")
for name, market in enabled_plugins(config_path.read_text()):
    copy_plugin(market, name)

cfg = config_path.read_text()
print("\n[5/5] 生成插件覆盖报告 / Generating plugin coverage report...")
print_plugin_coverage_report(cfg)
markets = set(re.findall(r'^\[marketplaces\.([^\]]+)\]', cfg, re.M))
missing = []
for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S):
    name, market, body = m.group(1), m.group(2), m.group(3)
    if not re.search(r'^enabled\s*=\s*true\s*$', body, re.M):
        continue
    cache = codex_home / "plugins" / "cache" / market / name
    ok_market = market in markets
    ok_cache = has_plugin_cache(cache)
    src_market = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
    src = src_market / "plugins" / name if str(src_market) else None
    source_exists = bool(src and src.exists())
    status = "OK" if ok_cache else "MISSING"
    if status != "OK":
        missing.append(f"{name}@{market}")

if missing:
    write_diagnostic_log(cfg, missing)
    sys.stdout.flush()
    print("\n仍有插件缺失 / Still missing: " + ", ".join(missing), file=sys.stderr)
    print_agents_help()
    sys.exit(2)
PY

echo
echo "修复完成。/ Repair complete."
echo "下一步 / Next steps:"
PLATFORM_NAME="${CODEX_PLUGIN_REPAIR_PLATFORM:-$(uname -s)}"
case "$PLATFORM_NAME" in
  Darwin)
    echo "1. 如果 Codex Desktop 正在运行，请重启一次以重新加载 config.toml。"
    echo "If Codex Desktop is open, restart it once so it reloads config.toml."
    ;;
  Linux)
    echo "1. 请启动新的 Codex CLI 会话以重新加载 config.toml。"
    echo "Start a new Codex CLI session so it reloads config.toml."
    ;;
  *)
    echo "1. 请重启 Codex 或启动新的 Codex 会话以重新加载 config.toml。"
    echo "Restart Codex or start a new Codex session so it reloads config.toml."
    ;;
esac
echo "2. 可运行 'codex mcp list' 检查工具是否出现。"
echo "You can run 'codex mcp list' to check whether the tools appear."
