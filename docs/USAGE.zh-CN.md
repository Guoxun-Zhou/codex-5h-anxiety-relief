# 详细使用说明

**先准备一台能够持续开机、联网且不休眠的电脑、服务器或 NAS。**任务在该设备上执行。设备可以不是你日常工作的那台，但 Codex 必须登录同一个 ChatGPT 账号。一个账号只部署一个监控实例。

## Windows

使用 `setup.cmd` 安装。会先检查 CLI 版本、登录和 300 分钟额度窗口，再复制程序到 `%LOCALAPPDATA%\CodexQuotaHello`，注册名为 `CodexQuotaHello` 的 Windows 计划任务。通常以普通用户运行即可；组织策略可能限制创建任务。

任务约一分钟后首次运行，每五分钟运行一次，同时设有登录触发器。它使用当前用户的交互式登录会话，因此锁屏可继续，注销后不能运行。安装器不会修改睡眠、电源或系统执行策略；`ExecutionPolicy Bypass` 仅用于启动本次脚本，不会修改注册表中的全局设置。

手动命令：

```powershell
# 只读检查
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -Mode Check
# 立即检查并在符合条件时问候
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -Mode Run
# 指定特殊安装位置
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -Mode Setup -CodexPath "D:\Tools\Codex\codex.exe"
```

更新时下载新版本，再运行 `setup.cmd`。原有状态记录会保留，避免更新后立即重复发送。

## Linux 与服务器

要求 Python 3.10+、Bash，以及宿主架构支持的 Codex CLI。可先检查：

```bash
python3 --version
codex --version
codex login --device-auth
python3 monitor.py check
```

设备码登录可能需要先在账号安全设置中开启；如果当前工作区不提供设备码，请使用[官方文档中的其他登录方式](https://learn.chatgpt.com/docs/auth)。CLI 负责保存认证信息，项目不需要填写密码或 API Key。

安装自动任务：

```bash
bash setup.sh             # 自动选择
bash setup.sh --systemd   # 要求 systemd 用户会话可用
bash setup.sh --cron      # 使用当前用户的 cron
```

程序安装到 `${XDG_DATA_HOME:-~/.local/share}/codex-quota-hello`，默认数据位于 `${XDG_STATE_HOME:-~/.local/state}/codex-quota-hello`。可以在安装前设定项目专用数据目录：

```bash
QUOTA_HELLO_DATA=/your/persistent/path bash setup.sh
```

systemd 方式生成用户级 service 和 timer。检查：

```bash
systemctl --user list-timers codex-quota-hello.timer
journalctl --user -u codex-quota-hello.service -n 30 --no-pager
```

用户级 systemd 任务是否在退出登录后持续运行，取决于主机的 lingering 设置。长期无人值守时，确认 `loginctl enable-linger "$USER"` 可用且已启用，或者选择运行中的 cron。服务器的防火墙、网络和用户权限仍需满足 Codex 正常运行要求。

cron 方式写入带 `# codex-quota-hello` 标记的专用条目，保留其他条目；重复安装会替换本项目条目。检查 `crontab -l`，并确认发行版的 cron／crond 服务正常。安装脚本会记录当前 PATH 及 CLI 绝对路径，避免定时环境找不到 Node 或 Codex。

手动前台运行不需要安装定时器：

```bash
python3 monitor.py check       # 只读
python3 monitor.py run         # 一次自动判断
python3 monitor.py watch       # 前台每五分钟检查，Ctrl+C 停止
python3 monitor.py status      # 只看本地日志
```

全局参数放在子命令前：`python3 monitor.py --codex /path/to/codex --data-dir /path/to/state check`。Python 版也可在 Windows 使用，但不要与 PowerShell 版另起独立监控。

## NAS 与 Docker

NAS 是一种通常长期联网、提供文件存储等服务的设备。**仅能共享文件并不等于能运行本项目**：推荐确认它支持 Docker／容器管理器，以及匹配的 amd64 或 arm64 架构。32 位 ARM 不在支持目标内。

在支持 Compose 的终端或 SSH 会话中：

```bash
docker compose build
docker compose run --rm quota-hello login --device-auth
docker compose run --rm quota-hello check
docker compose up -d
docker compose logs --tail=50 quota-hello
```

在浏览器完成设备码登录后，认证保存在 `codex-auth` 卷里。检查成功再后台启动。容器无需映射任何端口，不需要挂载 Docker socket，也不需要宿主机网络模式。它需要向外访问 Codex 登录与服务接口。

Compose 中的 `restart: unless-stopped` 会在 Docker 恢复运行后按策略重启容器；NAS 本身和 Docker 服务也必须启用。换用不同的 Compose 项目目录或项目名可能创建另一组卷，迁移时应保持项目名或明确迁移卷。

如果 NAS 只有 Docker 命令或图形容器管理器，可使用等价流程：

```bash
docker build -t codex-quota-hello:local .
docker volume create codex-hello-auth
docker volume create codex-hello-data
docker run --rm -it -v codex-hello-auth:/home/node/.codex -v codex-hello-data:/data codex-quota-hello:local login --device-auth
docker run --rm -v codex-hello-auth:/home/node/.codex -v codex-hello-data:/data codex-quota-hello:local check
docker run -d --name codex-quota-hello --init --restart unless-stopped -v codex-hello-auth:/home/node/.codex -v codex-hello-data:/data codex-quota-hello:local watch
```

镜像以 `node` 用户运行，默认 UID 为 1000；使用命名卷可使用镜像预设的目录权限。自行改成宿主目录挂载时，要保证容器用户对认证与数据目录可写。不要为了修复权限就公开认证目录。

本项目没有预先发布容器镜像，提供的是本地构建文件。默认固定 `CODEX_VERSION=0.163.0`，可用 `CODEX_VERSION=<你验证的版本> docker compose build --no-cache` 切换 CLI 版本；在 PowerShell 中先设置 `$env:CODEX_VERSION`。

更新前先停止容器，再重新构建并启动：

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

停止并移除容器：`docker compose down`。**不要加 `-v`，除非确实要删除登录及防重复状态卷。**

## 日志与判断

| 判断 | 含义 |
|---|---|
| `send` | 满足问候条件；`checkOnly=True` 时仍不会发送 |
| `quota-in-use` | 本窗口已有用量，等待恢复 |
| `already-attempted` | 已保留本次尝试，暂不重复 |
| `weekly-limit` / `limit-reached` | 已知额度阻断 |
| `missing-quota` / `unexpected-window` | 额度数据不足或不是 300 分钟窗口 |
| `Greeting completed` | 问候进程成功，并返回预期文字 |
| `ERROR` | 本轮失败，需结合错误查看排查文档 |

Python 版日志按 1 MiB 轮转、保留 3 个备份。Windows 原版日志为追加写入。项目日志不保存问候的完整上游 stderr。官方 CLI 可能另外保存其正常诊断数据。

## 去重和断网

同一数据目录使用文件锁阻止并发检查。发送前先写入 `attempted` 状态，成功后写入 `completed`。成功阻断从回复完成时算五小时；发送结果不确定时，预留五小时加五分钟，优先避免重复发送。额度查询阶段失败不会写入尝试状态。

这些记录不是跨设备分布式锁。换主机部署前请停掉旧实例，并保留或迁移状态；不要依赖多个独立监控互相发现。卸载默认保留状态及登录。
