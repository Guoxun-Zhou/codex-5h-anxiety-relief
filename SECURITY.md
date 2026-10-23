# Security and privacy / 安全与隐私

This project has no third-party collection service. Its runtime invokes the official Codex CLI, which handles authentication and communicates with OpenAI. Docker stores those credentials in the persistent `codex-auth` volume. Local state and logs belong to the user and should not be published.

本项目没有第三方数据收集服务，认证与上游请求由官方 CLI 处理。认证卷、状态、日志都属于本地运行数据，请勿上传到 GitHub。

The GitHub publisher uses an explicit file manifest and rejects credential/runtime paths. It does not publish unlisted files. This reduces accidental inclusion, but reviewers should still inspect source changes and archives before publishing.

发布工具使用文件清单，只上传列出的源码与文档，并拒绝认证与运行数据路径。修改文件后仍应检查准备公开的内容。

If you find a vulnerability, use GitHub's private vulnerability reporting when enabled for the repository. Otherwise open an issue with only a high-level description and request a private reporting route. Never post credentials or exploit details that expose another user's data.

发现漏洞时，优先使用仓库启用的私密漏洞报告功能；如果未启用，请仅描述问题类型并请求私下沟通渠道，不公开凭证或他人数据。
