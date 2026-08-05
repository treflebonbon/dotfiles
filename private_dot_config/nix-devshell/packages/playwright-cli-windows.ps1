param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Inspect", "Start")]
    [string]$Action,

    [ValidateSet("headless", "headed")]
    [string]$Mode = "headless"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$DebugAddress = "127.0.0.1"
$DebugPort = 9222
$ProfileDir = Join-Path $env:LOCALAPPDATA "aiakos\playwright-cli\chrome-profile"

function Find-ChromeExecutable {
    $Candidates = @()
    if ($env:ProgramFiles) {
        $Candidates += Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"
    }
    if (${env:ProgramFiles(x86)}) {
        $Candidates += Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"
    }
    if ($env:LOCALAPPDATA) {
        $Candidates += Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe"
    }
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return (Get-Item -LiteralPath $Candidate).FullName
        }
    }
    return $null
}

function Format-ManagedState {
    param([object]$Process)

    $ProcessMode = if ($Process.CommandLine -match "(?:^|\s)--headless(?:=\S+)?(?:\s|$)") {
        "headless"
    }
    else {
        "headed"
    }
    return "managed:${ProcessMode}:$($Process.ProcessId)"
}

function Get-ChromeState {
    param([string]$ChromeExecutable)

    if (-not $ChromeExecutable) {
        return "chrome-missing"
    }

    $ChromeProcesses = @(
        Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction SilentlyContinue
    )
    $EscapedProfile = [Regex]::Escape($ProfileDir)
    $ProfilePattern = "--user-data-dir=(?:`"$EscapedProfile`"|$EscapedProfile)(?:\s|$)"
    $ProfileProcesses = @(
        $ChromeProcesses | Where-Object {
            $_.CommandLine -and $_.CommandLine -match $ProfilePattern
        }
    )
    $ManagedProcesses = @(
        $ProfileProcesses | Where-Object {
            $_.ExecutablePath -and
            $_.ExecutablePath.Equals($ChromeExecutable, [StringComparison]::OrdinalIgnoreCase) -and
            $_.CommandLine -notmatch "(?:^|\s)--type=" -and
            $_.CommandLine -match "(?:^|\s)--remote-debugging-address=$DebugAddress(?:\s|$)" -and
            $_.CommandLine -match "(?:^|\s)--remote-debugging-port=$DebugPort(?:\s|$)"
        }
    )
    $Listeners = @(
        Get-NetTCPConnection `
            -State Listen `
            -LocalAddress $DebugAddress `
            -LocalPort $DebugPort `
            -ErrorAction SilentlyContinue
    )

    if ($ManagedProcesses.Count -gt 0) {
        if ($Listeners.Count -eq 0) {
            return Format-ManagedState -Process $ManagedProcesses[0]
        }
        foreach ($Listener in $Listeners) {
            $ListenerProcessId = [uint32]$Listener.OwningProcess
            $ListenerProcess = $ManagedProcesses | Where-Object {
                [uint32]$_.ProcessId -eq $ListenerProcessId
            } | Select-Object -First 1
            if ($ListenerProcess) {
                return Format-ManagedState -Process $ListenerProcess
            }
        }
    }

    if ($Listeners.Count -gt 0) {
        return "port-conflict:$($Listeners[0].OwningProcess)"
    }
    if ($ProfileProcesses.Count -gt 0) {
        return "profile-conflict:$($ProfileProcesses[0].ProcessId)"
    }
    return "absent"
}

$Chrome = Find-ChromeExecutable
$State = Get-ChromeState -ChromeExecutable $Chrome

if ($Action -eq "Inspect") {
    Write-Output $State
    exit 0
}

if ($State -ne "absent") {
    Write-Output $State
    exit 0
}

New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
$ChromeArguments = @(
    "--remote-debugging-address=$DebugAddress"
    "--remote-debugging-port=$DebugPort"
    "--user-data-dir=`"$ProfileDir`""
    "--no-first-run"
    "--no-default-browser-check"
    "about:blank"
)
if ($Mode -eq "headless") {
    $ChromeArguments = @("--headless") + $ChromeArguments
}
$Arguments = $ChromeArguments -join " "
Start-Process -FilePath $Chrome -ArgumentList $Arguments | Out-Null
Write-Output "started"
