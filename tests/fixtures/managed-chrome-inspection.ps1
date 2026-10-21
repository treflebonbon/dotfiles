param([string]$ScriptPath, [string]$Scenario, [string]$Role)

function Test-Path { return $true }
function Get-Item { return @{ FullName = 'C:\Chrome\chrome.exe' } }
function Get-CimInstance {
    [CmdletBinding()]
    param([string]$ClassName, [string]$Filter, [string]$Namespace)
    if ($ClassName -eq 'Win32_Process') {
        if ($Scenario -eq 'process') { Write-Error 'process query unavailable' }
        if ($Scenario -eq 'managed') {
            return @{
                ProcessId = 4242
                ExecutablePath = 'C:\Chrome\chrome.exe'
                CommandLine = 'chrome.exe --user-data-dir=C:\test-profile --headless --remote-debugging-address=127.0.0.1 --remote-debugging-port=19330'
            }
        }
        return
    }
    if ($ClassName -ne 'MSFT_NetTCPConnection' -or $Namespace -ne 'root/StandardCimv2' -or
        $Filter -notmatch '\bState\s*=\s*2\b' -or
        $Filter -notmatch "\bLocalAddress\s*=\s*'127\.0\.0\.1'" -or
        $Filter -notmatch '\bLocalPort\s*=\s*19330\b') {
        throw 'TCP query must filter the selected loopback listener in the provider'
    }
    if ($Scenario -eq 'port') { Write-Error 'port query unavailable' }
    if ($Scenario -in @('conflict', 'managed')) { return @{ OwningProcess = 4242 } }
}
function Get-NetTCPConnection {
    [CmdletBinding()]
    param([string]$State, [string]$LocalAddress, [int]$LocalPort)
    throw 'Unfiltered TCP enumeration is forbidden'
}

if ($Role -eq 'dogfood') {
    & $ScriptPath -Action Inspect -RunId inspection-test -ProfileDir 'C:\test-profile' -DebugPort 19330
}
else {
    & $ScriptPath -Action Inspect -ProfileDir 'C:\test-profile' -DebugPort 19330
}
