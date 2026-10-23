param([string]$ScratchDirectory)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
if (-not $ScratchDirectory) { $ScratchDirectory = Join-Path ([IO.Path]::GetTempPath()) ('CodexQuotaHello-tests-' + [guid]::NewGuid().ToString('N')) }
$testRoot = [IO.Path]::GetFullPath($ScratchDirectory)
. (Join-Path $project 'monitor.ps1') -Mode Library -DataDirectory (Join-Path $testRoot 'library')
$testCount = 0
$originalHello = (Get-Item Function:Invoke-Hello).ScriptBlock
function Assert-Equal($Actual, $Expected, [string]$Name) {
    if ($Actual -ne $Expected) { throw "$Name expected=$Expected actual=$Actual" }
    $script:testCount++
}
function Make-Bucket($Used = 0, $Window = 300, $Weekly = 20) {
    [pscustomobject]@{
        primary = [pscustomobject]@{ usedPercent = $Used; windowDurationMins = $Window; resetsAt = 20000 }
        secondary = [pscustomobject]@{ usedPercent = $Weekly }
        rateLimitReachedType = $null
    }
}
$tokens = $null
$errorsFound = $null
$null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $project 'monitor.ps1'), [ref]$tokens, [ref]$errorsFound)
Assert-Equal $errorsFound.Count 0 'Parse'
Assert-Equal (Get-SendDecision (Make-Bucket 0) $null 1000) 'send' 'Unused sends'
Assert-Equal (Get-SendDecision (Make-Bucket 1) $null 1000) 'quota-in-use' 'Used waits'
Assert-Equal (Get-SendDecision (Make-Bucket 0.01) $null 1000) 'quota-in-use' 'Fraction waits'
Assert-Equal (Get-SendDecision (Make-Bucket -1) $null 1000) 'quota-in-use' 'Negative fails closed'
Assert-Equal (Get-SendDecision (Make-Bucket $null) $null 1000) 'missing-quota' 'Null usage fails closed'
Assert-Equal (Get-SendDecision ([pscustomobject]@{}) $null 1000) 'missing-quota' 'Missing primary fails closed'
Assert-Equal (Get-SendDecision (Make-Bucket 0 60) $null 1000) 'unexpected-window' 'Other window fails closed'
Assert-Equal (Get-SendDecision (Make-Bucket 0 300 100) $null 1000) 'weekly-limit' 'Weekly exhausted waits'
$reached = Make-Bucket
$reached.rateLimitReachedType = 'hard_limit'
Assert-Equal (Get-SendDecision $reached $null 1000) 'limit-reached' 'Service limit waits'
Assert-Equal (Get-SendDecision (Make-Bucket) @{ blockUntil = 2000 } 1000) 'already-attempted' 'Guard waits'
Assert-Equal (Get-SendDecision (Make-Bucket) @{ blockUntil = 1000 } 1000) 'send' 'Expired guard releases'

# A native fixture removes Python launcher/alias differences from PowerShell tests.
$null = [IO.Directory]::CreateDirectory($testRoot)
$fakeExecutable = Join-Path $testRoot 'fake-codex.exe'
$fixtureSource = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
public static class FakeCodex {
    public static int Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = new UTF8Encoding(false);
        if (args.Length > 0 && args[0] == "app-server") {
            JavaScriptSerializer json = new JavaScriptSerializer();
            string line;
            while ((line = Console.ReadLine()) != null) {
                Dictionary<string, object> request = json.Deserialize<Dictionary<string, object>>(line);
                string method = (string)request["method"];
                if (method == "initialized") continue;
                Console.WriteLine(json.Serialize(new { method = "test/notification", @params = new { } }));
                object result;
                if (method == "initialize") result = new { userAgent = "fixture" };
                else if (method == "account/read") result = new { account = new { type = "chatgpt", email = "fixture@example.invalid" } };
                else if (method == "account/rateLimits/read") result = new {
                    rateLimitsByLimitId = new Dictionary<string, object> {
                        { "other", new { primary = new { usedPercent = 0, windowDurationMins = 60 } } },
                        { "codex", new { primary = new { usedPercent = 0, windowDurationMins = 300, resetsAt = 20000 }, secondary = new { usedPercent = 20 } } }
                    }
                };
                else return 2;
                Console.WriteLine(json.Serialize(new { id = request["id"], result = result }));
            }
            return 0;
        }
        if (args.Contains("--help")) {
            Console.WriteLine("--ignore-user-config --ephemeral"); return 0;
        }
        if (!args.Contains("forced_login_method=chatgpt") ||
            !args.Contains("read-only") || !args.Contains("--ignore-user-config")) return 2;
        string input = Console.ReadLine();
        string hello = "\u4f60\u597d";
        if (input == null || !input.Contains(hello)) return 3;
        Console.WriteLine(hello); return 0;
    }
}
'@
Add-Type -TypeDefinition $fixtureSource -Language CSharp -ReferencedAssemblies 'System.Web.Extensions','System.Core' -OutputAssembly $fakeExecutable -OutputType ConsoleApplication

# Real process I/O, with a local fake app server. It sends a notification before
# matching RPC replies and includes an unrelated usage bucket before Codex.
$originalProcess = (Get-Item Function:Start-CodexProcess).ScriptBlock
function Start-CodexProcess([string]$Executable, [string[]]$Arguments) {
    & $originalProcess $fakeExecutable $Arguments
}
$snapshot = Get-AccountSnapshot 'unused'
Assert-Equal $snapshot.Bucket.primary.windowDurationMins 300 'Select Codex bucket'
Assert-Equal $snapshot.Bucket.primary.usedPercent 0 'RPC quota value'
Assert-Equal $snapshot.AccountKey.Length 64 'Identity hashed'

# Full worker decision and write-before-send behavior without any model request.
function Find-Codex { return 'fake.exe' }
function Get-AccountSnapshot([string]$Executable) {
    return [pscustomobject]@{ AccountKey = 'unit-test-account'; Bucket = (Make-Bucket) }
}
$script:sendCount = 0
function Invoke-Hello([string]$Executable) {
    $guard = Get-Content -LiteralPath (Join-Path $script:Root 'state-unit-test-account.json') -Raw | ConvertFrom-Json
    Assert-Equal $guard.outcome 'attempted' 'Guard saved before model invocation'
    $script:sendCount++
}
$script:Root = Join-Path $testRoot ('case-' + [guid]::NewGuid().ToString('N'))
Invoke-Monitor -ReadOnly
Assert-Equal $script:sendCount 0 'Read-only never sends'
Assert-Equal (Test-Path -LiteralPath (Join-Path $script:Root 'state-unit-test-account.json')) $false 'Read-only writes no guard'
Invoke-Monitor
Invoke-Monitor
Assert-Equal $script:sendCount 1 'Two runs greet once even if usage still rounds to zero'
$guardFile = Join-Path $script:Root 'state-unit-test-account.json'
$saved = Get-Content -LiteralPath $guardFile -Raw | ConvertFrom-Json
Assert-Equal $saved.outcome 'completed' 'Successful completion persisted'

# Simulate an ambiguous failure after a model request could have been accepted.
$script:Root = Join-Path $testRoot ('case-' + [guid]::NewGuid().ToString('N'))
function Invoke-Hello([string]$Executable) { $script:sendCount++; throw 'Simulated network error after send.' }
try { Invoke-Monitor } catch { }
Invoke-Monitor
Assert-Equal $script:sendCount 2 'Ambiguous error never triggers a second attempt'

# Simulate an offline quota read. It must not mark this window attempted.
$script:Root = Join-Path $testRoot ('case-' + [guid]::NewGuid().ToString('N'))
function Get-AccountSnapshot([string]$Executable) { throw 'Simulated offline query.' }
try { Invoke-Monitor } catch { }
Assert-Equal (Test-Path -LiteralPath (Join-Path $script:Root 'state-unit-test-account.json')) $false 'Offline quota read writes no guard'

# Exercise the real greeting subprocess implementation using the native fixture.
# This checks quoting, UTF-8 stdin, required flags, and exact reply handling.
Set-Item Function:Start-CodexProcess $originalProcess
& $originalHello $fakeExecutable
Assert-Equal $true $true 'Real greeting subprocess with native fixture'

# Build, but do not register, the exact Task Scheduler objects used by setup.
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$onLogon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden'
$taskFixture = New-ScheduledTask -Action $action -Trigger @($trigger, $onLogon) -Settings $settings -Principal $principal
Assert-Equal $taskFixture.Triggers.Count 2 'Timed and logon triggers'
Assert-Equal $taskFixture.Triggers[0].Repetition.Interval 'PT5M' 'Five-minute repetition'
Assert-Equal ([string]$taskFixture.Triggers[0].Repetition.Duration) '' 'Repetition does not expire'
Assert-Equal $taskFixture.Settings.StartWhenAvailable $true 'Resume missed checks'
Write-Host ('PASS: ' + $script:testCount + ' checks; zero actual model requests; zero scheduled tasks registered.')
