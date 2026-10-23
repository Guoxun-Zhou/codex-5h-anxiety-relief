[CmdletBinding()]
param(
    [ValidateSet('Setup','Check','Run','Status','Uninstall','Library')]
    [string]$Mode = 'Check',
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'CodexQuotaHello'),
    [string]$CodexPath
)

$ErrorActionPreference = 'Stop'
$script:TaskName = 'CodexQuotaHello'
$script:Root = [IO.Path]::GetFullPath($DataDirectory)
$script:Utf8 = New-Object Text.UTF8Encoding($false)

function Write-Log([string]$Message) {
    [IO.Directory]::CreateDirectory($script:Root) | Out-Null
    $line = '{0} {1}{2}' -f [DateTimeOffset]::Now.ToString('o'), $Message, [Environment]::NewLine
    [IO.File]::AppendAllText((Join-Path $script:Root 'monitor.log'), $line, $script:Utf8)
    Write-Host $Message
}

function Write-JsonFile([string]$Path, $Value) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), $script:Utf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Find-Codex {
    $candidates = New-Object 'Collections.Generic.List[string]'
    if ($CodexPath) { $candidates.Add($CodexPath) }
    $settingsPath = Join-Path $script:Root 'settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        $saved = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        if ($saved.codexPath) { $candidates.Add([string]$saved.codexPath) }
    }
    $command = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates.Add($command.Source) }
    $bundled = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    if (Test-Path -LiteralPath $bundled) {
        Get-ChildItem -LiteralPath $bundled -Filter codex.exe -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | ForEach-Object { $candidates.Add($_.FullName) }
    }
    $wrapper = Get-Command codex.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wrapper) {
        $npmScope = Join-Path (Split-Path $wrapper.Source) 'node_modules\@openai'
        if (Test-Path -LiteralPath $npmScope) {
            Get-ChildItem -LiteralPath $npmScope -Directory -Filter 'codex*' | ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Filter codex.exe -File -Recurse -ErrorAction SilentlyContinue
            } | Sort-Object LastWriteTime -Descending | ForEach-Object { $candidates.Add($_.FullName) }
        }
    }
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and ([IO.Path]::GetExtension($candidate) -eq '.exe')) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    throw 'Codex executable not found. Install/update Codex CLI or the Codex desktop app first; see README.'
}

function Start-CodexProcess([string]$Executable, [string[]]$Arguments) {
    $workDirectory = Join-Path $script:Root 'empty-workspace'
    [IO.Directory]::CreateDirectory($workDirectory) | Out-Null
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    # All arguments are fixed literals or Windows paths, neither can contain a quote.
    $quoted = foreach ($argument in $Arguments) {
        if ($argument.Contains('"')) { throw 'Unexpected quote in a process argument.' }
        '"' + $argument + '"'
    }
    $info.Arguments = $quoted -join ' '
    $info.WorkingDirectory = $workDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $script:Utf8
    $info.StandardErrorEncoding = $script:Utf8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Unable to start Codex.' }
    # Windows PowerShell 5.1 lacks ProcessStartInfo.StandardInputEncoding.
    # Wrap the stdin pipe explicitly, so Chinese is always sent as UTF-8.
    $writer = [IO.StreamWriter]::new($process.StandardInput.BaseStream, $script:Utf8)
    $writer.AutoFlush = $true
    # Drain stderr immediately, so a full stderr pipe cannot block quota reads.
    $stderr = $process.StandardError.ReadToEndAsync()
    return @{ Process = $process; Stderr = $stderr; Input = $writer }
}

function Stop-CodexProcess($Session) {
    if (-not $Session) { return }
    $process = $Session.Process
    try {
        if (-not $process.HasExited) {
            $Session.Input.Close()
            if (-not $process.WaitForExit(1500)) {
                $process.Kill()
                $process.WaitForExit(2000) | Out-Null
            }
        }
    } catch { } finally { $process.Dispose() }
}

function Invoke-Rpc($Session, [int]$Id, [string]$Method, $Parameters = @{}) {
    $request = @{ id = $Id; method = $Method; params = $Parameters } | ConvertTo-Json -Depth 15 -Compress
    $Session.Input.WriteLine($request)
    $Session.Input.Flush()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 35) {
        $remaining = [Math]::Max(1, 35000 - [int]$clock.ElapsedMilliseconds)
        $pending = $Session.Process.StandardOutput.ReadLineAsync()
        if (-not $pending.Wait($remaining)) { throw ('Quota request timed out: ' + $Method) }
        $line = $pending.Result
        if ($null -eq $line) { throw ('Codex closed its connection: ' + $Method) }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $message = $line | ConvertFrom-Json } catch { continue }
        if (($null -ne $message.id) -and ([string]$message.id -eq [string]$Id)) {
            if ($message.error) { throw ('Codex request failed: ' + $Method + '; code=' + $message.error.code) }
            return $message.result
        }
    }
    throw ('Quota request timed out: ' + $Method)
}

function Get-AccountSnapshot([string]$Executable) {
    $session = $null
    try {
        $session = Start-CodexProcess $Executable @('app-server')
        $null = Invoke-Rpc $session 1 'initialize' @{
            clientInfo = @{ name = 'codex_quota_hello'; title = 'Codex Quota Hello'; version = '1.0.0' }
        }
        $session.Input.WriteLine('{"method":"initialized","params":{}}')
        $session.Input.Flush()
        $identity = Invoke-Rpc $session 2 'account/read' @{ refreshToken = $false }
        if (($null -eq $identity.account) -or ($identity.account.type -ne 'chatgpt')) {
            throw 'ChatGPT account login is required. Run setup.cmd and sign in with your subscription account.'
        }
        $accountIdentity = [string]$identity.account.id
        if (-not $accountIdentity) { $accountIdentity = [string]$identity.account.email }
        if (-not $accountIdentity) { throw 'Account identity is unavailable; refusing to mix account state.' }
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $accountKey = [BitConverter]::ToString($hasher.ComputeHash($script:Utf8.GetBytes($accountIdentity))).Replace('-', '').ToLowerInvariant() }
        finally { $hasher.Dispose() }
        $limits = Invoke-Rpc $session 3 'account/rateLimits/read'
        if ($null -ne $limits.rateLimitsByLimitId) {
            # Never fall back to a different meter when the multi-meter view exists.
            $bucket = $limits.rateLimitsByLimitId.codex
        } else {
            $bucket = $limits.rateLimits
            if ($bucket.limitId -and ($bucket.limitId -ne 'codex')) { $bucket = $null }
        }
        if ($null -eq $bucket) { throw 'Codex usage meter is unavailable.' }
        return [pscustomobject]@{ AccountKey = $accountKey; Bucket = $bucket }
    } finally { Stop-CodexProcess $session }
}

function Get-SendDecision($Bucket, $State, [long]$Now) {
    if (($null -eq $Bucket.primary) -or ($null -eq $Bucket.primary.usedPercent) -or
        ($null -eq $Bucket.primary.windowDurationMins)) { return 'missing-quota' }
    if ([double]$Bucket.primary.windowDurationMins -ne 300) { return 'unexpected-window' }
    if (($null -ne $Bucket.secondary) -and ($null -ne $Bucket.secondary.usedPercent) -and
        ([double]$Bucket.secondary.usedPercent -ge 100)) { return 'weekly-limit' }
    if ($Bucket.rateLimitReachedType) { return 'limit-reached' }
    if ($State -and ([long]$State.blockUntil -gt $Now)) { return 'already-attempted' }
    if ([double]$Bucket.primary.usedPercent -ne 0) { return 'quota-in-use' }
    return 'send'
}

function Invoke-Hello([string]$Executable) {
    $help = & $Executable exec --help 2>&1 | Out-String
    if (($LASTEXITCODE -ne 0) -or ($help -notmatch '--ignore-user-config') -or ($help -notmatch '--ephemeral')) {
        throw 'This Codex version is too old. Update it before enabling automatic greetings.'
    }
    $session = $null
    try {
        $session = Start-CodexProcess $Executable @(
            'exec', '--ignore-user-config', '--skip-git-repo-check', '--ephemeral',
            '--sandbox', 'read-only', '-c', 'approval_policy=never',
            '-c', 'forced_login_method=chatgpt',
            '-c', 'model_reasoning_effort=low', '-c', 'project_doc_max_bytes=0', '-'
        )
        $stdout = $session.Process.StandardOutput.ReadToEndAsync()
        $hello = [string][char]0x4F60 + [char]0x597D
        $session.Input.WriteLine('Reply with exactly these two characters: ' + $hello + '. Do not use tools or inspect files.')
        $session.Input.Close()
        if (-not $session.Process.WaitForExit(120000)) { throw 'Greeting timed out. It may have reached the service; retry is blocked for this window.' }
        if ($session.Process.ExitCode -ne 0) { throw ('Greeting failed; exit=' + $session.Process.ExitCode + '. Retry is blocked for this window to avoid duplicates.') }
        $reply = $stdout.GetAwaiter().GetResult().Trim()
        if ($reply -ne $hello) { throw 'Greeting finished with unexpected output. Retry is blocked for this window.' }
    } finally { Stop-CodexProcess $session }
}

function Invoke-Monitor([switch]$ReadOnly) {
    [IO.Directory]::CreateDirectory($script:Root) | Out-Null
    $lock = $null
    try {
        try { $lock = [IO.File]::Open((Join-Path $script:Root 'running.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] { Write-Host 'A check is already running; skipped.'; return }
        $executable = Find-Codex
        $snapshot = Get-AccountSnapshot $executable
        $statePath = Join-Path $script:Root ('state-' + $snapshot.AccountKey + '.json')
        $state = $null
        if (Test-Path -LiteralPath $statePath) {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if (($null -eq $state.blockUntil) -or ([long]$state.blockUntil -le 0)) { throw 'Invalid state file; refusing to send. See README.' }
        }
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $decision = Get-SendDecision $snapshot.Bucket $state $now
        $primary = $snapshot.Bucket.primary
        $remaining = if ($null -ne $primary.usedPercent) { 100 - [double]$primary.usedPercent } else { 'unknown' }
        $resetText = if ($primary.resetsAt) { [DateTimeOffset]::FromUnixTimeSeconds([long]$primary.resetsAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz') } else { 'unknown' }
        Write-Log ('remaining={0}%; reset={1}; decision={2}; checkOnly={3}' -f $remaining, $resetText, $decision, [bool]$ReadOnly)
        if ($ReadOnly -or ($decision -ne 'send')) { return }
        # Write the guard BEFORE starting a model request. Even an ambiguous network failure
        # or power loss cannot cause another attempt during the following five hours.
        # Reserve five extra minutes for a request accepted shortly before a timeout.
        $state = @{ attemptAt = $now; blockUntil = $now + 18300; outcome = 'attempted' }
        Write-JsonFile $statePath $state
        Invoke-Hello $executable
        $state.outcome = 'completed'
        # Start the successful guard after the response, so process startup latency
        # cannot let a rounded-to-zero meter trigger before the real reset.
        $state.blockUntil = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 18000
        Write-JsonFile $statePath $state
        Write-Log 'Greeting completed. No further greeting attempt for at least five hours.'
    } finally { if ($lock) { $lock.Dispose() } }
}

function Install-Monitor {
    $executable = Find-Codex
    $help = & $executable exec --help 2>&1 | Out-String
    if ($help -notmatch '--ignore-user-config') { throw 'Update Codex first; this version does not support --ignore-user-config.' }
    [IO.Directory]::CreateDirectory($script:Root) | Out-Null
    $loginOutput = & $executable login status 2>&1 | Out-String
    if (($LASTEXITCODE -ne 0) -or ($loginOutput -notmatch 'ChatGPT')) {
        Write-Host 'A browser will open. Sign in to the SAME ChatGPT subscription account.'
        & $executable login
        if ($LASTEXITCODE -ne 0) { throw 'Login did not complete.' }
    }
    # Real quota access is checked before any scheduled task is installed.
    $snapshot = Get-AccountSnapshot $executable
    if ($null -eq $snapshot.Bucket.primary -or [double]$snapshot.Bucket.primary.windowDurationMins -ne 300) {
        throw 'A five-hour Codex usage meter was not found. No task was installed.'
    }
    $installedScript = Join-Path $script:Root 'monitor.ps1'
    if ([IO.Path]::GetFullPath($PSCommandPath) -ne $installedScript) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    }
    Write-JsonFile (Join-Path $script:Root 'settings.json') @{ codexPath = $executable }
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $installedScript + '" -Mode Run -DataDirectory "' + $script:Root + '"'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $onLogon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger @($trigger, $onLogon) -Settings $settings -Principal $principal -Description 'Check Codex quota every 5 minutes; greet only when unused, at most one attempt per five hours.' -Force | Out-Null
    Write-Log 'Installed. The first background check starts in about one minute; later checks run every five minutes.'
    Write-Host ('Program and logs: ' + $script:Root)
    Write-Host 'Keep this Windows user signed in, the computer awake, and the network connected. Locking the screen is OK.'
}

if ($Mode -eq 'Library') { return }
try {
    switch ($Mode) {
        'Setup' { Install-Monitor }
        'Check' { Invoke-Monitor -ReadOnly }
        'Run' { Invoke-Monitor }
        'Status' {
            Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue | Select-Object TaskName, State
            Get-ScheduledTaskInfo -TaskName $script:TaskName -ErrorAction SilentlyContinue | Select-Object LastRunTime, LastTaskResult, NextRunTime
            $logPath = Join-Path $script:Root 'monitor.log'
            if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Tail 15 }
        }
        'Uninstall' {
            $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
            if ($task) {
                Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
                Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
            }
            Write-Host 'Automatic checks stopped and the scheduled task removed. Logs and login were kept.'
        }
    }
} catch {
    Write-Log ('ERROR: ' + $_.Exception.Message)
    exit 1
}
