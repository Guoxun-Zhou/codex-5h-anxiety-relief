#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$')]
    [string]$RepositoryName = 'codex-5h-anxiety-relief',
    [ValidateSet('Public','Private')][string]$Visibility = 'Public',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
$project = Get-Content -LiteralPath (Join-Path $sourceRoot 'project.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$manifest = Join-Path $sourceRoot 'publish-manifest.txt'
$files = @(Get-Content -LiteralPath $manifest -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
$seen = @{}
foreach ($relative in $files) {
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) { throw 'Unsafe manifest path.' }
    if ($seen.ContainsKey($relative.ToLowerInvariant())) { throw ('Duplicate manifest path: ' + $relative) }
    $seen[$relative.ToLowerInvariant()] = $true
    if ($relative -match '(^|[\\/])(auth\.json|settings\.json|state-[^/\\]+\.json|\.env[^/\\]*|\.codex|\.git)([\\/]|$)' -or $relative -match '\.log(\.[^/\\]+)?$|\.(zip|exe|key|pem|pfx)$') {
        throw ('Runtime or credential file is not publishable: ' + $relative)
    }
    $full = [IO.Path]::GetFullPath((Join-Path $sourceRoot $relative))
    if (-not $full.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escaped the project.' }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw ('Missing project file: ' + $relative) }
    $cursorPath = $full
    while ($cursorPath -ne $sourceRoot) {
        $cursor = Get-Item -LiteralPath $cursorPath -Force
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked files/directories are not published.' }
        $cursorPath = Split-Path -Parent $cursorPath
    }
}
Write-Host ('Project: ' + $project.displayName)
Write-Host ('Repository: ' + $RepositoryName + '; visibility: ' + $Visibility + '; files: ' + $files.Count)
if ($CheckOnly) { Write-Host 'Manifest verified. No GitHub request, login, commit, or upload was performed.'; exit 0 }

$git = Get-Command git.exe -ErrorAction SilentlyContinue
$gh = Get-Command gh.exe -ErrorAction SilentlyContinue
if (-not $git -or -not $gh) { throw 'Install Git and GitHub CLI first, then reopen this window. See docs/PUBLISH.zh-CN.md.' }
function Invoke-GitHubProbe([string[]]$Arguments) {
    # In Windows PowerShell 5.1, redirected native stderr can become a terminating
    # error under Stop. Expected negative probes must instead use the exit code.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $gh.Source @Arguments *> $null
        return [int]$LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
}
if ((Invoke-GitHubProbe @('auth', 'status', '--hostname', 'github.com')) -ne 0) {
    & $gh.Source auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { throw 'GitHub login did not complete.' }
}
$identityText = & $gh.Source api user
if ($LASTEXITCODE -ne 0) { throw 'Unable to identify the signed-in GitHub account.' }
$identity = $identityText | ConvertFrom-Json
$login = [string]$identity.login
if ($login -notmatch '^[a-zA-Z0-9-]+$' -or [string]$identity.id -notmatch '^\d+$') { throw 'Unexpected GitHub identity.' }
$target = $login + '/' + $RepositoryName
if ((Invoke-GitHubProbe @('repo', 'view', $target, '--json', 'nameWithOwner')) -eq 0) {
    throw ('Repository already exists: ' + $target + '. Choose a different name; existing repositories are never overwritten.')
}

$stage = Join-Path $env:LOCALAPPDATA ('CodexQuotaHelloPublish\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($relative in $files) {
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot $relative) -Destination $destination
}
Write-Host ('Uploading ONLY the release manifest to https://github.com/' + $target)
Write-Host ('Local publication checkout: ' + $stage)
& $git.Source -C $stage init -b main
if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
& $git.Source -C $stage add --all
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
$noreply = [string]$identity.id + '+' + $login + '@users.noreply.github.com'
& $git.Source -C $stage -c ('user.name=' + $login) -c ('user.email=' + $noreply) -c commit.gpgsign=false commit -m ('Initial release v' + $project.version)
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
& $gh.Source repo create $target ('--' + $Visibility.ToLowerInvariant()) --description $project.displayName --source $stage --remote origin
if ($LASTEXITCODE -ne 0) { throw 'Repository creation failed. The local publication checkout was kept.' }
# Use GitHub CLI credentials for this command only; do not edit global Git settings.
& $git.Source -C $stage -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin main
if ($LASTEXITCODE -ne 0) { throw ('Repository was created, but push failed. Local files remain at ' + $stage + '. See the publishing guide.') }
Write-Host ('Published: https://github.com/' + $target)
& $gh.Source repo view $target --web
