Option Explicit

Function Quote(ByVal value)
    Quote = Chr(34) & value & Chr(34)
End Function

Dim fso, shell, scriptDir, dotfilesDir, powerShell, updater, command, exitCode
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
dotfilesDir = fso.GetParentFolderName(scriptDir)
powerShell = fso.BuildPath(shell.ExpandEnvironmentStrings("%SystemRoot%"), "System32\WindowsPowerShell\v1.0\powershell.exe")
updater = fso.BuildPath(scriptDir, "dotfiles-update-windows.ps1")

command = Quote(powerShell) & _
    " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Quote(updater) & _
    " -DotfilesDir " & Quote(dotfilesDir)

' Window style 0 keeps PowerShell fully hidden. Wait=True preserves its exit code.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
