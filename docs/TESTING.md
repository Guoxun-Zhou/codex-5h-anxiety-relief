# Validation record / 验证记录

Recorded on 2026-10-23. This distinguishes implemented support from actual end-to-end deployment coverage.

## Local checks

| Component | Validation performed |
|---|---|
| Original Windows PowerShell implementation | 27 offline checks, including guards, UTF-8 greeting process fixture, real stdio fixture, and scheduler objects without registration |
| Python implementation on Windows | Offline unit tests, stdio protocol fixture, guard persistence, state corruption, concurrency lock, and greeting argument checks |
| Python implementation on Ubuntu / WSL | The same offline suite plus isolated systemd and cron installer/update/uninstaller tests |
| Linux shell scripts | Bash syntax check; generated units and cron entries checked using fake schedulers |
| Compose | `docker compose config --quiet` |
| Publication files | Manifest validation, package inspection, local-link checks, and exclusion of runtime data |

Tests do not authenticate, send a real greeting, buy credits, redeem resets, or install real scheduled jobs. Fixture accounts use `example.invalid`; any “Greeting completed” output during tests refers to a local fake process.

An earlier Windows deployment was reported successful by the user. The Windows runtime in this release is retained from that working package. That report is not a guarantee for every account, CLI version, server policy, or NAS.

## Coverage limits

- Docker Engine was not running in the preparation environment. Compose was validated, but a local image build and container authentication were not completed.
- No real NAS device or ARM64 host was available for end-to-end validation.
- Linux scheduler behavior was tested with isolated fake commands; no real cron entry or systemd user service was installed during preparation.
- GitHub CI is supplied for the published repository, including a Docker build. It has not run on GitHub before publication.
- The publication helper's manifest-only mode is checked locally. A real remote repository is not created during preparation.

The Dockerfile pins `@openai/codex` to `0.163.0`. The package's Linux x64 and arm64 variants were confirmed in registry metadata; this is not a substitute for running an actual image on each architecture. You can select another verified CLI version using `CODEX_VERSION`.

## 中文说明

已完成 Windows／Ubuntu 离线回归、Linux 模拟调度安装与卸载、Compose 配置及发布文件检查。测试不会调用真实模型、安装真实任务或创建 GitHub 远端仓库。

Windows 原版已有用户反馈实际测试成功。Docker、NAS、ARM64 和 GitHub CI 的真实运行状态不能仅凭配置检查认定已经通过，首次部署请查看日志确认。此文档保留验证边界，避免把“代码支持”写成“所有设备都已实测”。
