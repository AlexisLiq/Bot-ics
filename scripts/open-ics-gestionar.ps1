param(
    [string]$WindowTitleHint = "Internet Collection System",
    [int]$TimeoutMs = 12000,
    [int]$PollMs = 120,
    [int]$CommandId = 10057
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_ics-window-common.ps1")

if (-not (Initialize-IcsWindowCommonType)) {
    [pscustomobject]@{
        ok = $false
        windowFound = $false
        menuSent = $false
        error = "Add-Type Win32IcsWindowCommon failed: $(Get-IcsWindowCommonInitError)"
    } | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

$menuSource = @"
using System;
using System.Runtime.InteropServices;

public static class Win32IcsMenuOps
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool PostMessageW(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    private const uint WM_COMMAND = 0x0111;

    public static bool PostMenuCommand(long hwnd, int commandId)
    {
        if (commandId <= 0) return false;
        try { return PostMessageW(new IntPtr(hwnd), WM_COMMAND, new IntPtr(commandId), IntPtr.Zero); }
        catch { return false; }
    }
}
"@

if (-not ("Win32IcsMenuOps" -as [type])) {
    try {
        Add-Type -TypeDefinition $menuSource -Language CSharp -ErrorAction Stop
    } catch {
        [pscustomobject]@{
            ok = $false
            windowFound = $false
            menuSent = $false
            error = "Add-Type Win32IcsMenuOps failed: $($_.Exception.Message)"
        } | ConvertTo-Json -Depth 4 -Compress
        exit 0
    }
}

$result = [ordered]@{
    ok = $false
    windowFound = $false
    menuSent = $false
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
    if ($hwnd -ne 0 -and [Win32IcsMenuOps]::PostMenuCommand($hwnd, [int]$CommandId)) {
        $result.ok = $true
        $result.menuSent = $true
        break
    }

    Start-Sleep -Milliseconds $PollMs
}

if (-not $result.windowFound) {
    $result.error = "No se encontro la ventana principal de ICS dentro del timeout."
} elseif (-not $result.menuSent) {
    $result.error = "No se pudo invocar Gestion -> Gestionar por WM_COMMAND."
}

$result | ConvertTo-Json -Depth 5 -Compress
