param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }),
    [string]$PackageName = "OpenAI.Codex",
    [string]$BundledSourceRoot = $(if ($env:CODEX_PLUGIN_REPAIR_BUNDLED_SOURCE_ROOT) { $env:CODEX_PLUGIN_REPAIR_BUNDLED_SOURCE_ROOT } else { "" })
)

$ErrorActionPreference = "Stop"

$Config = Join-Path $CodexHome "config.toml"
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
$Backup = "$Config.bak-plugin-repair-$Stamp"

if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
    Write-Error "Missing Codex config: $Config"
    exit 1
}

Copy-Item -LiteralPath $Config -Destination $Backup -Force
Write-Host "Backed up config to: $Backup"

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
        Write-Host "Windows bundled source override missing: $SourceOverride"
        return $null
    }

    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Host "Get-AppxPackage is unavailable; keeping existing bundled marketplace source."
        return $null
    }

    $Package = Get-AppxPackage -Name $PackageName | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $Package) {
        Write-Host "Could not find AppX package: $PackageName"
        return $null
    }

    $Source = Join-Path $Package.InstallLocation "app/resources/plugins/openai-bundled"
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Host "Could not find bundled plugin source: $Source"
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
        Move-Item -LiteralPath $Destination -Destination $BackupPath -Force
        Write-Host "Backed up bundled marketplace to: $BackupPath"
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
    Write-Host "Synced Windows bundled marketplace: $Source -> $Destination"
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
    $Timestamp = if ($env:CODEX_PLUGIN_REPAIR_TIMESTAMP) { $env:CODEX_PLUGIN_REPAIR_TIMESTAMP } else { "2026-06-04T00:00:00Z" }
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
    Write-Host "Updated latest link: $Latest -> $Target"
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
            Write-Host "Missing cache file for ${PluginName}: $MissingFile"
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
        Write-Host "Skip ${PluginName}@${Marketplace}: marketplace source is unknown"
        return $false
    }

    $Source = Join-Path $SourceMarket "plugins/$PluginName"
    $DestBase = Join-Path $CodexHome "plugins/cache/$Marketplace/$PluginName"
    $Existing = Get-CachedPluginDirs $DestBase

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        if ($Existing.Count -gt 0) {
            Write-Host "Cache already valid for ${PluginName}@${Marketplace}: $($Existing[-1].FullName)"
            if ($Marketplace -eq "openai-bundled") {
                Update-LatestLink -Base $DestBase -Target $Existing[-1].FullName
            }
            return $true
        }
        Write-Host "Skip ${PluginName}@${Marketplace}: marketplace plugin source missing: $Source"
        return $false
    }

    $Version = Get-PluginVersion $Source
    if (-not $Version) {
        if ($Existing.Count -gt 0) {
            Write-Host "Cache already valid for ${PluginName}@${Marketplace}: $($Existing[-1].FullName)"
            if ($Marketplace -eq "openai-bundled") {
                Update-LatestLink -Base $DestBase -Target $Existing[-1].FullName
            }
            return $true
        }
        Write-Host "Skip ${PluginName}@${Marketplace}: missing version in $Source/.codex-plugin/plugin.json"
        return $false
    }

    $Dest = Join-Path $DestBase $Version
    New-Item -ItemType Directory -Path $DestBase -Force | Out-Null
    if (Test-Path -LiteralPath $Dest -PathType Container) {
        if (Test-PluginCacheReady -PluginName $PluginName -PluginRoot $Dest -PlatformName $SystemName) {
            Write-Host "Cache exists for ${PluginName}@${Marketplace}: $Dest"
        } else {
            $BackupDest = "$Dest.bak-plugin-repair-$Stamp"
            Move-Item -LiteralPath $Dest -Destination $BackupDest -Force
            Write-Host "Backed up incomplete cache for ${PluginName}@${Marketplace}: $BackupDest"
            Copy-Item -LiteralPath $Source -Destination $Dest -Recurse
            Write-Host "Rebuilt ${PluginName}@${Marketplace} -> $Dest"
        }
    } else {
        Copy-Item -LiteralPath $Source -Destination $Dest -Recurse
        Write-Host "Copied ${PluginName}@${Marketplace} -> $Dest"
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

$Text = Get-Content -LiteralPath $Config -Raw
$Text = [regex]::Replace($Text, '(?m)^service_tier\s*=\s*"default"\s*$', 'service_tier = "fast"')

$DetectedPlatform = Get-DetectedPlatform
$SystemName = $DetectedPlatform.ToLowerInvariant()
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
    Write-Host "Platform detected: $DetectedPlatform. Skipping Desktop bundled plugin auto-enable."
}

Set-Content -LiteralPath $Config -Value $Text -NoNewline

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
            Write-Host "Updated notify helper path: $HelperPath"
        } else {
            Write-Host "Skip notify update: Computer Use helper missing: $HelperPath"
        }
    } else {
        Write-Host "Skip notify update: Computer Use cache missing"
    }
}

Write-Host ""
Write-Host "Enabled plugin consistency:"
$FinalText = Get-Content -LiteralPath $Config -Raw
$Markets = @{}
foreach ($Match in [regex]::Matches($FinalText, '(?m)^\[marketplaces\.([^\]]+)\]')) {
    $Markets[$Match.Groups[1].Value] = $true
}

$Missing = @()
foreach ($Plugin in Get-EnabledPlugins $FinalText) {
    $Cache = Join-Path $CodexHome "plugins/cache/$($Plugin.Marketplace)/$($Plugin.Name)"
    $OkMarket = $Markets.ContainsKey($Plugin.Marketplace)
    $OkCache = Test-Path -LiteralPath $Cache -PathType Container
    $DefaultSource = if ($KnownMarketplaces.ContainsKey($Plugin.Marketplace)) { $KnownMarketplaces[$Plugin.Marketplace] } else { "" }
    $SourceMarket = Get-MarketplaceSource -Text $FinalText -Name $Plugin.Marketplace -Default $DefaultSource
    $Source = if ($SourceMarket) { Join-Path $SourceMarket "plugins/$($Plugin.Name)" } else { "" }
    $SourceExists = $Source -and (Test-Path -LiteralPath $Source -PathType Container)
    $Status = if ($OkMarket -and $OkCache) { "OK" } else { "MISSING" }
    Write-Host "$Status $($Plugin.Name)@$($Plugin.Marketplace) marketplace=$OkMarket cache=$OkCache source=$SourceExists"
    if ($Status -ne "OK") {
        $Missing += "$($Plugin.Name)@$($Plugin.Marketplace)"
    }
}

if ($Missing.Count -gt 0) {
    Write-Error ("Still missing: " + ($Missing -join ", "))
    exit 2
}

Write-Host ""
Write-Host "Repair complete."
if ($SystemName -eq "windows" -or $SystemName -eq "darwin") {
    Write-Host "If Codex Desktop is open, restart it once so it reloads config.toml."
} elseif ($SystemName -eq "linux") {
    Write-Host "Start a new Codex CLI session so it reloads config.toml."
} else {
    Write-Host "Restart Codex or start a new Codex session so it reloads config.toml."
}
