# 上传到 GitHub

项目首页标题已经设置为 **codex5小时重置焦虑缓解剂**，英文说明为 **Codex 5-Hour Reset Anxiety Relief**。默认仓库名为 `codex-5h-anxiety-relief`，创建时会将中文标题写入仓库描述。

## Windows 双击上传

这份源码包提供 `publish-to-github.cmd`。**双击将创建公开仓库并上传发布清单中的文件。**第一次需要在浏览器完成 GitHub 登录。它不是设置 Codex 自动问候的安装按钮；安装监控请用 `setup.cmd`。

1. 安装 [Git](https://git-scm.com/downloads) 和 [GitHub CLI](https://cli.github.com/)，安装后重新打开终端／文件夹窗口，确保 PATH 更新。
2. 完整解压源码包，双击 `publish-to-github.cmd`。
3. 如提示登录 GitHub，按浏览器指引完成。无需把 GitHub 密码或令牌写进文件。
4. 脚本会创建你个人账号下的 `codex-5h-anxiety-relief` 公开仓库、生成首次提交并推送 `main`，最后打开仓库网页。

如果已有 winget，也可自行安装依赖：

```powershell
winget install --id Git.Git --exact
winget install --id GitHub.cli --exact
```

GitHub CLI 的实际 winget 标识请以 [GitHub CLI 官方安装说明](https://github.com/cli/cli#installation)为准；也可以直接使用上面的官方网站安装包。

### 先检查、不上传

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-to-github.ps1 -CheckOnly
```

这个命令只检查发布文件清单，不登录、不创建仓库、不联网上传。

### 改仓库名或先建私有仓库

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-to-github.ps1 -RepositoryName "my-codex-5h-tool" -Visibility Private
```

双击入口默认公开；脚本也支持明确指定私有。它不会覆盖已存在的同名仓库。如果同名仓库存在，换一个名字，或自行使用 Git 管理已有仓库。

## 发布脚本具体做什么

发布器读取 `publish-manifest.txt`，只复制清单内文件，在 `%LOCALAPPDATA%\CodexQuotaHelloPublish\随机标识` 下新建发布副本。它不会把你日常工作目录整个 `git add`，不会上传 `.codex`、登录文件、状态、日志、压缩包或其他未列出的文件。

提交身份采用当前 GitHub 用户名和 GitHub noreply 邮箱。脚本不修改全局 Git 用户名、邮箱或凭证助手设置；GitHub CLI 自身会按登录流程保存凭证。保留发布副本，以便上传失败时恢复。

若仓库已创建但推送失败，错误消息会给出发布副本位置。你可以进入该位置检查 `git status` 与 `git remote -v`，解决网络后推送，或把错误信息发给维护者。不要为了重试而删除远端仓库。

发布器用于**首次发布一个新仓库**，不是日常同步工具。以后更新建议 clone 仓库、提交修改后正常 push。

## 不使用脚本的网页上传

1. 在 GitHub 新建仓库，仓库名使用 `codex-5h-anxiety-relief`，描述填写中文标题。
2. 进入 **Add file → Upload files**，上传解压目录里的源码与文件夹内容，确保 `README.md` 位于仓库根目录。
3. 确认隐藏文件及 `.github` 目录也已上传；它们包含忽略规则和 CI。不要只上传 ZIP 文件，否则首页不会自动展示项目说明。
4. 检查文件后提交。

## Linux 手动发布

安装 Git 与 GitHub CLI，登录后在一个干净的项目副本里执行：

```bash
gh auth login --hostname github.com --git-protocol https --web
git init -b main
git add .
git commit -m "Initial release v1.0.0"
gh repo create codex-5h-anxiety-relief --public --description "codex5小时重置焦虑缓解剂" --source . --remote origin --push
```

如尚未配置 Git 提交身份，请先按 Git 的提示配置。运行数据和认证数据不应放在该源码副本中。

## GitHub 仓库建议

描述：`codex5小时重置焦虑缓解剂｜Windows / Linux / Server / Docker / NAS`

可选 Topics：`codex`、`openai`、`automation`、`windows`、`linux`、`docker`、`nas`、`powershell`、`python`。

上传后检查 Actions 的 CI 结果。可以创建 `v1.0.0` Release，标题用“codex5小时重置焦虑缓解剂 v1.0.0”，将生成的源码 ZIP 和 `SHA256SUMS.txt` 作为附件。`RELEASE_NOTES.md` 已准备好中英文发布说明。

本交付包尚未替你创建或上传远端仓库。发布器依据 [GitHub CLI 创建仓库](https://cli.github.com/manual/gh_repo_create)与[登录](https://cli.github.com/manual/gh_auth_login)命令编写。
