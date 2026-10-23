# 故障排查

先确认运行设备始终开机、联网且不休眠；Windows 还需要保留登录会话。不要用反复发送真实问候来排错，优先使用只读 `Check`／`check`。

| 现象 | 排查方法 |
|---|---|
| 找不到 Codex | 在同一用户下运行 `codex --version`；更新 CLI。Windows 特殊路径用 `-CodexPath`，Python 用 `--codex` |
| 不是 ChatGPT 登录 | 运行 `codex login`；服务器／容器使用 `--device-auth`。不要用单独计费的 API Key 代替订阅登录 |
| 版本过旧 | `codex exec --help` 必须包含 `--ignore-user-config` 和 `--ephemeral`；更新 Codex 后再试 |
| `quota-in-use` | 本窗口已有用量，属于正常等待 |
| `already-attempted` | 已保存防重复记录，正常等待；发送失败也可能保留该记录 |
| `missing-quota` | 服务未返回完整额度；稍后只读检查，确认账号支持这类额度查询 |
| `unexpected-window` | 不是 300 分钟窗口；本项目会跳过，不适配没有五小时额度的套餐 |
| `weekly-limit` / `limit-reached` | 周额度或服务端额度已阻断，短问候也不会发送 |
| `Quota request timed out` | 检查 DNS、网络、代理和服务连接；额度查询失败不会创建问候记录 |
| `Greeting timed out` / `Greeting failed` | 请求可能已经送达，保留至少五小时的去重记录；不要直接删状态反复发送 |
| `Unexpected greeting output` | 请求已经执行，但没有收到精确的“你好”；保留去重记录，检查 Codex 版本和上游行为 |
| 状态文件损坏 | 先停止监控，备份文件，再检查 JSON；如果确需重置本地状态，确认距任何可能的问候至少已过五小时 |
| 手动可以，后台不运行 | 检查 Windows 会话／任务历史、systemd lingering、cron 服务及任务中的可执行路径 |
| 找不到 Node | Linux 安装时保留了 PATH；更换 Node／CLI 路径后重新运行 `setup.sh` |
| NAS 登录不保留 | 确认认证卷始终挂在 `/home/node/.codex`，且没有更换 Compose 项目名或删除卷 |
| 容器 `Permission denied` | 使用默认命名卷，或将绑定目录权限调整给容器用户；镜像通常使用 UID 1000 |
| ARM NAS 无法构建 | 核对是否为 arm64，且官方 Codex/npm 包支持；32 位 ARM 不在支持目标内 |

## Windows 检查

双击 `status.cmd`，或打开 Windows“任务计划程序”查看 `CodexQuotaHello`。只有看到 `Installed`，才能确认安装器完成了任务注册。组织策略禁止任务时会明确报错。

睡眠设置需要用户自行调整；锁屏不等于注销。重启后未登录该用户时，原版 Windows 任务不会运行。

## Linux 检查

```bash
python3 monitor.py check
systemctl --user list-timers codex-quota-hello.timer
journalctl --user -u codex-quota-hello.service -n 30 --no-pager
crontab -l
```

使用 systemd 的主机不必同时使用 cron。安装器会清理本项目另一种方式的定时入口，保留其他任务。cron 守护进程名称随发行版不同，可能为 `cron` 或 `crond`。

## Docker 检查

```bash
docker compose ps
docker compose logs --tail=50 quota-hello
docker compose run --rm quota-hello check
```

镜像构建需要访问容器软件源和 npm；运行需要访问 Codex。宿主机代理只监听 `127.0.0.1` 时，容器通常不能把它当作宿主机代理使用，应按你的网络配置设置可访问的代理地址。项目不会自动修改代理或系统防火墙。

## 提交问题

请提供操作系统、架构、部署方式、CLI 版本、Python／Docker 版本，以及**脱敏后的相关错误行**。不要提交登录文件、令牌、完整用户目录、完整容器卷或未检查的日志。可以使用仓库的问题模板。
