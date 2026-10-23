# Contributing / 贡献说明

感谢帮助改进。请保持“查询额度不调用模型、发送前落盘去重、数据不足不发送”的行为，并在中英文文档中同步说明用户可见的变化。

Please preserve model-free quota reads, write-before-send guards, and skipping on insufficient data. Update both language versions for user-visible behavior changes.

## Development

Runtime: Python 3.10+ standard library, or Windows PowerShell 5.1 for the retained Windows implementation. Python is needed for the development tests, including the PowerShell test fixture.

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/build-release.py
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-to-github.ps1 -CheckOnly
```

Linux installer tests use isolated directories and fake `codex`, `systemctl`, and `crontab` commands. They never change real scheduler entries. Do not add tests requiring personal credentials or a real model call to CI.

Linux 安装测试使用临时目录和模拟调度器，不改动真实任务。CI 不应依赖个人账号或实际问候。

## Release files

When adding a public file, also update `publish-manifest.txt`. Build archives with `scripts/build-release.py`; it includes only the listed source and documentation and preserves dotfiles. Build output goes into ignored `dist/` by default.

新增公开文件时同步维护发布清单。不要把运行状态、认证文件、测试生成的可执行文件、日志或本地压缩包加入清单。

Use an issue or pull request to describe a concrete problem, the resulting behavior, and relevant offline validation. Never include private credentials or unredacted runtime data.
