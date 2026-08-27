# 安全与隐私

## 不要提交私密文件

仓库的 `.gitignore` 会排除以下文件：

- `config.ps1`：SMTP 地址、收发邮箱与授权码；
- `state.json`、`monitor.log`、`monitor_data.csv`、`monitor_data_v2.csv`：账号信息和个人使用历史；
- `auth.json`、令牌、证书和密钥文件。

提交前请运行 `git status`，确认暂存区中没有上述文件。尤其不要把
`C:\Users\<你的用户名>\.codex\auth.json` 复制进项目或上传。

## SMTP 授权码

请使用邮箱服务商生成的 SMTP 专用授权码，而不是邮箱登录密码。若授权码
被泄露，请立即在邮箱设置中撤销它并新建一个；同时更新本机的 `config.ps1`。

## 漏洞报告

请不要在公开 Issue 中发布令牌、授权码或完整日志。可先创建一个仅描述
影响范围的 Issue，维护者会提供后续的私密沟通方式。
