# 监控 Codex(ChatGPT Plus) 的额度重置：一旦 OpenAI 发放了可用的重置额度，立刻邮件通知。
# 注意：5 小时 primary_window 的正常恢复只记录状态；仅 7 天 secondary_window 的提前回补会发邮件。
# 用法：
#   正常监控：powershell -NoProfile -ExecutionPolicy Bypass -File codex-quota-monitor.ps1
#   测试邮件：powershell -NoProfile -ExecutionPolicy Bypass -File codex-quota-monitor.ps1 -TestMail
#   查看当前状态：powershell -NoProfile -ExecutionPolicy Bypass -File codex-quota-monitor.ps1 -ShowStatus
param(
  [switch]$TestMail,
  [switch]$ShowStatus
)

$configPath = Join-Path $PSScriptRoot 'config.ps1'
if (-not (Test-Path -LiteralPath $configPath)) {
  Write-Error "找不到配置文件：$configPath。请先复制 config.example.ps1 为 config.ps1，再填写邮箱配置。"
  exit 1
}
. $configPath

function Write-Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

# 把一次检查的结构化数据追加到 CSV（用于日后画图表）。表头自动创建。
function Append-DataCsv([hashtable]$row) {
  $fields = @(
    'checked_at',
    'primary_remaining_percent','primary_reset_at','primary_reset_at_time','primary_window_seconds',
    'secondary_remaining_percent','secondary_reset_at','secondary_reset_at_time','secondary_window_seconds',
    'reset_event_type','mail_sent','plan_type','limit_reached'
  )
  $newFile = -not (Test-Path $CsvFile)
  $sb = New-Object System.Text.StringBuilder
  if ($newFile) { [void]$sb.AppendLine(($fields -join ',')) }
  $vals = foreach ($f in $fields) {
    $v = $row[$f]
    if ($null -eq $v) { '' } else { '"' + ($v -replace '"','""') + '"' }
  }
  [void]$sb.AppendLine(($vals -join ','))
  Add-Content -Path $CsvFile -Value $sb.ToString() -Encoding UTF8
}

function Decode-JwtPayload([string]$jwt) {
  $parts = $jwt.Split('.')
  if ($parts.Length -lt 2) { return $null }
  $p = $parts[1]
  switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
  $p = $p.Replace('-', '+').Replace('_', '/')
  [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
}

function Format-ResetAt([long]$unixSeconds) {
  if ($unixSeconds -le 0) { return '未知' }
  return [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
}

function Format-Duration([long]$seconds) {
  $seconds = [Math]::Max(0, $seconds)
  if ($seconds -ge 86400) {
    return "{0}天{1}小时" -f [Math]::Floor($seconds / 86400), [Math]::Floor(($seconds % 86400) / 3600)
  }
  if ($seconds -ge 3600) { return "{0}小时" -f [Math]::Floor($seconds / 3600) }
  return "{0}分钟" -f [Math]::Floor($seconds / 60)
}

function Send-Mail([string]$subject, [string]$body) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $msg = New-Object -ComObject CDO.Message
    $cfg = $msg.Configuration
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/sendusing') = 2
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/smtpserver') = $SmtpHost
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/smtpserverport') = $SmtpPort
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/smtpusessl') = $true
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/smtpauthenticate') = 1
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/sendusername') = $SmtpUser
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/sendpassword') = $SmtpPass
    $cfg.Fields.Item('http://schemas.microsoft.com/cdo/configuration/sendcharset') = 'utf-8'
    $cfg.Fields.Update()
    $msg.From = $MailFrom
    $msg.To = $MailTo
    $msg.Subject = $subject
    $msg.TextBody = $body
    $msg.Send()
    Write-Log "邮件已发送: $subject"
    return $true
  } catch {
    Write-Log "邮件发送失败: $($_.Exception.Message)"
    return $false
  }
}

# ---- 测试邮件 ----
if ($TestMail) {
  Write-Log "测试邮件发送中..."
  $ok = Send-Mail "[Codex额度监控] 测试邮件" "这是一封来自 codex-quota-monitor 的测试邮件。`r`n收到说明 SMTP 配置正常。`r`n时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  if ($ok) { Write-Host "OK：测试邮件已发送到 $MailTo" } else { Write-Host "失败：请检查 config.ps1 里的授权码 / 端口" }
  exit 0
}

# 1. 读取 auth.json
if (-not (Test-Path $AuthJsonPath)) { Write-Log "找不到 auth.json: $AuthJsonPath"; exit 1 }
$auth = Get-Content $AuthJsonPath -Raw | ConvertFrom-Json
$accessToken = $auth.tokens.access_token
$refreshToken = $auth.tokens.refresh_token

# 2. 检查 token 是否过期，过期则用 refresh_token 刷新并写回 auth.json
$needRefresh = $true
try {
  $payload = Decode-JwtPayload $accessToken
  if ($payload.exp) {
    $exp = [DateTimeOffset]::FromUnixTimeSeconds([long]$payload.exp).UtcDateTime
    if ((Get-Date).ToUniversalTime().AddSeconds(60) -lt $exp) { $needRefresh = $false }
  }
} catch { Write-Log "解析 access_token 失败(将尝试刷新): $($_.Exception.Message)" }

if ($needRefresh -and $refreshToken) {
  Write-Log "access_token 已过期，尝试刷新..."
  try {
    $body = @{
      grant_type    = 'refresh_token'
      client_id     = $ClientId
      refresh_token = $refreshToken
      scope         = 'openid profile email offline_access api.connectors.read api.connectors.invoke'
    }
    $resp = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
    $auth.tokens.access_token  = $resp.access_token
    if ($resp.refresh_token) { $auth.tokens.refresh_token = $resp.refresh_token }
    if ($resp.id_token)      { $auth.tokens.id_token = $resp.id_token }
    $auth.last_refresh = (Get-Date -Format 'o')
    $auth | ConvertTo-Json -Depth 20 | Set-Content -Path $AuthJsonPath -Encoding UTF8
    $accessToken = $resp.access_token
    Write-Log "token 刷新成功"
  } catch {
    Write-Log "token 刷新失败: $($_.Exception.Message)（请打开一次 Codex 让它刷新登录）"
    exit 1
  }
}

# 3. 查询两个额度窗口。primary 是短期（目前约 5 小时）窗口，secondary 是约 7 天的总额度窗口。
$headers = @{ Authorization = "Bearer $accessToken"; 'User-Agent' = 'codex' }
try {
  $data = Invoke-RestMethod -Uri $RateLimitUrl -Headers $headers -Method Get
} catch {
  $code = '(none)'
  if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
  Write-Log "查询额度接口失败 status=$code msg=$($_.Exception.Message)"
  exit 1
}

$primaryWindow = $data.rate_limit.primary_window
$secondaryWindow = $data.rate_limit.secondary_window

$primaryUsed = [int]$primaryWindow.used_percent
$primaryRemaining = 100 - $primaryUsed
$primaryResetAt = [long]$primaryWindow.reset_at
$primaryResetTime = Format-ResetAt $primaryResetAt
$primaryWindowSeconds = [long]$primaryWindow.limit_window_seconds

$secondaryAvailable = $null -ne $secondaryWindow
$secondaryUsed = $null
$secondaryRemaining = $null
$secondaryResetAt = 0
$secondaryResetTime = '未提供'
$secondaryWindowSeconds = 0
if ($secondaryAvailable) {
  $secondaryUsed = [int]$secondaryWindow.used_percent
  $secondaryRemaining = 100 - $secondaryUsed
  $secondaryResetAt = [long]$secondaryWindow.reset_at
  $secondaryResetTime = Format-ResetAt $secondaryResetAt
  $secondaryWindowSeconds = [long]$secondaryWindow.limit_window_seconds
}

# ---- 仅查看状态 ----
if ($ShowStatus) {
  Write-Host "短期窗口（约 $(Format-Duration $primaryWindowSeconds)）剩余: $primaryRemaining%"
  Write-Host "短期窗口下次重置: $primaryResetTime"
  if ($secondaryAvailable) {
    Write-Host "7 天总额度剩余: $secondaryRemaining%"
    Write-Host "7 天总额度预计重置: $secondaryResetTime"
  } else {
    Write-Host "7 天总额度: 接口暂未提供，监控不会发送重置邮件"
  }
  exit 0
}

if ($secondaryAvailable) {
  Write-Log "当前额度状态: 5小时剩余=$primaryRemaining%（$primaryResetTime 重置）；7天总额度剩余=$secondaryRemaining%（预计 $secondaryResetTime 重置）"
} else {
  Write-Log "当前额度状态: 5小时剩余=$primaryRemaining%（$primaryResetTime 重置）；未提供7天总额度窗口，已跳过重置提醒判断"
}

# 4. 只以 secondary_window（7 天总额度）判断重置。primary_window 的 5 小时正常恢复绝不发邮件。
$prev = $null
if (Test-Path $StateFile) {
  try { $prev = Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
}

$resetEventType = 'none'
$detail = ''
$shouldNotify = $false

# 允许接口时间、计划任务 10 分钟间隔和临时网络失败造成的误差。实际检查晚于预计时间，永远算按期。
$naturalResetEarlyToleranceMinutes = if ($null -ne $NaturalResetEarlyToleranceMinutes) { [int]$NaturalResetEarlyToleranceMinutes } else { 90 }
$refillMinimumPercent = if ($null -ne $RefillMinimumPercent) { [int]$RefillMinimumPercent } else { 15 }
$refillStartRemainingPercent = if ($null -ne $RefillStartRemainingPercent) { [int]$RefillStartRemainingPercent } else { 85 }
$notificationCooldownHours = if ($null -ne $EarlyResetNotificationCooldownHours) { [int]$EarlyResetNotificationCooldownHours } else { 6 }

if ($secondaryAvailable -and $prev -and $prev.secondary) {
  $prevSecondaryRemaining = [int]$prev.secondary.remaining_percent
  $prevSecondaryResetAt = [long]$prev.secondary.reset_at
  $refillAmount = $secondaryRemaining - $prevSecondaryRemaining

  # 只要总额度有明显回补就识别；不要求恰好 100%，避免 10 分钟检查间隔漏掉重置。
  if ($prevSecondaryRemaining -le $refillStartRemainingPercent -and $refillAmount -ge $refillMinimumPercent) {
    $nowUnix = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    $expectedResetTime = Format-ResetAt $prevSecondaryResetAt
    if ($prevSecondaryResetAt -gt 0 -and $nowUnix -lt ($prevSecondaryResetAt - $naturalResetEarlyToleranceMinutes * 60)) {
      $resetEventType = 'early'
      $leadTime = Format-Duration ($prevSecondaryResetAt - $nowUnix)
      $detail = "7天总额度提前回补：剩余 $prevSecondaryRemaining% → $secondaryRemaining%（原预计 $expectedResetTime 重置，提前约 $leadTime）"
    } elseif ($prevSecondaryResetAt -gt 0) {
      $resetEventType = 'scheduled'
      $detail = "7天总额度按期重置：剩余 $prevSecondaryRemaining% → $secondaryRemaining%（原预计 $expectedResetTime）"
    } else {
      $resetEventType = 'unclassified'
      $detail = "7天总额度出现回补：剩余 $prevSecondaryRemaining% → $secondaryRemaining%，但缺少上一轮预计时间，未发送邮件"
    }
  }
} elseif ($secondaryAvailable) {
  Write-Log "7天总额度监控首次运行（或已从旧版升级），仅记录基线，不发送邮件"
}

# 只有提前回补才通知。按期重置只记日志，5 小时窗口的恢复不会走到这里。
if ($resetEventType -eq 'early') {
  $skip = $false
  if ($prev.last_early_notified_time) {
    try {
      $lastNotify = [DateTimeOffset]::Parse($prev.last_early_notified_time).LocalDateTime
      $elapsed = (Get-Date) - $lastNotify
      if ($elapsed.TotalHours -lt $notificationCooldownHours) {
        $skip = $true
        Write-Log "距上次提前重置提醒仅 $([int]$elapsed.TotalMinutes) 分钟，冷却期内跳过重复邮件"
      }
    } catch {}
  }
  if (-not $skip) { $shouldNotify = $true }
}

if ($resetEventType -eq 'scheduled') { Write-Log $detail }
if ($resetEventType -eq 'unclassified') { Write-Log $detail }

# 5. 保存当前状态（状态文件 v2；第一次升级只建立 7 天窗口基线）。
$lastEarlyNotifiedTime = if ($shouldNotify) { (Get-Date -Format 'o') } elseif ($prev -and $prev.last_early_notified_time) { $prev.last_early_notified_time } else { '' }
$lastScheduledResetTime = if ($resetEventType -eq 'scheduled') { (Get-Date -Format 'o') } elseif ($prev -and $prev.last_scheduled_reset_time) { $prev.last_scheduled_reset_time } else { '' }
$state = @{
  schema_version                = 2
  checked_at                    = (Get-Date -Format 'o')
  primary                       = @{
    remaining_percent = $primaryRemaining
    reset_at          = $primaryResetAt
    reset_time        = $primaryResetTime
    window_seconds    = $primaryWindowSeconds
  }
  secondary                     = if ($secondaryAvailable) { @{
    remaining_percent = $secondaryRemaining
    reset_at          = $secondaryResetAt
    reset_time        = $secondaryResetTime
    window_seconds    = $secondaryWindowSeconds
  } } else { $null }
  last_early_notified_time      = $lastEarlyNotifiedTime
  last_scheduled_reset_time     = $lastScheduledResetTime
  last_reset_event_type         = $resetEventType
  raw                           = $data
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile -Encoding UTF8

# 追加结构化数据到 CSV（v2 单独保存，保留旧版 monitor_data.csv 历史）。
$csvRow = @{
  checked_at                   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  primary_remaining_percent    = $primaryRemaining
  primary_reset_at             = $primaryResetAt
  primary_reset_at_time        = $primaryResetTime
  primary_window_seconds       = $primaryWindowSeconds
  secondary_remaining_percent  = $secondaryRemaining
  secondary_reset_at           = $secondaryResetAt
  secondary_reset_at_time      = $secondaryResetTime
  secondary_window_seconds     = $secondaryWindowSeconds
  reset_event_type             = $resetEventType
  mail_sent                    = if ($shouldNotify) { 1 } else { 0 }
  plan_type                    = $data.plan_type
  limit_reached                = $data.rate_limit.limit_reached
}
Append-DataCsv $csvRow

# 6. 仅提前重置才发邮件。
if ($shouldNotify) {
  Write-Log "检测到7天总额度提前重置！$detail"
  $subject = "Codex 7天总额度提前重置：剩余 $secondaryRemaining%"
  $body = "这是提前重置提醒，不是 5 小时窗口的正常恢复。`r`n`r`n$detail`r`n`r`n当前7天总额度剩余: $secondaryRemaining%`r`n下一次预计重置: $secondaryResetTime`r`n检查时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n—— codex-quota-monitor"
  Send-Mail $subject $body
}
