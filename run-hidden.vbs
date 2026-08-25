' 隐藏窗口启动同目录的 PowerShell 脚本，避免计划任务运行时弹出黑框
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptDir & "\codex-quota-monitor.ps1""", 0, False
