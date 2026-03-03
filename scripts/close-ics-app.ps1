param(
    [string]$WindowTitleHint = "Internet Collection System",
    [int]$TimeoutMs = 5000,
    [int]$PollMs = 150
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_ics-window-common.ps1")

if (-not (Initialize-IcsWindowCommonType)) {
    [pscustomobject]@{
        ok = $false
        windowFound = $false
        closed = $false
        error = "Add-Type Win32IcsWindowCommon failed: $(Get-IcsWindowCommonInitError)"
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

$closeSource = @"
using System;
using System.Runtime.InteropServices;

public static class Win32IcsCloseOps
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool PostMessageW(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    private const uint WM_CLOSE = 0x0010;

    public static bool CloseWindow(long hwnd)
    {
        try { return PostMessageW(new IntPtr(hwnd), WM_CLOSE, IntPtr.Zero, IntPtr.Zero); }
        catch { return false; }
    }
}
"@

if (-not ("Win32IcsCloseOps" -as [type])) {
    try {
        Add-Type -TypeDefinition $closeSource -Language CSharp -ErrorAction Stop
    } catch {
        [pscustomobject]@{
            ok = $false
            windowFound = $false
            closed = $false
            error = "Add-Type Win32IcsCloseOps failed: $($_.Exception.Message)"
        } | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }
}

$result = [ordered]@{
    ok = $false
    windowFound = $false
    closed = $false
    window = $null
    error = $null
}

$deadline = (Get-Date).AddMilliseconds($TimeoutMs)
while ((Get-Date) -lt $deadline) {
    $window = Find-IcsWindow -WindowTitleHint $WindowTitleHint
    if (-not $window) {
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    $result.windowFound = $true
    $result.window = $window

    $hwnd = 0
    try { $hwnd = [int64]$window.hwnd } catch { $hwnd = 0 }
    if ($hwnd -eq 0) {
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    $result.closed = [Win32IcsCloseOps]::CloseWindow($hwnd)
    $result.ok = $result.closed
    break
}

if (-not $result.windowFound) {
    $result.error = "No se encontro ventana principal de ICS para cerrar."
} elseif (-not $result.closed) {
    $result.error = "No se pudo enviar WM_CLOSE a la ventana de ICS."
}

$result | ConvertTo-Json -Depth 5 -Compress
