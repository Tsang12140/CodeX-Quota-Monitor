# CodeX Quota Monitor

一个运行在 Windows 上的轻量脚本：定时检查本机 Codex / ChatGPT Plus
额度窗口，在额度重新补满时发送邮件提醒。

通知和日志都按**剩余额度**表达。例如：`本轮剩余额度 1% → 100%（已补满）`，
而不是难理解的“已用 99% → 0%”。

> 本项目读取 Codex 本机登录状态并调用当前客户端使用的额度接口。该接口并非
> 面向第三方开发者的稳定公开 API，字段或可用性未来可能变化。

## 功能

- 每次检查记录本轮**剩余额度**和预计重置时间；
- 发现剩余额度由低位（不高于 50%）恢复到高位（不低于 80%）时发送提醒；
- 重置后的 6 小时内防止重复通知；
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

并确认没有 `config.ps1`、`state.json`、`monitor.log` 或 `monitor_data.csv`。
更多说明请查看 [SECURITY.md](SECURITY.md)。

## 开源协议

本项目采用 [MIT License](LICENSE)。
