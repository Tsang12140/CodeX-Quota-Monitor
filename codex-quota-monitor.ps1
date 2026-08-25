# 监控 Codex(ChatGPT Plus) 的额度重置：一旦 OpenAI 发放了可用的重置额度，立刻邮件通知。
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
    'checked_at','used_percent','remaining_percent','reset_at','reset_at_time',
    'reset_after_seconds','limit_window_seconds','plan_type','limit_reached',
    'credits_available_count','credits_has_credits','approx_local_messages',
    'approx_cloud_messages','reset_detected','mail_sent','prev_used_percent'
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

# 3. 查询额度使用百分比
$headers = @{ Authorization = "Bearer $accessToken"; 'User-Agent' = 'codex' }
try {
  $data = Invoke-RestMethod -Uri $RateLimitUrl -Headers $headers -Method Get
} catch {
  $code = '(none)'
  if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
  Write-Log "查询额度接口失败 status=$code msg=$($_.Exception.Message)"
  exit 1
}

$pw = $data.rate_limit.primary_window
$curUsed   = [int]$pw.used_percent
$curResetAt= [long]$pw.reset_at
$curResetTime = if ($curResetAt -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($curResetAt).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '未知' }
$curRemaining = 100 - $curUsed

# ---- 仅查看状态 ----
if ($ShowStatus) {
  Write-Host "剩余额度:       $curRemaining%"
  Write-Host "重置时间(预计): $curResetTime"
  $data | ConvertTo-Json -Depth 10
  exit 0
}

Write-Log "当前额度状态: 剩余=$curRemaining% 下次重置=$curResetTime"

# 4. 与上次状态对比，判断是否发生了全量重置
$prev = $null
if (Test-Path $StateFile) {
  try { $prev = Get-Content $StateFile -Raw | ConvertFrom-Json } catch {}
}

$resetDetected = $false
$detail = ""
if ($prev) {
  # 优先读取旧状态中的剩余额度；兼容早期只保存 used_percent 的状态文件。
  $prevRemaining = if ($null -ne $prev.remaining) { [int]$prev.remaining } else { 100 - [int]$prev.used_percent }
  # 判定补满：上次剩余较低(<=50%)，本次明显回升(>=80%)，说明本轮额度已重置。
  if ($prevRemaining -le 50 -and $curRemaining -ge 80) {
    $resetDetected = $true
    $detail = "本轮剩余额度 $prevRemaining% → $curRemaining%（已补满）"
  }
} else {
  Write-Log "首次运行，记录初始状态，暂不发送通知"
}

# 4.1 防重复通知：检测到重置后 6 小时内不重复发邮件（冷却期）
#     重置周期为 7 天，6 小时冷却不可能漏掉下一次真实重置
$cooldownHours = 6
$shouldNotify = $false
if ($resetDetected) {
  $skip = $false
  if ($prev.last_notified_time) {
    try {
      $lastNotify = [DateTimeOffset]::Parse($prev.last_notified_time).LocalDateTime
      $elapsed = (Get-Date) - $lastNotify
      if ($elapsed.TotalHours -lt $cooldownHours) {
        $skip = $true
        Write-Log "距上次通知仅 $([int]$elapsed.TotalMinutes) 分钟，冷却期内跳过重复通知"
      }
    } catch {}
  }
  if (-not $skip) { $shouldNotify = $true }
}

# 5. 保存当前状态
$notifiedTime = if ($shouldNotify) { (Get-Date -Format 'o') } elseif ($prev.last_notified_time) { $prev.last_notified_time } else { '' }
$state = @{
  checked_at          = (Get-Date -Format 'o')
  used_percent        = $curUsed
  remaining           = $curRemaining
  reset_at            = $curResetAt
  reset_time          = $curResetTime
  last_notified_time  = $notifiedTime
  raw                 = $data
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile -Encoding UTF8

# 追加结构化数据到 CSV（每次检查都记，用于画图表）
$prevUsedForCsv = if ($prev) { [int]$prev.used_percent } else { '' }
$csvRow = @{
  checked_at               = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  used_percent             = $curUsed
  remaining_percent        = $curRemaining
  reset_at                 = $curResetAt
  reset_at_time            = $curResetTime
  reset_after_seconds      = $pw.reset_after_seconds
  limit_window_seconds     = $pw.limit_window_seconds
  plan_type                = $data.plan_type
  limit_reached            = $data.rate_limit.limit_reached
  credits_available_count  = $data.rate_limit_reset_credits.available_count
  credits_has_credits      = $data.credits.has_credits
  approx_local_messages    = ($data.credits.approx_local_messages -join '|')
  approx_cloud_messages    = ($data.credits.approx_cloud_messages -join '|')
  reset_detected           = if ($resetDetected) { 1 } else { 0 }
  mail_sent                = if ($shouldNotify) { 1 } else { 0 }
  prev_used_percent        = $prevUsedForCsv
}
Append-DataCsv $csvRow

# 6. 检测到重置则发邮件
if ($shouldNotify) {
  Write-Log "检测到额度重置！$detail"
  $subject = "Codex 额度已补满：剩余 $curRemaining%"
  $body = "你的 Codex(ChatGPT Plus) 本轮额度已重置。`r`n`r`n$detail`r`n`r`n当前剩余: $curRemaining%`r`n下次重置预计: $curResetTime`r`n检查时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n`r`n—— codex-quota-monitor"
  Send-Mail $subject $body
}
