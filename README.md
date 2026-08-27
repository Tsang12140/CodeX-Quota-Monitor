# CodeX Quota Monitor

一个运行在 Windows 上的轻量脚本：定时检查本机 Codex / ChatGPT Plus
的两个额度窗口，专门在 **7 天总额度提前回补** 时发送邮件提醒。

通知和日志都按**剩余额度**表达。例如：`7天总额度提前回补：剩余 1% → 100%`，
而不是难理解的“已用 99% → 0%”。5 小时窗口用完后的正常恢复不会触发邮件。

> 本项目读取 Codex 本机登录状态并调用当前客户端使用的额度接口。该接口并非
> 面向第三方开发者的稳定公开 API，字段或可用性未来可能变化。

## 功能

- 分开显示短期（通常 5 小时）窗口与 7 天总额度窗口的剩余额度和重置时间；
- **5 小时窗口恢复：仅记录，不发邮件**；
- 7 天总额度明显回补时，按上一轮预计重置时间区分：
  - 在预计时间前超过 90 分钟：判定为**提前重置**并发邮件；
  - 在预计时间前 90 分钟内或之后：判定为**按期重置**，只记日志，不打扰；
- 回补幅度至少 15 个百分点才判定为重置，不要求恰好 100%，避免 10 分钟检查间隔漏报；
- 提前重置提醒后的 6 小时内防止重复通知；
- 支持通过 Windows 计划任务每 10 分钟后台运行；
- 将本地状态、日志和 CSV 数据与公开代码分离。

## 使用前准备

1. Windows PowerShell 5.1 或更高版本；
2. 已在本机 Codex 中登录，默认登录文件位于 `~\.codex\auth.json`；
3. 一个能通过 SMTP 发信的邮箱。QQ 邮箱需要在网页版邮箱设置中开启
   `IMAP/SMTP` 服务并生成**授权码**。

## 安装与配置

克隆仓库后，在项目目录执行：

```powershell
Copy-Item config.example.ps1 config.ps1
```

然后打开 `config.ps1`，填写这几项：

| 配置项 | 填什么 |
| --- | --- |
| `$SmtpHost` | SMTP 地址，例如 QQ 邮箱为 `smtp.qq.com` |
| `$SmtpPort` | SMTP 端口；QQ 邮箱通常为 `465` |
| `$SmtpUser` | 发件邮箱账号 |
| `$SmtpPass` | SMTP 授权码，**不要填邮箱登录密码** |
| `$MailFrom` | 发件人邮箱，通常与 `$SmtpUser` 相同 |
| `$MailTo` | 接收额度提醒的邮箱 |

`config.ps1` 只存在于你的电脑上，已被 Git 忽略，不能也不应上传。

### 重置判定的宽限设置

配置示例底部提供了以下可选项。默认值已经针对每 10 分钟检查一次的计划任务设置，
一般无需修改：

| 配置项 | 默认值 | 含义 |
| --- | --- | --- |
| `$NaturalResetEarlyToleranceMinutes` | `90` | 预计时间前 90 分钟以内的回补都算按期，避免因接口或检查延迟误报提前重置 |
| `$RefillMinimumPercent` | `15` | 总额度至少回补多少百分点才识别为重置 |
| `$RefillStartRemainingPercent` | `85` | 上一轮剩余额度不高于多少时，才开始判断回补 |
| `$EarlyResetNotificationCooldownHours` | `6` | 提前重置邮件的防重复间隔 |

判断按上一轮的“预计重置时间”进行：检查即使晚几个小时才运行，仍会认作按期重置；
只有明显早于该时间（超过宽限）才会被当成值得提醒的提前重置。

## 运行

发送测试邮件：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-quota-monitor.ps1 -TestMail
```

查看当前剩余额度：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\codex-quota-monitor.ps1 -ShowStatus
```

安装后台计划任务（每 10 分钟检查一次）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\_install-task.ps1
```

卸载计划任务：

```powershell
Unregister-ScheduledTask -TaskName CodexQuotaMonitor -Confirm:$false
```

## 隐私与安全

本项目不会把任何数据上传到 GitHub。公开仓库不会包含 SMTP 授权码、Codex
登录令牌、邮箱地址、状态文件、日志或使用历史。提交自己的改动前，请先运行：

```powershell
git status
```

并确认没有 `config.ps1`、`state.json`、`monitor.log`、`monitor_data.csv` 或
`monitor_data_v2.csv`。
更多说明请查看 [SECURITY.md](SECURITY.md)。

## 开源协议

本项目采用 [MIT License](LICENSE)。
