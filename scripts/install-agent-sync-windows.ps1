#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$DotfilesDir = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'DotfilesAgentSync'
$powerShell = (Get-Command powershell.exe).Source
$script = Join-Path $DotfilesDir 'scripts\dotfiles-update-windows.ps1'
$arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -DotfilesDir `"$DotfilesDir`""
$action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $currentIdentity -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Fast-forward dotfiles and synchronize Claude/Codex configuration without restarting active sessions.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output "install-agent-sync-windows: registered and started $taskName"
