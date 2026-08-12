#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$DotfilesDir = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
    [string]$Remote = 'origin',
    [string]$Branch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $DotfilesDir '.git'))) {
    throw "$DotfilesDir is not a Git checkout"
}

& git -C $DotfilesDir fetch --quiet $Remote $Branch
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }
$head = (& git -C $DotfilesDir rev-parse HEAD).Trim()
$upstream = (& git -C $DotfilesDir rev-parse "$Remote/$Branch").Trim()
if ($head -eq $upstream) {
    & (Join-Path $DotfilesDir 'scripts\sync-agent-config-windows.ps1') -DotfilesDir $DotfilesDir
    exit $LASTEXITCODE
}

& git -C $DotfilesDir merge-base --is-ancestor $head $upstream
if ($LASTEXITCODE -ne 0) {
    throw "local HEAD is not a fast-forward ancestor of $Remote/$Branch; manual reconciliation required"
}

$upstreamChanges = @(& git -C $DotfilesDir diff --name-only $head $upstream)
$localChanges = @(
    & git -C $DotfilesDir diff --name-only
    & git -C $DotfilesDir diff --cached --name-only
    & git -C $DotfilesDir ls-files --others --exclude-standard
) | Sort-Object -Unique
$overlap = @($upstreamChanges | Where-Object { $localChanges -contains $_ })
if ($overlap.Count -gt 0) {
    throw ("upstream changes overlap host-local changes:`n  " + ($overlap -join "`n  "))
}

& git -C $DotfilesDir merge --ff-only --quiet "$Remote/$Branch"
if ($LASTEXITCODE -ne 0) { throw 'git merge --ff-only failed' }
& (Join-Path $DotfilesDir 'scripts\sync-agent-config-windows.ps1') -DotfilesDir $DotfilesDir
if ($LASTEXITCODE -ne 0) { throw 'agent configuration synchronization failed' }
Write-Output ("dotfiles-update-windows: fast-forwarded {0} to {1}" -f $Branch, (& git -C $DotfilesDir rev-parse --short HEAD).Trim())
