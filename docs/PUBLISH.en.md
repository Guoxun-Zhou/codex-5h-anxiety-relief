# Publish to GitHub

The project title is **codex5小时重置焦虑缓解剂**, with the English name **Codex 5-Hour Reset Anxiety Relief**. The default repository slug is `codex-5h-anxiety-relief`; its description uses the Chinese title.

## Double-click publishing on Windows

**Running `publish-to-github.cmd` creates a public repository and uploads the manifest-listed files.** First use may require GitHub browser authentication. This is separate from `setup.cmd`, which installs quota monitoring.

1. Install [Git](https://git-scm.com/downloads) and [GitHub CLI](https://cli.github.com/), then reopen your terminal or folder window so PATH is refreshed.
2. Fully extract the source archive and double-click `publish-to-github.cmd`.
3. Complete GitHub authentication if prompted. Do not paste a password or token into the project.
4. The helper creates `codex-5h-anxiety-relief` under your personal account, commits the release, pushes `main`, and opens the repository page.

You can instead use the installers from their official sites. With winget, Git uses `winget install --id Git.Git --exact`; consult the [GitHub CLI installation instructions](https://github.com/cli/cli#installation) for its current package identifier.

### Check without publishing

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-to-github.ps1 -CheckOnly
```

This validates the manifest without login, network requests, repository creation, or upload.

### Choose another name or private visibility

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-to-github.ps1 -RepositoryName "my-codex-5h-tool" -Visibility Private
```

The double-click entry point defaults to public. Existing repositories are never overwritten. Choose another name or manage an existing repository with Git yourself.

## What the helper uploads

Only `publish-manifest.txt` entries are copied into a new checkout under `%LOCALAPPDATA%\CodexQuotaHelloPublish\<random-id>`. The helper never stages your entire work directory. Credentials, `.codex`, runtime state, logs, archives, and unlisted files are excluded.

Commit identity uses the signed-in GitHub username and its GitHub noreply address. Global Git name, email, and credential-helper settings are not changed. GitHub CLI itself stores credentials through its normal authentication flow. The publication checkout is retained for recovery.

If repository creation succeeds but push fails, the error identifies the local checkout. Inspect `git status` and `git remote -v` there, fix connectivity, and push again. Do not delete the remote repository merely to retry.

The helper is for the **first publication of a new repository**, not ongoing synchronization. Use a normal clone, commits, and pushes for later updates.

## Browser-only upload

1. Create a repository named `codex-5h-anxiety-relief` and set the desired description.
2. Choose **Add file → Upload files** and upload the extracted files and folders, with `README.md` at the repository root.
3. Ensure hidden files and `.github` are present; they contain ignore rules and CI. Uploading only the ZIP will not render the project README as its homepage.
4. Review and commit the files.

## Manual Linux publication

With Git and GitHub CLI installed, use a clean source copy:

```bash
gh auth login --hostname github.com --git-protocol https --web
git init -b main
git add .
git commit -m "Initial release v1.0.0"
gh repo create codex-5h-anxiety-relief --public --description "codex5小时重置焦虑缓解剂" --source . --remote origin --push
```

Configure a Git commit identity first if needed. Keep authentication and runtime directories outside this source copy.

## Repository details

Suggested description: `codex5小时重置焦虑缓解剂 | Windows / Linux / Server / Docker / NAS`.

Optional topics: `codex`, `openai`, `automation`, `windows`, `linux`, `docker`, `nas`, `powershell`, `python`.

Check CI results in Actions after uploading. You can create a `v1.0.0` release and attach the generated source ZIP and `SHA256SUMS.txt`. Bilingual release text is available in `RELEASE_NOTES.md`.

This source package has not created or uploaded a repository for you. The helper uses the documented [GitHub CLI repository creation](https://cli.github.com/manual/gh_repo_create) and [authentication](https://cli.github.com/manual/gh_auth_login) commands.
