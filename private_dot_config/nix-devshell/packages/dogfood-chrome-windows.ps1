param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Resolve", "Inspect", "Start", "Cleanup")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [ValidateSet("headless", "headed")]
    [string]$Mode = "headless",

    [int]$DebugPort = 0,

    [string]$ProfileDir,

    [string]$ExtensionPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$DebugAddress = "127.0.0.1"
if (-not $ProfileDir) {
    $ProfileDir = Join-Path ([IO.Path]::GetTempPath()) "aiakos-dogfood-$RunId"
}

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

function Get-ChromeProcesses {
    @(
        Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match [Regex]::Escape($ProfileDir) }
    )
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

if ($Action -eq "Resolve") {
    Write-Output $ProfileDir
    exit 0
}

if ($Action -eq "Cleanup") {
    $ManagedProcesses = @(Get-ChromeProcesses)
    foreach ($Process in $ManagedProcesses) {
        Stop-Process -Id ([int]$Process.ProcessId) -Force -ErrorAction SilentlyContinue
    }
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        if (@(Get-ChromeProcesses).Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (@(Get-ChromeProcesses).Count -gt 0) {
        throw "Managed Chrome did not exit for profile '$ProfileDir'."
    }
    if (Test-Path -LiteralPath $ProfileDir) {
        Remove-Item -LiteralPath $ProfileDir -Recurse -Force -ErrorAction Stop
    }
    exit 0
}

$Chrome = Find-ChromeExecutable
if (-not $Chrome) {
    Write-Output "chrome-missing"
    exit 0
}

$ProfileProcesses = @(Get-ChromeProcesses)
$Listeners = @(
    if ($DebugPort -gt 0) {
        Get-NetTCPConnection -State Listen -LocalAddress $DebugAddress -LocalPort $DebugPort -ErrorAction SilentlyContinue
    }
)

if ($ProfileProcesses.Count -gt 0) {
    $MatchingProcess = $ProfileProcesses | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.Equals($Chrome, [StringComparison]::OrdinalIgnoreCase) -and
        ($DebugPort -eq 0 -or $_.CommandLine -match "(?:^|\s)--remote-debugging-port=$DebugPort(?:\s|$)")
    } | Select-Object -First 1
    if ($MatchingProcess) {
        if ($DebugPort -eq 0 -or @($Listeners | Where-Object {
                [uint32]$_.OwningProcess -eq [uint32]$MatchingProcess.ProcessId
            }).Count -gt 0) {
            Write-Output (Format-ManagedState -Process $MatchingProcess)
        }
        elseif ($Listeners.Count -gt 0) {
            Write-Output "port-conflict:$($Listeners[0].OwningProcess)"
        }
        else {
            Write-Output (Format-ManagedState -Process $MatchingProcess)
        }
        exit 0
    }
    Write-Output "profile-conflict:$($ProfileProcesses[0].ProcessId)"
    exit 0
}

if ($Listeners.Count -gt 0) {
    Write-Output "port-conflict:$($Listeners[0].OwningProcess)"
    exit 0
}

if ($Action -eq "Inspect") {
    Write-Output "absent"
    exit 0
}

if ($DebugPort -le 0) {
    throw "Start requires a positive -DebugPort."
}

New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
$ChromeArguments = @(
    "--remote-debugging-address=$DebugAddress",
    "--remote-debugging-port=$DebugPort",
    "--remote-allow-origins=*",
    "--user-data-dir=$ProfileDir",
    "--no-first-run",
    "--no-default-browser-check",
    "about:blank"
)
if ($Mode -eq "headless") {
    $ChromeArguments = @("--headless=new") + $ChromeArguments
}
if ($ExtensionPath) {
    $ChromeArguments = @(
        "--disable-extensions-except=$ExtensionPath",
        "--load-extension=$ExtensionPath"
    ) + $ChromeArguments
}
Start-Process -FilePath $Chrome -ArgumentList $ChromeArguments | Out-Null
Write-Output "started"
