#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$DotfilesDir = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$homeDir = $env:USERPROFILE

function Resolve-NpmCommand([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $prefix = (& npm config get prefix).Trim()
    $candidate = Join-Path $prefix ($Name + '.cmd')
    if (Test-Path $candidate) { return $candidate }
    throw "$Name is not installed or is outside PATH"
}

function Resolve-ManagedPython {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\python.exe'),
        (Join-Path $homeDir '.local\share\codex-config-sync-venv\Scripts\python.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    throw 'A managed Python interpreter is required for Codex compatibility sync'
}

# Merge the shared Claude configuration while preserving Windows-only settings.
& (Join-Path $DotfilesDir 'scripts\install-claude-windows.ps1') -DotfilesDir $DotfilesDir

$codexDir = Join-Path $homeDir '.codex'
$agentsDir = Join-Path $homeDir '.agents\skills'
New-Item -ItemType Directory -Force -Path $codexDir, $agentsDir | Out-Null
Copy-Item (Join-Path $DotfilesDir '.codex\AGENTS.md') (Join-Path $codexDir 'AGENTS.md') -Force
Copy-Item (Join-Path $DotfilesDir '.codex\hooks.json') (Join-Path $codexDir 'hooks.json') -Force

# Codex uses ~/.agents/skills. Copy shared Claude skills without deleting
# Windows-only community skills.
$skillSource = Join-Path $homeDir '.claude\skills'
if (Test-Path $skillSource) {
    Get-ChildItem $skillSource -Directory | ForEach-Object {
        $target = Join-Path $agentsDir $_.Name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item (Join-Path $_.FullName '*') $target -Recurse -Force
    }
}

# Apply canonical Ruler configuration to every registered Ruler project.
# Equivalent command: ruler apply --project-root <root> --agents claude,codex
$ruler = Resolve-NpmCommand 'ruler'
$projectsDir = Join-Path $homeDir '.config\claude-rc\projects'
$roots = @()
if (Test-Path $projectsDir) {
    $roots = Get-ChildItem $projectsDir -Directory -Force | ForEach-Object {
        if (Test-Path (Join-Path $_.FullName '.ruler\ruler.toml')) { $_.FullName }
    } | Sort-Object -Unique
}
foreach ($root in $roots) {
    & $ruler apply --project-root $root --agents 'claude,codex' --local-only --no-gitignore --no-backup --no-skills --no-subagents
    if ($LASTEXITCODE -ne 0) { throw "ruler apply failed for $root" }
}

$python = Resolve-ManagedPython
& $python -m pip install --disable-pip-version-check --quiet 'tomlkit==0.13.3'
if ($LASTEXITCODE -ne 0) { throw 'tomlkit provisioning failed' }
& $python (Join-Path $DotfilesDir '.local\libexec\codex-config-sync.py') --compat-only --quiet
if ($LASTEXITCODE -ne 0) { throw 'Codex compatibility synchronization failed' }

Write-Output ("sync-agent-config-windows: synchronized shared configuration; projects=" + $roots.Count)
