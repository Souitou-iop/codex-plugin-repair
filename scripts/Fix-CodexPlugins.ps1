param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }),
    [string]$PackageName = "OpenAI.Codex",
    [string]$BundledSourceRoot = $(if ($env:CODEX_PLUGIN_REPAIR_BUNDLED_SOURCE_ROOT) { $env:CODEX_PLUGIN_REPAIR_BUNDLED_SOURCE_ROOT } else { "" }),
    [string]$Language = $(if ($env:CODEX_PLUGIN_REPAIR_LANGUAGE) { $env:CODEX_PLUGIN_REPAIR_LANGUAGE } else { "" }),
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

if ($env:CODEX_PLUGIN_REPAIR_YES -eq "1") {
    $Yes = $true
}

$Config = Join-Path $CodexHome "config.toml"
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
$Backup = "$Config.bak-plugin-repair-$Stamp"
$Log = Join-Path $CodexHome "codex-plugin-repair-diagnostics-$Stamp.log"

function Get-SelectedLanguage {
    param([string]$RequestedLanguage)

    if ($RequestedLanguage -match '^(zh|zh-CN|cn|1)$') { return "zh-CN" }
    if ($RequestedLanguage -match '^(en|en-US|2)$') { return "en-US" }

    Write-Host "请选择语言 / Choose language:"
    Write-Host "1. 简体中文"
    Write-Host "2. English"
    $Choice = Read-Host "请输入 1 或 2，然后按 Enter / Enter 1 or 2, then press Enter"
    if ($Choice -eq "2") { return "en-US" }
    return "zh-CN"
}

function Get-PromptPlatform {
    if ($env:CODEX_PLUGIN_REPAIR_PLATFORM) {
        return $env:CODEX_PLUGIN_REPAIR_PLATFORM
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return "Windows"
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return "Darwin"
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return "Linux"
    }
    return "Unknown"
}

function Confirm-Execution {
    param(
        [string]$SelectedLanguage,
        [string]$PlatformName,
        [bool]$SkipPrompt
    )

    $PlatformLower = $PlatformName.ToLowerInvariant()

    if ($SelectedLanguage -eq "en-US") {
        Write-Host "Codex Plugin Repair"
        Write-Host "This script will:"
        Write-Host "1. Check your Codex config file."
        Write-Host "2. Back up config.toml before changing anything."
        Write-Host "3. Repair known marketplace entries and service_tier when needed."
        Write-Host "4. Repair cache for plugins that are already enabled."
        if ($PlatformLower -eq "windows") {
            Write-Host "5. On Windows, enable Browser, Chrome, and Computer Use bundled plugins."
            Write-Host "6. On Windows, rebuild bundled marketplace/cache and update the Computer Use notify helper path when possible."
        } elseif ($PlatformLower -eq "darwin") {
            Write-Host "5. On macOS, enable Browser, Chrome, and Computer Use bundled plugins."
            Write-Host "6. On macOS, repair bundled marketplace/cache and refresh latest links when possible."
        } elseif ($PlatformLower -eq "linux") {
            Write-Host "5. On Linux, keep Desktop-only bundled plugins disabled and repair already-enabled CLI plugin cache only."
        } else {
            Write-Host "5. On this platform, repair already-enabled plugin cache without forcing Desktop-only plugins."
        }
        Write-Host "It will not delete browser data, browser profiles, or the active config.toml."
        Write-Host "It will not close apps or terminate processes automatically. If files are locked, it will ask you to close Codex Desktop and retry."
        Write-Host ""
        if ($SkipPrompt) { return }
        $Answer = Read-Host "Type yes/y to continue, or no/n to exit"
    } else {
        Write-Host "Codex 插件修复脚本"
        Write-Host "这个脚本将执行以下操作："
        Write-Host "1. 检查 Codex 配置文件。"
        Write-Host "2. 修改前先备份 config.toml。"
        Write-Host "3. 按需修复已知 marketplace 配置和 service_tier。"
        Write-Host "4. 修复当前已经启用插件的缓存。"
        if ($PlatformLower -eq "windows") {
            Write-Host "5. 在 Windows 上启用 Browser、Chrome、Computer Use bundled 插件。"
            Write-Host "6. 在 Windows 上尽量重建 bundled marketplace/cache，并修正 Computer Use notify helper 路径。"
        } elseif ($PlatformLower -eq "darwin") {
            Write-Host "5. 在 macOS 上启用 Browser、Chrome、Computer Use bundled 插件。"
            Write-Host "6. 在 macOS 上尽量修复 bundled marketplace/cache，并刷新 latest 链接。"
        } elseif ($PlatformLower -eq "linux") {
            Write-Host "5. 在 Linux 上不启用 Desktop 专属 bundled 插件，只修复已启用的 CLI 插件缓存。"
        } else {
            Write-Host "5. 在当前平台不强行启用 Desktop 专属插件，只修复已启用插件缓存。"
        }
        Write-Host "脚本不会删除浏览器数据、浏览器 Profile，也不会删除当前有效的 config.toml。"
        Write-Host "脚本不会自动关闭应用或结束进程；如果文件被占用，会提示你关闭 Codex Desktop 后重试。"
        Write-Host ""
        if ($SkipPrompt) { return }
        $Answer = Read-Host "输入 yes 或 y 继续执行，输入 no 或 n 退出"
    }

    $NormalizedAnswer = $Answer.Trim().ToLowerInvariant()
    if ($NormalizedAnswer -eq "yes" -or $NormalizedAnswer -eq "y") {
        return
    }

    if ($SelectedLanguage -eq "en-US") {
        Write-Host "Cancelled. No changes were made."
    } else {
        Write-Host "已取消，未做任何修改。"
    }
    exit 0
}

$SelectedLanguage = Get-SelectedLanguage -RequestedLanguage $Language
$PromptPlatform = Get-PromptPlatform
Confirm-Execution -SelectedLanguage $SelectedLanguage -PlatformName $PromptPlatform -SkipPrompt ([bool]$Yes)
Write-Host ""
if ($SelectedLanguage -eq "en-US") {
    Write-Host "[1/5] Checking Codex config..."
} else {
    Write-Host "[1/5] 检查 Codex 配置..."
}

function Write-AgentsHelp {
    param([string]$LogPath)
    [Console]::Error.WriteLine("诊断日志 / Diagnostic log: $LogPath")
    [Console]::Error.WriteLine("你可以把这份日志粘贴到 Agents / Codex 软件中继续排查。")
    [Console]::Error.WriteLine("You can paste this log into Agents / Codex to continue troubleshooting.")
}

function Write-MissingConfigLog {
    param([string]$LogPath)
    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
    @(
        "Codex Plugin Repair diagnostic log",
        "Codex 插件修复诊断日志",
        "timestamp=$Stamp",
        "codex_home=$CodexHome",
        "config=$Config",
        "error=missing Codex config"
    ) | Set-Content -LiteralPath $LogPath -Encoding UTF8
}

function Write-FailureLog {
    param(
        [string]$ErrorMessage,
        [string[]]$Advice = @()
    )

    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
    $Lines = @(
        "Codex Plugin Repair diagnostic log",
        "Codex 插件修复诊断日志",
        "timestamp=$Stamp",
        "codex_home=$CodexHome",
        "config=$Config",
        "backup=$Backup",
        "error=$ErrorMessage"
    )
    if ($Advice.Count -gt 0) {
        $Lines += ""
        $Lines += "Advice / 建议:"
        $Lines += $Advice
    }
    $Lines | Set-Content -LiteralPath $Log -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    Write-MissingConfigLog -LogPath $Log
    [Console]::Error.WriteLine("错误：找不到 Codex 配置文件。 / Error: missing Codex config: $Config")
    Write-AgentsHelp -LogPath $Log
    exit 1
}

Write-Host "[2/5] 备份配置文件 / Backing up config..."
Copy-Item -LiteralPath $Config -Destination $Backup -Force
Write-Host "已备份配置文件。/ Backed up config to: $Backup"

function Format-Bool {
    param([bool]$Value)
    if ($Value) { return "true" }
    return "false"
}

function Convert-ToTomlPath {
    param([string]$Path)
    return $Path.Replace("\", "/")
}

function Get-DetectedPlatform {
    if ($env:CODEX_PLUGIN_REPAIR_PLATFORM) {
        return $env:CODEX_PLUGIN_REPAIR_PLATFORM
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return "Windows"
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return "Darwin"
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return "Linux"
    }
    return "Unknown"
}

function Get-WindowsBundledSourceRoot {
    param(
        [string]$PackageName,
        [string]$SourceOverride
    )

    if ($SourceOverride) {
        if (Test-Path -LiteralPath $SourceOverride -PathType Container) {
            return (Resolve-Path -LiteralPath $SourceOverride).Path
        }
        Write-Host "Windows bundled 源覆盖路径缺失 / Windows bundled source override missing: $SourceOverride"
        return $null
    }

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Host "Get-AppxPackage 不可用，将保留现有 bundled marketplace 源 / Get-AppxPackage is unavailable; keeping existing bundled marketplace source."
        return $null
    }

    $Package = Get-AppxPackage -Name $PackageName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $Package) {
        Write-Host "找不到 AppX 包 / Could not find AppX package: $PackageName"
        return $null
    }

    $Source = Join-Path $Package.InstallLocation "app/resources/plugins/openai-bundled"
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Host "找不到 bundled 插件源 / Could not find bundled plugin source: $Source"
        return $null
    }

    return $Source
}

function Sync-WindowsBundledMarketplace {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not $Source) {
        return $false
    }

    $Parent = Split-Path -Path $Destination -Parent
    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    if (Test-Path -LiteralPath $Destination) {
        $BackupPath = "$Destination.bak-plugin-repair-$Stamp"
        try {
            Move-Item -LiteralPath $Destination -Destination $BackupPath -Force -ErrorAction Stop
        } catch {
            $Message = $_.Exception.Message
            $Advice = @(
                "请完全退出 Codex Desktop，然后重新运行本脚本。",
                "如果 Chrome/Browser 插件仍在运行，请也关闭相关浏览器插件窗口后重试。",
                "Fully quit Codex Desktop, then run this script again.",
                "If the Chrome/Browser plugin helper is still running, close related browser/plugin windows and retry."
            )
            Write-FailureLog -ErrorMessage "Could not back up bundled marketplace: $Message" -Advice $Advice
            [Console]::Error.WriteLine("无法备份 bundled marketplace，目录可能仍被进程占用。")
            [Console]::Error.WriteLine("Could not back up bundled marketplace; the directory may still be locked by another process.")
            [Console]::Error.WriteLine("请完全退出 Codex Desktop 后重新运行脚本。")
            [Console]::Error.WriteLine("Fully quit Codex Desktop, then run this script again.")
            [Console]::Error.WriteLine("原始错误 / Original error: $Message")
            Write-AgentsHelp -LogPath $Log
            exit 3
        }
        Write-Host "已备份 bundled marketplace / Backed up bundled marketplace to: $BackupPath"
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
    Write-Host "已同步 Windows bundled marketplace / Synced Windows bundled marketplace: $Source -> $Destination"
    return $true
}

function Set-PluginEnabled {
    param(
        [string]$Text,
        [string]$PluginId,
        [bool]$Enabled = $true
    )

    $Value = if ($Enabled) { "true" } else { "false" }
    $Pattern = "(?ms)(^\[plugins\.`"$([regex]::Escape($PluginId))`"\]\r?\n)(.*?)(?=^\[|\z)"
    $Match = [regex]::Match($Text, $Pattern)
    if ($Match.Success) {
        $Body = $Match.Groups[2].Value
        if ($Body -match "(?m)^enabled\s*=") {
            $Body = [regex]::Replace($Body, "(?m)^enabled\s*=.*$", "enabled = $Value")
        } else {
            $Body = "enabled = $Value`n$Body"
        }
        return $Text.Substring(0, $Match.Index) + $Match.Groups[1].Value + $Body + $Text.Substring($Match.Index + $Match.Length)
    }

    $FirstPlugin = [regex]::Match($Text, "(?m)^\[plugins\.")
    $Block = "`n[plugins.`"$PluginId`"]`nenabled = $Value`n"
    if ($FirstPlugin.Success) {
        return $Text.Substring(0, $FirstPlugin.Index).TrimEnd() + "`n" + $Block + "`n" + $Text.Substring($FirstPlugin.Index).TrimStart()
    }
    return $Text.TrimEnd() + "`n" + $Block + "`n"
}

function Ensure-Marketplace {
    param(
        [string]$Text,
        [string]$Name,
        [string]$Source
    )

    $Source = Convert-ToTomlPath $Source
    $Timestamp = if ($env:CODEX_PLUGIN_REPAIR_TIMESTAMP) { $env:CODEX_PLUGIN_REPAIR_TIMESTAMP } else { [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    $Body = "last_updated = `"$Timestamp`"`nsource_type = `"local`"`nsource = `"$Source`"`n"
    $Pattern = "(?ms)(^\[marketplaces\.$([regex]::Escape($Name))\]\r?\n)(.*?)(?=^\[|\z)"
    $Match = [regex]::Match($Text, $Pattern)

    if ($Match.Success) {
        $Old = $Match.Groups[2].Value
        if ($Old -match "(?m)^last_updated\s*=") {
            $Old = [regex]::Replace($Old, "(?m)^last_updated\s*=.*$", "last_updated = `"$Timestamp`"")
        } else {
            $Old = "last_updated = `"$Timestamp`"`n$Old"
        }
        if ($Old -match "(?m)^source_type\s*=") {
            $Old = [regex]::Replace($Old, "(?m)^source_type\s*=.*$", 'source_type = "local"')
        } else {
            $Old += 'source_type = "local"' + "`n"
        }
        if ($Old -match "(?m)^source\s*=") {
            $Old = [regex]::Replace($Old, "(?m)^source\s*=.*$", "source = `"$Source`"")
        } else {
            $Old += "source = `"$Source`"`n"
        }
        return $Text.Substring(0, $Match.Index) + $Match.Groups[1].Value + $Old + $Text.Substring($Match.Index + $Match.Length)
    }

    $MarketBlocks = [regex]::Matches($Text, "(?ms)^\[marketplaces\.[^\]]+\]\r?\n.*?(?=^\[|\z)")
    if ($MarketBlocks.Count -gt 0) {
        $Last = $MarketBlocks[$MarketBlocks.Count - 1]
        return $Text.Substring(0, $Last.Index + $Last.Length).TrimEnd() + "`n`n[marketplaces.$Name]`n$Body`n" + $Text.Substring($Last.Index + $Last.Length).TrimStart()
    }
    return $Text.TrimEnd() + "`n`n[marketplaces.$Name]`n$Body`n"
}

function Get-MarketplaceSource {
    param(
        [string]$Text,
        [string]$Name,
        [string]$Default
    )

    $Pattern = "(?ms)^\[marketplaces\.$([regex]::Escape($Name))\]\r?\n(.*?)(?=^\[|\z)"
    $Match = [regex]::Match($Text, $Pattern)
    if (-not $Match.Success) {
        return $Default
    }
    $SourceMatch = [regex]::Match($Match.Groups[1].Value, '(?m)^source\s*=\s*"([^"]+)"')
    if ($SourceMatch.Success) {
        return $SourceMatch.Groups[1].Value
    }
    return $Default
}

function Get-PluginVersion {
    param([string]$PluginRoot)
    $PluginJson = Join-Path $PluginRoot ".codex-plugin/plugin.json"
    if (-not (Test-Path -LiteralPath $PluginJson -PathType Leaf)) {
        return $null
    }
    return (Get-Content -LiteralPath $PluginJson -Raw | ConvertFrom-Json).version
}

function Get-CachedPluginDirs {
    param([string]$Base)
    if (-not (Test-Path -LiteralPath $Base -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $Base -Directory | Where-Object {
        $_.Name -ne "latest" -and $_.Name -notlike "*.bak-plugin-repair-*" -and -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName ".codex-plugin/plugin.json") -PathType Leaf)
    } | Sort-Object FullName)
}

function Update-LatestLink {
    param(
        [string]$Base,
        [string]$Target
    )

    $Latest = Join-Path $Base "latest"
    if (Test-Path -LiteralPath $Latest) {
        Remove-Item -LiteralPath $Latest -Recurse -Force
    }
    New-Item -ItemType Junction -Path $Latest -Target $Target | Out-Null
    Write-Host "已更新 latest 链接 / Updated latest link: $Latest -> $Target"
}

function Test-PluginCacheReady {
    param(
        [string]$PluginName,
        [string]$PluginRoot,
        [string]$PlatformName
    )

    $Required = @((Join-Path $PluginRoot ".codex-plugin/plugin.json"))
    if ($PlatformName -eq "windows") {
        switch ($PluginName) {
            "browser" {
                $Required += (Join-Path $PluginRoot "scripts/browser-client.mjs")
            }
            "chrome" {
                $Required += (Join-Path $PluginRoot "scripts/browser-client.mjs")
                $Required += (Join-Path $PluginRoot "extension-host/windows/x64/extension-host.exe")
            }
            "computer-use" {
                $Required += (Join-Path $PluginRoot "scripts/computer-use-client.mjs")
                $Required += (Join-Path $PluginRoot "node_modules/@oai/sky/bin/windows/codex-computer-use.exe")
            }
        }
    }

    $Missing = @($Required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($Missing.Count -gt 0) {
        foreach ($MissingFile in $Missing) {
            Write-Host "缓存文件缺失 / Missing cache file for ${PluginName}: $MissingFile"
        }
        return $false
    }
    return $true
}

function Copy-Plugin {
    param(
        [string]$Marketplace,
        [string]$PluginName,
        [hashtable]$KnownMarketplaces
    )

    $CurrentText = Get-Content -LiteralPath $Config -Raw
    $DefaultSource = if ($KnownMarketplaces.ContainsKey($Marketplace)) { $KnownMarketplaces[$Marketplace] } else { "" }
    $SourceMarket = Get-MarketplaceSource -Text $CurrentText -Name $Marketplace -Default $DefaultSource
    if (-not $SourceMarket) {
        Write-Host "跳过 ${PluginName}@${Marketplace}：marketplace 源未知 / Skip ${PluginName}@${Marketplace}: marketplace source is unknown"
        return $false
    }

    $Source = Join-Path $SourceMarket "plugins/$PluginName"
    $DestBase = Join-Path $CodexHome "plugins/cache/$Marketplace/$PluginName"
    $Existing = Get-CachedPluginDirs $DestBase

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        if ($Existing.Count -gt 0) {
            Write-Host "缓存已有效 / Cache already valid for ${PluginName}@${Marketplace}: $($Existing[-1].FullName)"
            if ($Marketplace -eq "openai-bundled") {
                Update-LatestLink -Base $DestBase -Target $Existing[-1].FullName
            }
            return $true
        }
        Write-Host "跳过 ${PluginName}@${Marketplace}：marketplace 插件源缺失 / Skip ${PluginName}@${Marketplace}: marketplace plugin source missing: $Source"
        return $false
    }

    $Version = Get-PluginVersion $Source
    if (-not $Version) {
        if ($Existing.Count -gt 0) {
            Write-Host "缓存已有效 / Cache already valid for ${PluginName}@${Marketplace}: $($Existing[-1].FullName)"
            if ($Marketplace -eq "openai-bundled") {
                Update-LatestLink -Base $DestBase -Target $Existing[-1].FullName
            }
            return $true
        }
        Write-Host "跳过 ${PluginName}@${Marketplace}：plugin.json 缺少版本号 / Skip ${PluginName}@${Marketplace}: missing version in $Source/.codex-plugin/plugin.json"
        return $false
    }

    $Dest = Join-Path $DestBase $Version
    New-Item -ItemType Directory -Path $DestBase -Force | Out-Null
    if (Test-Path -LiteralPath $Dest -PathType Container) {
        if (Test-PluginCacheReady -PluginName $PluginName -PluginRoot $Dest -PlatformName $SystemName) {
            Write-Host "缓存已存在 / Cache exists for ${PluginName}@${Marketplace}: $Dest"
        } else {
            $BackupDest = "$Dest.bak-plugin-repair-$Stamp"
            try {
                Move-Item -LiteralPath $Dest -Destination $BackupDest -Force -ErrorAction Stop
            } catch {
                $Message = $_.Exception.Message
                $Advice = @(
                    "请完全退出 Codex Desktop，然后重新运行本脚本。",
                    "如果相关插件窗口仍在运行，请关闭后重试。",
                    "Fully quit Codex Desktop, then run this script again.",
                    "If related plugin windows are still running, close them and retry."
                )
                Write-FailureLog -ErrorMessage "Could not back up incomplete cache for ${PluginName}@${Marketplace}: $Message" -Advice $Advice
                [Console]::Error.WriteLine("无法备份残缺缓存，目录可能仍被进程占用。")
                [Console]::Error.WriteLine("Could not back up incomplete cache; the directory may still be locked by another process.")
                [Console]::Error.WriteLine("原始错误 / Original error: $Message")
                Write-AgentsHelp -LogPath $Log
                exit 3
            }
            Write-Host "已备份残缺缓存 / Backed up incomplete cache for ${PluginName}@${Marketplace}: $BackupDest"
            Copy-Item -LiteralPath $Source -Destination $Dest -Recurse
            Write-Host "已重建插件缓存 / Rebuilt ${PluginName}@${Marketplace} -> $Dest"
        }
    } else {
        Copy-Item -LiteralPath $Source -Destination $Dest -Recurse
        Write-Host "已复制插件 / Copied ${PluginName}@${Marketplace} -> $Dest"
    }

    if ($Marketplace -eq "openai-bundled") {
        Update-LatestLink -Base $DestBase -Target $Dest
    }
    return $true
}

function Get-EnabledPlugins {
    param([string]$Text)
    $Pattern = '(?ms)^\[plugins\."([^@"]+)@([^"]+)"\]\r?\n(.*?)(?=^\[|\z)'
    foreach ($Match in [regex]::Matches($Text, $Pattern)) {
        if ($Match.Groups[3].Value -match "(?m)^enabled\s*=\s*true\s*$") {
            [pscustomobject]@{
                Name = $Match.Groups[1].Value
                Marketplace = $Match.Groups[2].Value
            }
        }
    }
}

function Set-NotifyHelper {
    param(
        [string]$Text,
        [string]$HelperPath
    )

    $EscapedHelperPath = $HelperPath.Replace("'", "''")
    $NotifyLine = "notify = [ '$EscapedHelperPath', 'turn-ended' ]"
    if ($Text -match "(?m)^notify\s*=") {
        return [regex]::Replace($Text, "(?m)^notify\s*=.*$", $NotifyLine)
    }

    if ($Text -match "(?m)^sandbox_mode\s*=") {
        return [regex]::Replace($Text, "(?m)^(sandbox_mode\s*=.*)$", "`$1`n$NotifyLine")
    }

    return $NotifyLine + "`n" + $Text
}

function Get-MarketplaceTables {
    param([string]$Text)
    $Tables = @{}
    foreach ($Match in [regex]::Matches($Text, '(?ms)^\[marketplaces\.([^\]]+)\]\r?\n(.*?)(?=^\[|\z)')) {
        $Tables[$Match.Groups[1].Value] = $Match.Groups[2].Value
    }
    return $Tables
}

function Get-PluginTables {
    param([string]$Text)
    $Pattern = '(?ms)^\[plugins\."([^@"]+)@([^"]+)"\]\r?\n(.*?)(?=^\[|\z)'
    foreach ($Match in [regex]::Matches($Text, $Pattern)) {
        [pscustomobject]@{
            Name = $Match.Groups[1].Value
            Marketplace = $Match.Groups[2].Value
            Enabled = ($Match.Groups[3].Value -match "(?m)^enabled\s*=\s*true\s*$")
        }
    }
}

function Get-CacheMarketplaces {
    $CacheRoot = Join-Path $CodexHome "plugins/cache"
    if (-not (Test-Path -LiteralPath $CacheRoot -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $CacheRoot -Directory | ForEach-Object { $_.Name })
}

function Test-PluginCacheExists {
    param([string]$Base)
    return (Get-CachedPluginDirs $Base).Count -gt 0
}

function Get-SourcePluginNames {
    param([string]$SourceRoot)
    $PluginsRoot = Join-Path $SourceRoot "plugins"
    if (-not (Test-Path -LiteralPath $PluginsRoot -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $PluginsRoot -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName ".codex-plugin/plugin.json") -PathType Leaf
    } | ForEach-Object { $_.Name } | Sort-Object)
}

function Write-PluginCoverageReport {
    param(
        [string]$Text,
        [hashtable]$KnownMarketplaces
    )

    Write-Host ""
    foreach ($Line in Get-PluginCoverageReportLines -Text $Text -KnownMarketplaces $KnownMarketplaces) {
        Write-Host $Line
    }
}

function Get-PluginCoverageReportLines {
    param(
        [string]$Text,
        [hashtable]$KnownMarketplaces
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("插件覆盖报告 / Plugin coverage report:")
    $MarketplaceTables = Get-MarketplaceTables $Text
    $CacheMarkets = @(Get-CacheMarketplaces)
    $AllMarkets = @($MarketplaceTables.Keys + $CacheMarkets + $KnownMarketplaces.Keys | Sort-Object -Unique)

    $Lines.Add("Marketplaces / 插件市场:")
    foreach ($Market in $AllMarkets) {
        $DefaultSource = if ($KnownMarketplaces.ContainsKey($Market)) { $KnownMarketplaces[$Market] } else { "" }
        $SourceMarket = Get-MarketplaceSource -Text $Text -Name $Market -Default $DefaultSource
        $HasTable = $MarketplaceTables.ContainsKey($Market)
        $HasSource = $SourceMarket -and (Test-Path -LiteralPath $SourceMarket -PathType Container)
        $HasCache = $CacheMarkets -contains $Market
        $Label = if ($KnownMarketplaces.ContainsKey($Market) -or $HasTable) { "KNOWN" } else { "UNKNOWN" }
        $Lines.Add("$Label $Market table=$(Format-Bool $HasTable) source=$(Format-Bool $HasSource) cache=$(Format-Bool $HasCache)")
    }

    $Lines.Add("Enabled plugins / 已启用插件:")
    foreach ($Plugin in Get-PluginTables $Text) {
        if (-not $Plugin.Enabled) { continue }
        $Cache = Join-Path $CodexHome "plugins/cache/$($Plugin.Marketplace)/$($Plugin.Name)"
        $DefaultSource = if ($KnownMarketplaces.ContainsKey($Plugin.Marketplace)) { $KnownMarketplaces[$Plugin.Marketplace] } else { "" }
        $SourceMarket = Get-MarketplaceSource -Text $Text -Name $Plugin.Marketplace -Default $DefaultSource
        $Source = if ($SourceMarket) { Join-Path $SourceMarket "plugins/$($Plugin.Name)" } else { "" }
        $OkMarket = $MarketplaceTables.ContainsKey($Plugin.Marketplace)
        $OkCache = Test-PluginCacheExists $Cache
        $SourceExists = $Source -and (Test-Path -LiteralPath $Source -PathType Container)
        $Status = if ($OkCache) { "OK" } else { "MISSING" }
        $Lines.Add("$Status $($Plugin.Name)@$($Plugin.Marketplace) marketplace=$(Format-Bool $OkMarket) source=$(Format-Bool $SourceExists) cache=$(Format-Bool $OkCache)")
    }

    if ($env:CODEX_PLUGIN_REPAIR_VERBOSE_REPORT -eq "1") {
        $EnabledIds = @{}
        foreach ($Plugin in Get-PluginTables $Text) {
            if ($Plugin.Enabled) { $EnabledIds["$($Plugin.Name)@$($Plugin.Marketplace)"] = $true }
        }
        $Lines.Add("Available but not enabled / 可用但未启用:")
        $Found = 0
        foreach ($Market in $AllMarkets) {
            $DefaultSource = if ($KnownMarketplaces.ContainsKey($Market)) { $KnownMarketplaces[$Market] } else { "" }
            $SourceMarket = Get-MarketplaceSource -Text $Text -Name $Market -Default $DefaultSource
            if (-not ($SourceMarket -and (Test-Path -LiteralPath $SourceMarket -PathType Container))) { continue }
            foreach ($Name in Get-SourcePluginNames $SourceMarket) {
                $PluginId = "$Name@$Market"
                if (-not $EnabledIds.ContainsKey($PluginId)) {
                    $Lines.Add($PluginId)
                    $Found++
                }
            }
        }
        if ($Found -eq 0) { $Lines.Add("none / 无") }
    }
    return $Lines
}

function Write-DiagnosticLog {
    param(
        [string]$Text,
        [hashtable]$KnownMarketplaces,
        [string[]]$Missing
    )

    $Lines = @(
        "Codex Plugin Repair diagnostic log",
        "Codex 插件修复诊断日志",
        "timestamp=$Stamp",
        "platform=$DetectedPlatform",
        "codex_home=$CodexHome",
        "config=$Config",
        "backup=$Backup",
        "missing=$($Missing -join ', ')",
        ""
    )
    $Lines += Get-PluginCoverageReportLines -Text $Text -KnownMarketplaces $KnownMarketplaces
    $Lines | Set-Content -LiteralPath $Log -Encoding UTF8
}

$Text = Get-Content -LiteralPath $Config -Raw
$Text = [regex]::Replace($Text, '(?m)^service_tier\s*=\s*"default"\s*$', 'service_tier = "fast"')

$DetectedPlatform = Get-DetectedPlatform
$SystemName = $DetectedPlatform.ToLowerInvariant()
Write-Host ""
Write-Host "[3/5] 检测平台和修复 marketplace / Detecting platform and repairing marketplaces: $DetectedPlatform"
$BundledSource = Join-Path $CodexHome ".tmp/bundled-marketplaces/openai-bundled"
$CuratedSource = Join-Path $CodexHome ".tmp/plugins"
$PrimaryRuntimeSource = Join-Path $HOME ".cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime"

if ($SystemName -eq "windows") {
    $WindowsBundledSource = Get-WindowsBundledSourceRoot -PackageName $PackageName -SourceOverride $BundledSourceRoot
    Sync-WindowsBundledMarketplace -Source $WindowsBundledSource -Destination $BundledSource | Out-Null
}

$KnownMarketplaces = @{
    "openai-bundled" = $BundledSource
    "openai-curated" = $CuratedSource
    "openai-primary-runtime" = $PrimaryRuntimeSource
}

$Text = Ensure-Marketplace -Text $Text -Name "openai-bundled" -Source $BundledSource
if (Test-Path -LiteralPath (Join-Path $CuratedSource ".agents/plugins/marketplace.json") -PathType Leaf) {
    $Text = Ensure-Marketplace -Text $Text -Name "openai-curated" -Source $CuratedSource
}
if (Test-Path -LiteralPath (Join-Path $PrimaryRuntimeSource ".agents/plugins/marketplace.json") -PathType Leaf) {
    $Text = Ensure-Marketplace -Text $Text -Name "openai-primary-runtime" -Source $PrimaryRuntimeSource
}

if ($SystemName -eq "windows" -or $SystemName -eq "darwin") {
    foreach ($PluginId in @("browser@openai-bundled", "chrome@openai-bundled", "computer-use@openai-bundled")) {
        $Text = Set-PluginEnabled -Text $Text -PluginId $PluginId -Enabled $true
    }
} else {
    Write-Host "检测到平台：$DetectedPlatform。跳过 Desktop bundled 插件自动启用。/ Platform detected: $DetectedPlatform. Skipping Desktop bundled plugin auto-enable."
}

Set-Content -LiteralPath $Config -Value $Text -NoNewline

Write-Host ""
Write-Host "[4/5] 修复已启用插件缓存 / Repairing enabled plugin cache..."
foreach ($Plugin in Get-EnabledPlugins (Get-Content -LiteralPath $Config -Raw)) {
    Copy-Plugin -Marketplace $Plugin.Marketplace -PluginName $Plugin.Name -KnownMarketplaces $KnownMarketplaces | Out-Null
}

if ($SystemName -eq "windows") {
    $ComputerUseCacheBase = Join-Path $CodexHome "plugins/cache/openai-bundled/computer-use"
    $ComputerUseCaches = Get-CachedPluginDirs $ComputerUseCacheBase
    if ($ComputerUseCaches.Count -gt 0) {
        $ComputerUseRoot = $ComputerUseCaches[-1].FullName
        $HelperPath = Join-Path $ComputerUseRoot "node_modules/@oai/sky/bin/windows/codex-computer-use.exe"
        if (Test-Path -LiteralPath $HelperPath -PathType Leaf) {
            $Text = Get-Content -LiteralPath $Config -Raw
            $Text = Set-NotifyHelper -Text $Text -HelperPath $HelperPath
            Set-Content -LiteralPath $Config -Value $Text -NoNewline
            Write-Host "已更新 notify helper 路径 / Updated notify helper path: $HelperPath"
        } else {
            Write-Host "跳过 notify 更新：Computer Use helper 缺失 / Skip notify update: Computer Use helper missing: $HelperPath"
        }
    } else {
        Write-Host "跳过 notify 更新：Computer Use 缓存缺失 / Skip notify update: Computer Use cache missing"
    }
}

$FinalText = Get-Content -LiteralPath $Config -Raw
Write-Host ""
Write-Host "[5/5] 生成插件覆盖报告 / Generating plugin coverage report..."
Write-PluginCoverageReport -Text $FinalText -KnownMarketplaces $KnownMarketplaces
$Markets = @{}
foreach ($Match in [regex]::Matches($FinalText, '(?m)^\[marketplaces\.([^\]]+)\]')) {
    $Markets[$Match.Groups[1].Value] = $true
}

$Missing = @()
foreach ($Plugin in Get-EnabledPlugins $FinalText) {
    $Cache = Join-Path $CodexHome "plugins/cache/$($Plugin.Marketplace)/$($Plugin.Name)"
    $OkMarket = $Markets.ContainsKey($Plugin.Marketplace)
    $OkCache = Test-PluginCacheExists $Cache
    $DefaultSource = if ($KnownMarketplaces.ContainsKey($Plugin.Marketplace)) { $KnownMarketplaces[$Plugin.Marketplace] } else { "" }
    $SourceMarket = Get-MarketplaceSource -Text $FinalText -Name $Plugin.Marketplace -Default $DefaultSource
    $Source = if ($SourceMarket) { Join-Path $SourceMarket "plugins/$($Plugin.Name)" } else { "" }
    $SourceExists = $Source -and (Test-Path -LiteralPath $Source -PathType Container)
    $Status = if ($OkCache) { "OK" } else { "MISSING" }
    if ($Status -ne "OK") {
        $Missing += "$($Plugin.Name)@$($Plugin.Marketplace)"
    }
}

if ($Missing.Count -gt 0) {
    Write-DiagnosticLog -Text $FinalText -KnownMarketplaces $KnownMarketplaces -Missing $Missing
    [Console]::Error.WriteLine("仍有插件缺失 / Still missing: " + ($Missing -join ", "))
    Write-AgentsHelp -LogPath $Log
    exit 2
}

Write-Host ""
if ($SelectedLanguage -eq "en-US") {
    Write-Host "Repair complete."
    Write-Host "Next step:"
    if ($SystemName -eq "windows" -or $SystemName -eq "darwin") {
        Write-Host "- Restart Codex Desktop so it reloads config.toml."
    } elseif ($SystemName -eq "linux") {
        Write-Host "- Start a new Codex CLI session so it reloads config.toml."
    } else {
        Write-Host "- Restart Codex or start a new Codex session so it reloads config.toml."
    }
} else {
    Write-Host "修复完成。"
    Write-Host "后续建议："
    if ($SystemName -eq "windows" -or $SystemName -eq "darwin") {
        Write-Host "- 重启 Codex Desktop，让它重新加载 config.toml。"
    } elseif ($SystemName -eq "linux") {
        Write-Host "- 启动新的 Codex CLI 会话，让它重新加载 config.toml。"
    } else {
        Write-Host "- 重启 Codex 或启动新的 Codex 会话，让它重新加载 config.toml。"
    }
}
