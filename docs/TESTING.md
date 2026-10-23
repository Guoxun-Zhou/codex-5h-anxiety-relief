# Validation record / 验证记录

Recorded on 2026-10-23. This distinguishes implemented support from actual end-to-end deployment coverage.

## Verified GitHub CI

[All six jobs passed](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/runs/39898311661) for runtime commit `659aa79698a907308fc59ecbbb1285d9bc475eae`:

- Windows PowerShell: 28 offline checks, including UTF-8 BOM regression coverage.
- Python 3.10 and 3.12 on both Windows and Ubuntu.
- Linux x64 Docker image build, Compose validation, and unauthenticated entry-point checks.

The GitHub publication helper was also used successfully to create this public repository and upload its 39 manifest-listed files, after fixing expected negative probes on Windows PowerShell 5.1.

## Local checks

| Component | Validation performed |
|---|---|
| Windows PowerShell implementation | 28 offline checks, including guards, BOM-free UTF-8 subprocess input, caller-encoding restoration, real stdio fixture, and scheduler objects without registration |
| Python implementation on Windows | Offline unit tests, stdio protocol fixture, guard persistence, state corruption, concurrency lock, and greeting argument checks |
| Python implementation on Ubuntu / WSL | The same offline suite plus isolated systemd and cron installer/update/uninstaller tests |
| Linux shell scripts | Bash syntax check; generated units and cron entries checked using fake schedulers |
| Compose | `docker compose config --quiet` |
| Publication files | Manifest validation, package inspection, local-link checks, and exclusion of runtime data |

Tests do not authenticate, send a real greeting, buy credits, redeem resets, or install real scheduled jobs. Fixture accounts use `example.invalid`; any “Greeting completed” output during tests refers to a local fake process.

An earlier Windows deployment was reported successful by the user. This release builds on that implementation and adds the UTF-8 BOM compatibility fix exposed by hosted Windows CI. That report is not a guarantee for every account, CLI version, server policy, or NAS.

## Coverage limits

- Docker Engine was not running locally. The image build and unauthenticated startup checks subsequently passed in GitHub CI on Linux x64. Real-account container authentication was not performed in CI.
- No real NAS device or ARM64 host was available for end-to-end validation.
- Linux scheduler behavior was tested with isolated fake commands; no real cron entry or systemd user service was installed during preparation.
- CI checks use fixtures and do not prove real NAS authentication, persistent login, or unattended operation on every host.

The Dockerfile pins `@openai/codex` to `0.163.0`. The package's Linux x64 and arm64 variants were confirmed in registry metadata; this is not a substitute for running an actual image on each architecture. You can select another verified CLI version using `CODEX_VERSION`.

## 中文说明

已完成 Windows／Ubuntu 离线回归、Linux 模拟调度安装与卸载、Compose 配置及发布文件检查。GitHub 六项 CI 已全部通过，包括 Docker x64 镜像构建与无登录启动检查。发布助手已成功创建本公开仓库并上传 39 个清单文件。测试本身不会调用真实模型或安装真实定时任务。

Windows 原版已有用户反馈实际测试成功。NAS、ARM64、容器真实账号登录和长期无人值守运行仍需设备实测，首次部署请查看日志确认。此文档保留验证边界，避免把“代码支持”写成“所有设备都已实测”。
