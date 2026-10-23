# codex5小时重置焦虑缓解剂 v1.0.0

**先决条件：需要一台可以持续开机、保持联网且不休眠的电脑、服务器或 NAS。**NAS 应支持 Docker 或兼容的 Linux 执行环境。

额度恢复到 100% 后，通过 Codex CLI 发送一次“你好”，让已验证账号环境中的五小时计时提前开始。只读额度查询不调用模型，问候本身按正常用量计算。

包含 Windows 双击安装、Linux systemd／cron、Docker／NAS 部署、中英文使用与排错指南、测试、MIT 许可证及首次 GitHub 发布助手。只建议每个账号部署一个监控实例。

Windows PowerShell 回归、Windows／Ubuntu 的 Python 3.10 与 3.12、Docker x64 构建等六项 GitHub CI 已全部通过；也修复了 Windows UTF-8 环境的 BOM 兼容问题。真实 NAS 登录、ARM64 和长期无人值守部署仍需要设备确认。官方接口与计时策略可能变化，详见文档。

[查看通过的 CI 记录](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/runs/39898311661)

## English

**Prerequisite: an always-on, online, awake computer, server, or NAS.** NAS devices need Docker or a compatible Linux runtime.

Send a single “你好” through Codex CLI when the five-hour meter reports 100% remaining. A user has verified the timer behavior in their account environment. Quota reads do not invoke a model; greetings count as normal usage.

Includes Windows, Linux systemd/cron, Docker/NAS deployment, bilingual documentation, offline tests, the MIT license, and an initial GitHub publishing helper. Use one monitor per account.

All six GitHub CI jobs passed: Windows PowerShell, Python 3.10/3.12 on Windows and Ubuntu, and the Linux x64 Docker build. Windows UTF-8 BOM handling is covered by regression checks. Real NAS authentication, ARM64, and long-running unattended deployments still require device validation. See the documentation for service-version and timer-policy limits.

[Passing CI record](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/runs/39898311661)
