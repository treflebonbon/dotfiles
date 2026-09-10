param([ValidateRange(1, 120)][int]$Seconds = 90)
$ErrorActionPreference = "Stop"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FocusProbe {
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
}
'@
$until = [DateTime]::UtcNow.AddSeconds($Seconds)
do {
    $point = New-Object FocusProbe+POINT
    $ok = [FocusProbe]::GetCursorPos([ref]$point)
    @{ time = [DateTime]::UtcNow.ToString("o"); foreground = [FocusProbe]::GetForegroundWindow().ToInt64(); cursorOk = $ok; x = $point.X; y = $point.Y } | ConvertTo-Json -Compress
    Start-Sleep -Milliseconds 200
} while ([DateTime]::UtcNow -lt $until)
