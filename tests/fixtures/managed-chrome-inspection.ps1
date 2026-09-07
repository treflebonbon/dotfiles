param([string]$ScriptPath, [string]$FailedQuery, [string]$Role)

function Test-Path { return $true }
function Get-Item { return @{ FullName = 'C:\Chrome\chrome.exe' } }
function Get-CimInstance {
    [CmdletBinding()]
    param([string]$ClassName, [string]$Filter)
    if ($FailedQuery -eq 'process') { Write-Error 'process query unavailable' }
}
function Get-NetTCPConnection {
    [CmdletBinding()]
    param([string]$State, [string]$LocalAddress, [int]$LocalPort)
    if ($FailedQuery -eq 'port') { Write-Error 'port query unavailable' }
}

if ($Role -eq 'dogfood') {
    & $ScriptPath -Action Inspect -RunId inspection-test -ProfileDir 'C:\test-profile' -DebugPort 19330
}
else {
    & $ScriptPath -Action Inspect
}
