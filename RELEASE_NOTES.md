# codex5小时重置焦虑缓解剂 v1.0.0

**先决条件：需要一台可以持续开机、保持联网且不休眠的电脑、服务器或 NAS。**NAS 应支持 Docker 或兼容的 Linux 执行环境。

额度恢复到 100% 后，通过 Codex CLI 发送一次“你好”，让已验证账号环境中的五小时计时提前开始。只读额度查询不调用模型，问候本身按正常用量计算。

包含 Windows 双击安装、Linux systemd／cron、Docker／NAS 部署、中英文使用与排错指南、测试、MIT 许可证及首次 GitHub 发布助手。只建议每个账号部署一个监控实例。

本地已完成 Windows PowerShell 回归、Windows 与 Ubuntu Python 离线测试、Linux 模拟调度安装测试和 Compose 配置校验。Docker 镜像构建与真实 NAS 登录仍需要在实际运行环境或 CI 中确认。官方接口与计时策略可能变化，详见文档。

## English

**Prerequisite: an always-on, online, awake computer, server, or NAS.** NAS devices need Docker or a compatible Linux runtime.

Send a single “你好” through Codex CLI when the five-hour meter reports 100% remaining. A user has verified the timer behavior in their account environment. Quota reads do not invoke a model; greetings count as normal usage.

Includes Windows, Linux systemd/cron, Docker/NAS deployment, bilingual documentation, offline tests, the MIT license, and an initial GitHub publishing helper. Use one monitor per account.

Local validation covers Windows PowerShell, Python on Windows and Ubuntu, isolated Linux scheduler installation tests, and Compose configuration. Actual Docker builds and NAS authentication remain to be verified in the deployment environment or CI. See the documentation for service-version and timer-policy limits.
