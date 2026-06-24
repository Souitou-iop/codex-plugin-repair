#!/usr/bin/env bash
set -euo pipefail

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG="$CODEX_HOME/config.toml"
STAMP="$(date +%Y%m%d%H%M%S)-$$"
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
SCRIPT_PLATFORM="${CODEX_PLUGIN_REPAIR_PLATFORM:-$(uname -s)}"

confirm_execution() {
  if [[ "$LANGUAGE" == "en-US" ]]; then
    echo "Codex Plugin Repair"
    echo "Next, this script will:"
    echo "1. Check your Codex config file."
    echo "2. Back up config.toml before changing anything."
    echo "3. Repair known marketplace entries and service_tier when needed."
    echo "4. Repair cache for plugins already configured or already cached locally."
    case "$SCRIPT_PLATFORM" in
      Darwin)
        echo "5. On macOS, enable Browser, Chrome, and Computer Use, repair bundled marketplace/cache, and refresh latest links when possible."
        ;;
      Linux)
        echo "5. On Linux, keep Desktop-only bundled plugins disabled and repair configured/cached CLI plugin cache only."
        ;;
      *)
        echo "5. On this platform, repair configured/cached plugin cache without forcing Desktop-only plugins."
        ;;
    esac
    echo "It will not delete browser data, browser profiles, or the active config.toml."
    echo "If Codex Desktop is running, it will ask whether to close it before repair. It will not terminate processes without your confirmation."
    echo
    if [[ "${CODEX_PLUGIN_REPAIR_YES:-}" == "1" ]]; then
      return
    fi
    printf "Type yes/y to continue, or no/n to exit: "
  else
    echo "Codex 插件修复脚本"
    echo "接下来脚本将执行以下操作："
    echo "1. 检查 Codex 配置文件。"
    echo "2. 修改前先备份 config.toml。"
    echo "3. 按需修复已知 marketplace 配置和 service_tier。"
    echo "4. 修复已配置或本机已有缓存的插件缓存。"
    case "$SCRIPT_PLATFORM" in
      Darwin)
        echo "5. 在 macOS 上启用 Browser、Chrome、Computer Use，尽量修复 bundled marketplace/cache，并刷新 latest 链接。"
        ;;
      Linux)
        echo "5. 在 Linux 上不启用 Desktop 专属 bundled 插件，只修复已配置/已缓存的 CLI 插件缓存。"
        ;;
      *)
        echo "5. 在当前平台不强行启用 Desktop 专属插件，只修复已配置/已缓存插件缓存。"
        ;;
    esac
    echo "脚本不会删除浏览器数据、浏览器 Profile，也不会删除当前有效的 config.toml。"
    echo "如果检测到 Codex Desktop 正在运行，会询问是否先关闭它；未经确认不会结束进程。"
    echo
    if [[ "${CODEX_PLUGIN_REPAIR_YES:-}" == "1" ]]; then
      return
    fi
    printf "输入 yes 或 y 继续执行，输入 no 或 n 退出: "
  fi
  read -r answer
  normalized_answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
  case "$normalized_answer" in
    yes|y) return ;;
  esac
  if [[ "$LANGUAGE" == "en-US" ]]; then
    echo "Cancelled. No changes were made."
  else
    echo "已取消，未做任何修改。"
  fi
  exit 0
}

show_running_process_warning() {
  local matches
  local codex_matches
  if ! command -v pgrep >/dev/null 2>&1; then
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "Process preflight skipped because pgrep is unavailable."
    else
      echo "未找到 pgrep，跳过进程预检。"
    fi
    return
  fi

  matches="$(find_repair_related_processes)"
  if [[ -z "$matches" ]]; then
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "No common Codex plugin processes were detected."
    else
      echo "未检测到常见的 Codex 插件相关进程。"
    fi
    return
  fi

  if [[ "$LANGUAGE" == "en-US" ]]; then
    echo "Warning: these processes may keep plugin files locked:"
  else
    echo "提醒：以下进程可能正在占用插件文件："
  fi
  printf '%s\n' "$matches" | while IFS= read -r line; do
    echo "- $line"
  done

  codex_matches="$(printf '%s\n' "$matches" | awk '$2 == "Codex" { print }')"
  if [[ -n "$codex_matches" ]]; then
    maybe_close_codex_desktop "$codex_matches"
  fi

  if [[ "$LANGUAGE" == "en-US" ]]; then
    echo "If repair still fails with a file-in-use error, fully quit Codex Desktop and related plugin windows, then run this script again."
  else
    echo "如果稍后仍遇到文件被占用，请完全退出 Codex Desktop 和相关插件窗口，然后重新运行脚本。"
  fi
}

is_yes_answer() {
  local normalized
  normalized="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$normalized" == "yes" || "$normalized" == "y" ]]
}

maybe_close_codex_desktop() {
  local codex_matches="$1"
  local answer
  local should_close=0

  case "${CODEX_PLUGIN_REPAIR_CLOSE_CODEX_DESKTOP:-}" in
    1)
      should_close=1
      ;;
    0)
      if [[ "$LANGUAGE" == "en-US" ]]; then
        echo "Skipping Codex Desktop close because CODEX_PLUGIN_REPAIR_CLOSE_CODEX_DESKTOP=0."
      else
        echo "已按 CODEX_PLUGIN_REPAIR_CLOSE_CODEX_DESKTOP=0 跳过关闭 Codex Desktop。"
      fi
      return
      ;;
    *)
      if [[ "${CODEX_PLUGIN_REPAIR_YES:-}" == "1" ]]; then
        if [[ "$LANGUAGE" == "en-US" ]]; then
          echo "Codex Desktop is running. Automatic yes mode is enabled, so the script will not close it without an explicit close setting."
        else
          echo "检测到 Codex Desktop 正在运行。当前为自动确认模式，未显式要求关闭时不会自动关闭它。"
        fi
        return
      fi
      if [[ "$LANGUAGE" == "en-US" ]]; then
        printf "Codex Desktop is running. Recommended: close it before repair to avoid locked files. You can continue without closing, but restart Codex Desktop after repair. Close it now? Type yes/y to close, or no/n to continue: "
      else
        printf "检测到 Codex Desktop 正在运行。推荐先关闭它再修复，避免文件被占用。不关闭也可以继续运行，但修复完成后需要重启 Codex Desktop。是否现在关闭？输入 yes/y 关闭，输入 no/n 继续: "
      fi
      read -r answer
      if is_yes_answer "$answer"; then
        should_close=1
      fi
      ;;
  esac

  if [[ "$should_close" != "1" ]]; then
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "Continuing without closing Codex Desktop. File-in-use errors are still possible; restart Codex Desktop after repair."
    else
      echo "将继续执行，但 Codex Desktop 未关闭时仍可能出现文件被占用；修复完成后请重启 Codex Desktop。"
    fi
    return
  fi

  if [[ "$SCRIPT_PLATFORM" == "Darwin" && -x /usr/bin/osascript ]]; then
    if /usr/bin/osascript -e 'tell application "Codex" to quit' >/dev/null 2>&1; then
      if [[ "$LANGUAGE" == "en-US" ]]; then
        echo "Requested Codex Desktop to close."
      else
        echo "已请求 Codex Desktop 关闭。"
      fi
      sleep 3
    else
      if [[ "$LANGUAGE" == "en-US" ]]; then
        echo "Could not request Codex Desktop to close. Please close it manually if repair fails."
      else
        echo "无法请求 Codex Desktop 关闭。如果修复失败，请手动关闭后重试。"
      fi
    fi
  else
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "Automatic Codex Desktop close is only supported on macOS Bash. Please close it manually if repair fails."
    else
      echo "Bash 版仅支持在 macOS 上自动请求关闭 Codex Desktop。如果修复失败，请手动关闭后重试。"
    fi
  fi

  if process_name_exists "Codex"; then
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "Codex Desktop may still be running. If repair fails, close it manually and run this script again."
    else
      echo "Codex Desktop 可能仍在运行。如果修复失败，请手动关闭后重新运行脚本。"
    fi
  else
    if [[ "$LANGUAGE" == "en-US" ]]; then
      echo "Codex Desktop is closed. Continuing repair."
    else
      echo "Codex Desktop 已关闭，继续修复。"
    fi
  fi
}

process_name_exists() {
  local name="$1"
  if [[ "$name" == "Codex" ]]; then
    ps ax -o pid=,comm= | awk '$0 ~ /Codex\.app\/Contents\/MacOS\/Codex$/ { found = 1 } END { exit found ? 0 : 1 }'
  else
    pgrep -x "$name" >/dev/null 2>&1
  fi
}

find_repair_related_processes() {
  local name
  local pid
  ps ax -o pid=,comm= | awk '$0 ~ /Codex\.app\/Contents\/MacOS\/Codex$/ { print $1 " Codex" }'
  for name in extension-host codex-computer-use; do
    { pgrep -x "$name" 2>/dev/null || true; } | while IFS= read -r pid; do
      if [[ "$pid" != "$$" ]]; then
        printf '%s %s\n' "$pid" "$name"
      fi
    done
  done | sort -n -u
}

if [[ "$LANGUAGE" == "en-US" ]]; then
  echo "[1/6] Checking running Codex/plugin processes..."
else
  echo "[1/6] 检查正在运行的 Codex/插件进程..."
fi
show_running_process_warning
echo
confirm_execution
echo
if [[ "$LANGUAGE" == "en-US" ]]; then
  echo "[2/6] Checking Codex config..."
else
  echo "[2/6] 检查 Codex 配置..."
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

PYTHON_BIN="${CODEX_PLUGIN_REPAIR_PYTHON:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "错误：找不到 python3，无法继续修复。" >&2
    echo "Error: python3 was not found, so the repair cannot continue." >&2
    if mkdir -p "$CODEX_HOME" 2>/dev/null; then
      {
        echo "Codex Plugin Repair diagnostic log"
        echo "Codex 插件修复诊断日志"
        echo "timestamp=$STAMP"
        echo "codex_home=$CODEX_HOME"
        echo "config=$CONFIG"
        echo "error=missing python3"
      } > "$LOG"
      print_agents_help "$LOG"
    fi
    exit 1
  fi
elif ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "错误：指定的 Python 不可用：$PYTHON_BIN" >&2
  echo "Error: configured Python is not available: $PYTHON_BIN" >&2
  if mkdir -p "$CODEX_HOME" 2>/dev/null; then
    {
      echo "Codex Plugin Repair diagnostic log"
      echo "Codex 插件修复诊断日志"
      echo "timestamp=$STAMP"
      echo "codex_home=$CODEX_HOME"
      echo "config=$CONFIG"
      echo "error=unavailable Python: $PYTHON_BIN"
    } > "$LOG"
    print_agents_help "$LOG"
  fi
  exit 1
fi

echo "[3/6] 备份配置文件 / Backing up config..."
cp "$CONFIG" "$BACKUP"
echo "已备份配置文件。/ Backed up config to: $BACKUP"

"$PYTHON_BIN" - "$CODEX_HOME" "$CONFIG" "$LOG" "$BACKUP" "$STAMP" <<'PY'
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
text = config_path.read_text(encoding="utf-8-sig")
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
        rf'(^\[plugins\."{re.escape(plugin_id)}"\]\r?\n)(.*?)(?=^\[|\Z)',
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
    block_re = re.compile(rf'(^\[marketplaces\.{re.escape(name)}\]\r?\n)(.*?)(?=^\[|\Z)', re.M | re.S)
    m = block_re.search(src)
    body = f'last_updated = {json.dumps(repair_timestamp)}\nsource_type = "local"\nsource = {json.dumps(str(source))}\n'
    if m:
        old = m.group(2)
        old = re.sub(r'^last_updated\s*=.*$', body.splitlines()[0], old, flags=re.M) if re.search(r'^last_updated\s*=', old, re.M) else body.splitlines()[0] + "\n" + old
        old = re.sub(r'^source_type\s*=.*$', 'source_type = "local"', old, flags=re.M) if re.search(r'^source_type\s*=', old, re.M) else old + 'source_type = "local"\n'
        old = re.sub(r'^source\s*=.*$', f'source = {json.dumps(str(source))}', old, flags=re.M) if re.search(r'^source\s*=', old, re.M) else old + f'source = {json.dumps(str(source))}\n'
        return src[:m.start()] + m.group(1) + old + src[m.end():]

    first_market = re.search(r'^\[marketplaces\.', src, re.M)
    if not first_market:
        return src.rstrip() + f'\n\n[marketplaces.{name}]\n{body}\n'

    # Keep openai-curated next to the other marketplace declarations.
    market_blocks = list(re.finditer(r'^\[marketplaces\.[^\]]+\]\r?\n.*?(?=^\[|\Z)', src, re.M | re.S))
    insert_at = market_blocks[-1].end() if market_blocks else first_market.end()
    return src[:insert_at].rstrip() + f'\n\n[marketplaces.{name}]\n{body}' + "\n" + src[insert_at:].lstrip()

def get_marketplace_source(src, name, default):
    m = re.search(rf'^\[marketplaces\.{re.escape(name)}\]\r?\n(.*?)(?=^\[|\Z)', src, re.M | re.S)
    if not m:
        return pathlib.Path(default).expanduser() if default else None
    s = re.search(r'^source\s*=\s*"([^"]+)"', m.group(1), re.M)
    if s:
        return pathlib.Path(s.group(1)).expanduser()
    return pathlib.Path(default).expanduser() if default else None

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

print(f"\n[4/6] 检测平台和修复 marketplace / Detecting platform and repairing marketplaces: {detected_platform}")

def yn(value):
    return "true" if value else "false"

def marketplace_tables(src):
    return dict(re.findall(r'^\[marketplaces\.([^\]]+)\]\r?\n(.*?)(?=^\[|\Z)', src, re.M | re.S))

def plugin_tables(src):
    for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\r?\n(.*?)(?=^\[|\Z)', src, re.M | re.S):
        name, market, body = m.group(1), m.group(2), m.group(3)
        enabled = bool(re.search(r'^enabled\s*=\s*true\s*$', body, re.M))
        yield name, market, enabled

def plugin_cache_ready(plugin_name, plugin_root):
    required = [plugin_root / ".codex-plugin" / "plugin.json"]
    if system_name == "windows":
        if plugin_name == "browser":
            required.append(plugin_root / "scripts" / "browser-client.mjs")
        elif plugin_name == "chrome":
            required.append(plugin_root / "scripts" / "browser-client.mjs")
            required.append(plugin_root / "extension-host" / "windows" / "x64" / "extension-host.exe")
        elif plugin_name == "computer-use":
            required.append(plugin_root / "scripts" / "computer-use-client.mjs")
            required.append(plugin_root / "node_modules" / "@oai" / "sky" / "bin" / "windows" / "codex-computer-use.exe")
    return all(p.is_file() for p in required)

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

def has_plugin_cache(dst_base, plugin_name):
    if not dst_base.exists():
        return False
    return any(
        p.is_dir() and not p.is_symlink() and plugin_cache_ready(plugin_name, p)
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
        has_source = bool(source) and source.exists()
        has_cache = market in cache_markets
        label = "KNOWN" if market in known_marketplaces or has_table else "UNKNOWN"
        lines.append(f"{label} {market} table={yn(has_table)} source={yn(has_source)} cache={yn(has_cache)}")

    lines.append("Enabled plugins / 已启用插件:")
    for name, market, enabled in plugin_tables(cfg):
        if not enabled:
            continue
        cache = codex_home / "plugins" / "cache" / market / name
        source_market = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
        source = source_market / "plugins" / name if source_market else None
        ok_market = market in markets
        ok_cache = has_plugin_cache(cache, name)
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

def write_failure_log(error, advice=()):
    lines = [
        "Codex Plugin Repair diagnostic log",
        "Codex 插件修复诊断日志",
        f"timestamp={stamp}",
        f"platform={detected_platform}",
        f"codex_home={codex_home}",
        f"config={config_path}",
        f"backup={backup_path}",
        f"error={error}",
    ]
    if advice:
        lines.append("")
        lines.append("Advice / 建议:")
        lines.extend(advice)
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

config_path.write_text(text, encoding="utf-8")

def plugin_version(plugin_root):
    plugin_json = plugin_root / ".codex-plugin" / "plugin.json"
    if not plugin_json.exists():
        return None
    with plugin_json.open() as f:
        return json.load(f).get("version")

def cached_plugin_dirs(plugin_name, dst_base):
    if not dst_base.exists():
        return []
    return sorted(
        p for p in dst_base.iterdir()
        if p.is_dir() and not p.is_symlink() and plugin_cache_ready(plugin_name, p)
    )

def backup_path_for(path):
    candidate = pathlib.Path(f"{path}.bak-plugin-repair-{stamp}")
    index = 1
    while candidate.exists() or candidate.is_symlink():
        candidate = pathlib.Path(f"{path}.bak-plugin-repair-{stamp}-{index}")
        index += 1
    return candidate

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
    dst_base = codex_home / "plugins" / "cache" / marketplace / plugin_name
    existing = cached_plugin_dirs(plugin_name, dst_base)
    src_market = get_marketplace_source(config_path.read_text(), marketplace, known_marketplaces.get(marketplace, ""))
    if not src_market:
        if existing:
            print(f"缓存已有效 / Cache already valid for {plugin_name}@{marketplace}: {existing[-1]}")
            return True
        print(f"跳过 {plugin_name}@{marketplace}：marketplace 源未知 / Skip {plugin_name}@{marketplace}: marketplace source is unknown")
        return False

    src = src_market / "plugins" / plugin_name
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
        if plugin_cache_ready(plugin_name, dst):
            print(f"缓存已存在 / Cache exists for {plugin_name}@{marketplace}: {dst}")
        else:
            backup_dst = backup_path_for(dst)
            try:
                shutil.move(str(dst), str(backup_dst))
                shutil.copytree(src, dst, symlinks=True)
            except Exception as exc:
                write_failure_log(
                    f"Could not rebuild incomplete cache for {plugin_name}@{marketplace}: {exc}",
                    [
                        "请完全退出 Codex Desktop，然后重新运行本脚本。",
                        "如果相关插件窗口仍在运行，请关闭后重试。",
                        "Fully quit Codex Desktop, then run this script again.",
                        "If related plugin windows are still running, close them and retry.",
                    ],
                )
                print(f"无法重建残缺缓存 / Could not rebuild incomplete cache for {plugin_name}@{marketplace}: {exc}", file=sys.stderr)
                print_agents_help()
                sys.exit(3)
            print(f"已备份残缺缓存 / Backed up incomplete cache for {plugin_name}@{marketplace}: {backup_dst}")
            print(f"已重建插件缓存 / Rebuilt {plugin_name}@{marketplace} -> {dst}")
    else:
        shutil.copytree(src, dst, symlinks=True)
        print(f"已复制插件 / Copied {plugin_name}@{marketplace} -> {dst}")

    if marketplace == "openai-bundled":
        update_latest_link(dst_base, dst)
    return True

def enabled_plugins(src):
    for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\r?\n(.*?)(?=^\[|\Z)', src, re.M | re.S):
        name, market, body = m.group(1), m.group(2), m.group(3)
        if re.search(r'^enabled\s*=\s*true\s*$', body, re.M):
            yield name, market

def configured_plugins(src):
    for name, market, _enabled in plugin_tables(src):
        yield name, market

def cached_plugins():
    cache_root = codex_home / "plugins" / "cache"
    if not cache_root.exists():
        return
    for market_dir in sorted(p for p in cache_root.iterdir() if p.is_dir()):
        for plugin_dir in sorted(p for p in market_dir.iterdir() if p.is_dir()):
            yield plugin_dir.name, market_dir.name

def repair_targets(src):
    seen = set()
    for name, market in configured_plugins(src):
        key = (name, market)
        if key not in seen:
            seen.add(key)
            yield key
    for name, market in cached_plugins() or ():
        key = (name, market)
        if key not in seen:
            seen.add(key)
            yield key

# Repair configured plugins and plugins that were already present in the local cache.
print("\n[5/6] 修复已配置和已缓存插件 / Repairing configured and cached plugin cache...")
for name, market in repair_targets(config_path.read_text()):
    copy_plugin(market, name)

cfg = config_path.read_text()
print("\n[6/6] 生成插件覆盖报告 / Generating plugin coverage report...")
print_plugin_coverage_report(cfg)
markets = set(re.findall(r'^\[marketplaces\.([^\]]+)\]', cfg, re.M))
missing = []
for m in re.finditer(r'^\[plugins\."([^@"]+)@([^"]+)"\]\r?\n(.*?)(?=^\[|\Z)', cfg, re.M | re.S):
    name, market, body = m.group(1), m.group(2), m.group(3)
    if not re.search(r'^enabled\s*=\s*true\s*$', body, re.M):
        continue
    cache = codex_home / "plugins" / "cache" / market / name
    ok_market = market in markets
    ok_cache = has_plugin_cache(cache, name)
    src_market = get_marketplace_source(cfg, market, known_marketplaces.get(market, ""))
    src = src_market / "plugins" / name if src_market else None
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
PLATFORM_NAME="${CODEX_PLUGIN_REPAIR_PLATFORM:-$(uname -s)}"
if [[ "$LANGUAGE" == "en-US" ]]; then
  echo "Repair complete."
  echo "Next step:"
  case "$PLATFORM_NAME" in
    Darwin)
      echo "- Restart Codex Desktop so it reloads config.toml."
      ;;
    Linux)
      echo "- Start a new Codex CLI session so it reloads config.toml."
      ;;
    *)
      echo "- Restart Codex or start a new Codex session so it reloads config.toml."
      ;;
  esac
else
  echo "修复完成。"
  echo "后续建议："
  case "$PLATFORM_NAME" in
    Darwin)
      echo "- 重启 Codex Desktop，让它重新加载 config.toml。"
      ;;
    Linux)
      echo "- 启动新的 Codex CLI 会话，让它重新加载 config.toml。"
      ;;
    *)
      echo "- 重启 Codex 或启动新的 Codex 会话，让它重新加载 config.toml。"
      ;;
  esac
fi
