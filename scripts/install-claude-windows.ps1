#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows equivalent of the Claude Code section of install_environment.sh.

.DESCRIPTION
    Deploys the ~/.claude global configuration from this dotfiles repo onto a
    Windows host. On Windows, creating symlinks requires elevation/Developer
    Mode, so files are COPIED instead of symlinked. Re-run this script after
    `git -C ~/.dot_files pull` to re-sync.

    Linux-specific pieces are adapted to working Windows equivalents:
      * The hook scripts and statusline are bash (#!/bin/bash). They run fine
        under Git Bash, but native Windows cannot exec a bare "*.sh" path, so
        settings.json invokes them as `bash <msys-path>` (the same pattern the
        host already uses for its statusline).
      * jq (required by statusline.sh and the hooks) is installed via winget if
        missing, and made reachable from Git Bash.
      * settings.json / settings.local.json are deep-merged so host-specific
        keys (autoUpdatesChannel, remote.defaultEnvironmentId, etc.) survive.

.PARAMETER DotfilesDir
    Path to the dotfiles repo. Defaults to the repo this script lives in.
#>
[CmdletBinding()]
param(
    [string]$DotfilesDir = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ClaudeSrc  = Join-Path $DotfilesDir '.claude'
$ClaudeDest = Join-Path $env:USERPROFILE '.claude'
$BackupDir  = Join-Path $env:USERPROFILE ('.dotfiles-backup\{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

if (-not (Test-Path $ClaudeSrc)) { throw "Cannot find $ClaudeSrc - is -DotfilesDir correct?" }

# Locate Git Bash (Claude Code runs hooks/statusline under Git Bash on Windows).
$GitBash = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $GitBash) { Write-Warning "Git Bash not found; hooks/statusline need Git for Windows (git-scm.com/downloads/win)." }

function Convert-ToMsysPath([string]$WinPath) {
    # C:\Users\me\.claude -> /c/Users/me/.claude  (the form Git Bash understands)
    $p = $WinPath -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)$') { return '/' + $Matches[1].ToLowerInvariant() + $Matches[2] }
    return $p
}

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path -PathType Leaf) {
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        $flat = ($Path.Substring($env:USERPROFILE.Length).TrimStart('\','/') -replace '[\\/]', '__')
        Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupDir $flat) -Force
        Write-Host "  backed up: $Path"
    }
}

function Copy-File([string]$Src, [string]$Dest) {
    if (-not (Test-Path $Src)) { Write-Warning "source not found: $Src"; return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Backup-IfExists $Dest
    Copy-Item -LiteralPath $Src -Destination $Dest -Force
}

Write-Host "Deploying Claude config: $ClaudeSrc -> $ClaudeDest"
New-Item -ItemType Directory -Force -Path $ClaudeDest, "$ClaudeDest\rules", "$ClaudeDest\agents", "$ClaudeDest\hooks", "$ClaudeDest\skills" | Out-Null

# ── jq (required by statusline.sh and hooks) ─────────────────────
# Check via the located Git Bash, NOT bare `bash` (which resolves to WSL on Windows).
function Test-JqInGitBash { if ($GitBash) { (& $GitBash -lc 'command -v jq' 2>$null) } }
$jqInBash = Test-JqInGitBash
if (-not $jqInBash) {
    Write-Host "jq not found on Git Bash PATH; installing via winget..."
    winget install --id jqlang.jq --accept-source-agreements --accept-package-agreements --silent | Out-Null
    $jqExe = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\jq.exe'
    if (Test-Path $jqExe) {
        # Make jq reachable from Git Bash regardless of PATH-refresh timing:
        # ~/bin is on the default Git Bash PATH.
        New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE 'bin') | Out-Null
        Copy-Item $jqExe (Join-Path $env:USERPROFILE 'bin\jq.exe') -Force
    }
    if (Test-JqInGitBash) { Write-Host "  jq ready" }
    else { Write-Warning "jq still not reachable from Git Bash; statusline/hooks may not work." }
} else {
    Write-Host "jq already available to Git Bash: $jqInBash"
}

# ── File-based config (straight copy) ────────────────────────────
Copy-File "$ClaudeSrc\global-CLAUDE.md"           "$ClaudeDest\CLAUDE.md"
Copy-File "$ClaudeSrc\global-learned-insights.md" "$ClaudeDest\global-learned-insights.md"
Copy-File "$ClaudeSrc\statusline.sh"              "$ClaudeDest\statusline.sh"
Copy-File "$ClaudeSrc\hooks.json"                 "$ClaudeDest\hooks.json"

Get-ChildItem "$ClaudeSrc\hooks" -File -ErrorAction SilentlyContinue | ForEach-Object { Copy-File $_.FullName "$ClaudeDest\hooks\$($_.Name)" }
Get-ChildItem "$ClaudeSrc\rules" -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { Copy-File $_.FullName "$ClaudeDest\rules\$($_.Name)" }
Get-ChildItem "$ClaudeSrc\agents" -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { Copy-File $_.FullName "$ClaudeDest\agents\$($_.Name)" }
Get-ChildItem $ClaudeSrc -Filter 'hookify.*.local.md' -ErrorAction SilentlyContinue | ForEach-Object { Copy-File $_.FullName "$ClaudeDest\$($_.Name)" }

# Skills: merge the repo's tree in (non-destructive to any local-only skills).
if (Test-Path "$ClaudeSrc\skills") {
    Copy-Item "$ClaudeSrc\skills\*" "$ClaudeDest\skills\" -Recurse -Force
    Write-Host "  copied skills/"
}

# ── settings.json (smart merge, Windows-adapted) ─────────────────
$msysHome = Convert-ToMsysPath $env:USERPROFILE

function ConvertTo-BashHookCommand([string]$cmd) {
    # Bare "$HOME/.claude/.../x.sh" or "~/.claude/.../x.sh" -> "bash /c/Users/.../x.sh".
    if ($cmd -match '^\s*(\$HOME|~)[\\/].*\.sh\s*$') {
        $rel = $cmd.Trim() -replace '^\s*(\$HOME|~)', ''
        return 'bash ' + $msysHome + ($rel -replace '\\', '/')
    }
    return $cmd
}

$settings = Get-Content "$ClaudeSrc\settings.json" -Raw | ConvertFrom-Json

# statusline -> invoke the bash script via bash with an absolute MSYS path
if ($settings.PSObject.Properties.Name -contains 'statusLine') {
    $settings.statusLine.command = 'bash ' + (Convert-ToMsysPath "$ClaudeDest\statusline.sh")
}

# hooks -> rewrite bare .sh script paths to `bash <msys-path>`
if ($settings.PSObject.Properties.Name -contains 'hooks') {
    foreach ($evt in $settings.hooks.PSObject.Properties) {
        foreach ($group in $evt.Value) {
            if ($group.PSObject.Properties.Name -contains 'hooks') {
                foreach ($h in $group.hooks) {
                    if ($h.PSObject.Properties.Name -contains 'command') {
                        $h.command = ConvertTo-BashHookCommand $h.command
                    }
                }
            }
        }
    }
}

# Pin Git Bash so Claude Code locates it regardless of PATH (WSL bash would break /c/ paths).
if ($GitBash) {
    if ($settings.PSObject.Properties.Name -notcontains 'env') {
        $settings | Add-Member -NotePropertyName 'env' -NotePropertyValue ([pscustomobject]@{})
    }
    if ($settings.env.PSObject.Properties.Name -contains 'CLAUDE_CODE_GIT_BASH_PATH') {
        $settings.env.CLAUDE_CODE_GIT_BASH_PATH = $GitBash
    } else {
        $settings.env | Add-Member -NotePropertyName 'CLAUDE_CODE_GIT_BASH_PATH' -NotePropertyValue $GitBash
    }
}

# Preserve host-only top-level keys (e.g. autoUpdatesChannel) from any existing file.
if (Test-Path "$ClaudeDest\settings.json") {
    $existing = Get-Content "$ClaudeDest\settings.json" -Raw | ConvertFrom-Json
    foreach ($p in $existing.PSObject.Properties) {
        if ($settings.PSObject.Properties.Name -notcontains $p.Name) {
            $settings | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
        }
    }
}

Backup-IfExists "$ClaudeDest\settings.json"
$settings | ConvertTo-Json -Depth 100 | Set-Content "$ClaudeDest\settings.json" -Encoding utf8
Write-Host "  wrote settings.json (merged)"

# ── settings.local.json (preserve host-specific keys, union perms) ─
$repoLocal = Get-Content "$ClaudeSrc\settings.local.json" -Raw | ConvertFrom-Json
$local = if (Test-Path "$ClaudeDest\settings.local.json") {
    Get-Content "$ClaudeDest\settings.local.json" -Raw | ConvertFrom-Json
} else { [pscustomobject]@{} }

# Union permissions.allow from repo + host
$allow = @()
foreach ($o in @($local, $repoLocal)) {
    if ($o.PSObject.Properties.Name -contains 'permissions' -and $o.permissions.PSObject.Properties.Name -contains 'allow') {
        $allow += $o.permissions.allow
    }
}
$allow = $allow | Select-Object -Unique
if ($local.PSObject.Properties.Name -notcontains 'permissions') {
    $local | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([pscustomobject]@{})
}
if ($local.permissions.PSObject.Properties.Name -notcontains 'allow') {
    $local.permissions | Add-Member -NotePropertyName 'allow' -NotePropertyValue @()
}
$local.permissions.allow = $allow

Backup-IfExists "$ClaudeDest\settings.local.json"
$local | ConvertTo-Json -Depth 100 | Set-Content "$ClaudeDest\settings.local.json" -Encoding utf8
Write-Host "  wrote settings.local.json (merged, host keys preserved)"

Write-Host ""
Write-Host "Done. Restart Claude Code to pick up the new config." -ForegroundColor Green
if (Test-Path $BackupDir) { Write-Host "Backups of replaced files: $BackupDir" }
