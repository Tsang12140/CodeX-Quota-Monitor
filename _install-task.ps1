# 注册 / 重新注册 Codex 额度监控计划任务（每 10 分钟运行一次，后台隐藏窗口）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File _install-task.ps1
# 卸载：powershell -NoProfile -Command "Unregister-ScheduledTask -TaskName CodexQuotaMonitor -Confirm:`$false"

$taskName = 'CodexQuotaMonitor'
$vbsPath  = Join-Path $PSScriptRoot 'run-hidden.vbs'

# 用 wscript 调 VBS，VBS 内部以 0（隐藏）模式启动 PowerShell，完全不弹窗
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$vbsPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description '监控Codex额度重置并邮件通知（后台隐藏运行）' -Force | Out-Null
Write-Host "计划任务已注册: $taskName （每 10 分钟运行一次，隐藏窗口，1 分钟后首次执行）"
