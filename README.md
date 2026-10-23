# codex5小时重置焦虑缓解剂

> **使用前提：你需要一台能够持续开机、保持联网且不休眠的电脑、服务器或 NAS。**
> 脚本运行在你自己的设备上。没有在线设备时，它无法自动发起问候。Windows 使用任务计划程序，Linux 使用 systemd／cron；服务器按操作系统选择，NAS 推荐使用 Docker。**NAS 需要支持 Docker，或具备可运行本项目的 Linux 环境；并非所有 NAS 都能直接安装。**

[English](README.en.md) · [详细使用说明](docs/USAGE.zh-CN.md) · [故障排查](docs/TROUBLESHOOTING.zh-CN.md) · [如何上传到 GitHub](docs/PUBLISH.zh-CN.md)

[![CI](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/workflows/ci.yml/badge.svg)](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/workflows/ci.yml)

Windows · Linux · Server · Docker / NAS · Python 标准库 · MIT

一个在 Codex 五小时额度恢复为 100% 时，通过 Codex CLI 自动发送一次“你好”的小工具。

已有 Windows 用户实际测试成功：在其账号环境中，通过 Codex CLI 发起请求会开始新的五小时计时。本项目让这次轻量问候在设备后台完成，希望正式开始工作时，距离下一次重置的时间已经缩短。

**它不会增加额度、缩短服务端的五小时窗口或清除周限额。**问候会消耗正常用量；计时规则以你的账号和服务端实际表现为准。独立社区项目，与 OpenAI 无隶属关系。

## 选择安装方式

| 设备 | 推荐方式 | 需要准备 |
|---|---|---|
| Windows 电脑 | 双击 `setup.cmd` | 当前版本 Codex、Windows PowerShell 5.1；无需 Python |
| Linux 电脑／服务器 | `bash setup.sh` | Python 3.10+、Bash、Codex、systemd 用户会话或运行中的 cron |
| Windows 服务器 | Windows 方式或 Python 方式 | 可用的用户会话和任务计划程序；服务器系统需自行验证 |
| 支持 Docker 的 NAS／Linux 服务器 | Docker Compose | Docker Engine、Compose、兼容的 64 位架构 |
| 仅提供文件共享、不能运行程序的 NAS | 无法直接使用 | 需要另一个可运行脚本的主机 |

原生 CLI 与 Docker 路线均依赖 Codex 对 CPU 架构的支持。Docker 路线面向 amd64／arm64；32 位 ARM NAS 不在支持目标内。macOS 原生安装暂未提供。

## 快速开始

### Windows

1. 安装或更新[官方 Codex CLI](https://developers.openai.com/codex/cli/)，或使用附带 CLI 的 Codex 桌面应用。
2. 下载并**完整解压**本项目。双击 `setup.cmd`，如需登录，选择你日常使用的同一个 ChatGPT 账号。
3. 看到 `Installed` 后，约一分钟开始首次检查，以后每五分钟检查。

保持该 Windows 用户登录、不休眠、网络可访问 Codex。锁屏或关闭显示器可以；注销、睡眠或关机时无法运行。重启后登录该用户即可恢复。无需一直打开 Codex 界面。

| 文件 | 操作 |
|---|---|
| `setup.cmd` | 安装或更新后台任务 |
| `check-only.cmd` | 只查看额度，**不发问候** |
| `status.cmd` | 查看任务状态及最近日志 |
| `uninstall.cmd` | 停止、移除后台任务，保留数据和登录 |

### Linux／服务器

先安装 Python 3.10+ 和 Codex CLI，再在项目目录执行：

```bash
codex login --device-auth
python3 monitor.py check
bash setup.sh
```

`check` 只读额度。安装器会优先使用可用的 systemd 用户定时器，否则使用当前用户的 cron。无浏览器环境可按 [Codex 官方登录说明](https://learn.chatgpt.com/docs/auth)完成设备码登录。

如使用 systemd 用户定时器且需要退出登录后继续运行，请确认系统允许用户 lingering，并按需执行 `loginctl enable-linger "$USER"`。也可显式选择 `bash setup.sh --cron`；cron 守护进程必须正常运行。

卸载：`bash uninstall.sh`。此操作只移除本项目的定时任务，保留程序、状态和 Codex 登录。

### NAS／Docker

在支持 Docker Compose 的 NAS 或服务器上，将整个项目放入一个目录，进入该目录执行：

```bash
docker compose build
docker compose run --rm quota-hello login --device-auth
docker compose run --rm quota-hello check
docker compose up -d
```

登录同一个 ChatGPT 账号即可。容器自带 Python 和 Codex CLI，宿主机无需另外安装这两项。首次构建需要联网下载依赖。查看日志：`docker compose logs --tail=50 quota-hello`；停止：`docker compose down`。

`codex-auth` 卷保存官方 CLI 的登录数据，`quota-data` 卷保存状态和日志。保留这两个卷，才能在容器重建后继续登录与去重。**不要将卷内容上传到 GitHub。** NAS 容器管理器中的具体操作和权限设置见[详细说明](docs/USAGE.zh-CN.md#nas-与-docker)。

## 运行原理

1. 每五分钟通过官方 App Server 的 `account/rateLimits/read` 接口读取额度，此步骤不调用模型。
2. 检查 `codex` 额度桶，确认窗口长度为 300 分钟、已用比例为 0，且没有已知的周限额阻断。
3. **先保存防重复记录，再发送问候**。实际请求使用 ChatGPT 登录、临时会话、只读沙箱和低推理强度。
4. 成功后至少等待五小时再允许下一次尝试，避免短问候消耗太小、界面仍显示 100% 时连续发送。

额度字段参见[官方接口文档](https://learn.chatgpt.com/docs/app-server)，命令行行为参见[非交互模式说明](https://learn.chatgpt.com/docs/non-interactive-mode)。

## 你需要知道的边界

- 查询失败、额度缺失或窗口不匹配时跳过；断网后下一轮继续检查。
- 请求已发出后若超时或断电，无法确定服务端是否收到，会保留至少五小时的阻断记录；这次可能错过提前计时。
- 100% 是服务端显示精度，不保证绝对零用量；多个设备同时使用时可能额外产生一次短问候。
- **一个账号建议只部署一个监控实例**。多个不同主机的状态文件不能互相去重。
- 问候计入适用的五小时及周额度；本项目不购买积分，也不调用额度重置兑换接口。
- 这是需要设备在线的本地工具，Docker 也需要宿主机开机联网。

## 数据与隐私

认证由你安装的官方 Codex CLI 处理。本项目不复制或上传认证文件，也没有第三方数据接收服务。CLI 仍会按正常登录、请求流程与 OpenAI 通信。

| 方式 | 本项目的数据目录 |
|---|---|
| Windows | `%LOCALAPPDATA%\CodexQuotaHello` |
| Linux 默认 | `${XDG_STATE_HOME:-~/.local/state}/codex-quota-hello` |
| Docker | `quota-data` 卷，对应容器 `/data` |

日志记录额度、判断结果及错误；状态文件使用账号标识的 SHA-256 摘要命名，仍属于本地运行数据。不要公开完整运行目录。`.gitignore` 和上传文件清单会排除这些数据。

## 项目与测试

Windows 保留已实际验证的 PowerShell 实现；Linux／Docker 使用 Python 标准库实现。运行离线测试：

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Windows PowerShell 回归检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

测试使用模拟账号、模拟 Codex 和模拟定时器，不发送真实问候、不安装真实任务。GitHub CI 包含 Windows／Linux 测试及 Docker 镜像构建检查；发布前的本地验证记录见 [TESTING.md](docs/TESTING.md)。

## 发布与贡献

准备了 `publish-to-github.cmd`，供此项目的首次发布使用。安装 Git 和 GitHub CLI 后双击它，会按提示登录 GitHub，并创建公开的 `codex-5h-anxiety-relief` 仓库。它只上传发布清单内的源码与文档，详见[发布指南](docs/PUBLISH.zh-CN.md)。

[更新记录](CHANGELOG.md) · [贡献说明](CONTRIBUTING.md) · [安全与隐私](SECURITY.md) · [MIT 许可证](LICENSE)
