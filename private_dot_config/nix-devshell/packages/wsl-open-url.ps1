param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url
)

$ErrorActionPreference = 'Stop'

if ($Url -notmatch '^(?i:https?)://') {
    Write-Error 'Only HTTP(S) URLs may be routed through the Windows default handler.'
    exit 2
}

try {
    Start-Process -FilePath $Url -ErrorAction Stop | Out-Null
}
catch {
    Write-Error ("Could not open URL with the Windows default handler: {0}" -f $_.Exception.Message)
    exit 1
}
