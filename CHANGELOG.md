# Changelog / 更新记录

## 1.0.0 — 2026-10-23

- 首次整理为公开发布项目，标题为“codex5小时重置焦虑缓解剂”。
- 保留已反馈实际运行成功的 Windows PowerShell 版本。
- 新增 Python 标准库实现，Linux systemd／cron 安装与卸载。
- 新增 Docker Compose 与 NAS 部署方式、持久化认证及状态卷。
- 补齐中英文首页、使用指南、排错、发布指南及 MIT 许可证。
- 添加离线回归测试、GitHub CI、显式发布文件清单及双击上传入口。
- 修正 Windows PowerShell 5.1 将首次发布时的“仓库不存在”检查视为致命错误的问题。
- PowerShell 回归改用原生 .NET 模拟进程，避免 CI 环境的 Python 启动器差异。
- 修复 Windows UTF-8 环境向子进程协议输入注入 BOM 的兼容问题，并验证调用者编码会恢复。

- Initial public project packaging with the requested Chinese title.
- Retained the Windows PowerShell implementation reported working by a user.
- Added standard-library Python, Linux systemd/cron installers, and Docker/NAS deployment.
- Added bilingual docs, MIT license, offline tests, CI, explicit release manifest, and a Windows publication helper.
- Fixed expected negative GitHub probes terminating the initial publisher under Windows PowerShell 5.1.
- Replaced the PowerShell RPC fixture with a native .NET process to avoid CI Python-launcher differences.
- Prevented a Windows UTF-8 BOM from leaking into child-process RPC input, with caller-encoding restoration coverage.
