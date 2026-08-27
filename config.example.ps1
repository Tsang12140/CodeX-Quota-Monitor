# CodeX Quota Monitor 配置示例
#
# 使用方法：将本文件复制为 config.ps1，然后填写 SMTP 信息。
# config.ps1 被 .gitignore 排除，绝不要把真实授权码提交到 GitHub。

# ===== 邮件配置 =====
# QQ 邮箱：网页版 QQ 邮箱 → 设置 → 账户 → 开启「IMAP/SMTP 服务」→ 生成授权码。
# SmtpPass 应填写「授权码」，不是邮箱登录密码。
$SmtpHost = 'smtp.qq.com'
$SmtpPort = 465
$SmtpUser = 'your-sender@example.com'
$SmtpPass = 'replace-with-your-smtp-authorization-code'
$MailFrom = $SmtpUser
$MailTo   = 'your-notification@example.com'

# ===== Codex / OpenAI 配置 =====
# 保持默认即可；使用前请先在本机 Codex 中完成登录。
$AuthJsonPath = Join-Path $env:USERPROFILE '.codex\auth.json'
$ClientId     = 'app_EMoamEEZ73f0CkXaXp7hrann'
$RateLimitUrl = 'https://chatgpt.com/backend-api/wham/usage'
$TokenUrl     = 'https://auth.openai.com/oauth/token'

# ===== 本地运行文件 =====
# 状态、日志和 CSV 都只会写在项目目录中，且已被 .gitignore 排除。
$ScriptDir = $PSScriptRoot
$StateFile = Join-Path $ScriptDir 'state.json'
$LogFile   = Join-Path $ScriptDir 'monitor.log'
$CsvFile   = Join-Path $ScriptDir 'monitor_data_v2.csv'

# ===== 提前重置识别规则 =====
# 按期重置允许最多提前 90 分钟，以容纳接口和每 10 分钟计划任务的时间误差；
# 真正早于这个宽限期的 7 天总额度回补才会邮件通知。
$NaturalResetEarlyToleranceMinutes = 90
# 上一次至少使用了 15%，本次总额度至少回补 15 个百分点，才视为一次重置。
$RefillMinimumPercent = 15
$RefillStartRemainingPercent = 85
$EarlyResetNotificationCooldownHours = 6
