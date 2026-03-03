param(
    [string]$MainWindowHwnd,
    [string]$TargetProcessName = "Ejecutivo Singular",
    [int]$TimeoutMs = 20000,
    [int]$PollMs = 250,
    [int]$StepDelayMs = 400
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

$win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32PostSearch
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")] private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);

    private const uint BM_CLICK = 0x00F5;
    private const int SW_RESTORE = 9;

    public sealed class TopWindowInfo
    {
        public long Hwnd { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
    }

    public sealed class ChildInfo
    {
        public long Hwnd { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
    }

    public static bool WindowExists(long hwnd)
    {
        try { return IsWindow(new IntPtr(hwnd)); } catch { return false; }
    }

    public static bool ActivateWindow(long hwnd)
    {
        try
        {
            var h = new IntPtr(hwnd);
            ShowWindow(h, SW_RESTORE);
            return SetForegroundWindow(h);
        }
        catch { return false; }
    }

    public static uint GetWindowPid(long hwnd)
    {
        try
        {
            uint pid;
            GetWindowThreadProcessId(new IntPtr(hwnd), out pid);
            return pid;
        }
        catch { return 0; }
    }

    public static List<TopWindowInfo> SnapshotTopWindows()
    {
        var list = new List<TopWindowInfo>();
        EnumWindows((hWnd, lParam) =>
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            list.Add(new TopWindowInfo
            {
                Hwnd = hWnd.ToInt64(),
                ProcessId = pid,
                Title = GetText(hWnd),
                ClassName = GetClass(hWnd),
                Visible = IsWindowVisible(hWnd)
            });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static List<ChildInfo> SnapshotChildren(long rootHwnd)
    {
        var list = new List<ChildInfo>();
        var root = new IntPtr(rootHwnd);
        EnumChildWindows(root, (child, lParam) =>
        {
            list.Add(new ChildInfo
            {
                Hwnd = child.ToInt64(),
                Title = GetText(child),
                ClassName = GetClass(child),
                Visible = IsWindowVisible(child)
            });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static bool Click(long hwnd)
    {
        try { return SendMessage(new IntPtr(hwnd), BM_CLICK, IntPtr.Zero, IntPtr.Zero) != IntPtr.Zero || true; }
        catch { return false; }
    }

    private static string GetText(IntPtr hWnd)
    {
        int len = 0;
        try { len = GetWindowTextLengthW(hWnd); } catch { len = 0; }
        if (len < 0) len = 0;
        var sb = new StringBuilder(Math.Max(1, len + 2));
        GetWindowTextW(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    private static string GetClass(IntPtr hWnd)
    {
        var sb = new StringBuilder(256);
        GetClassNameW(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }
}
"@

function Find-FirstButtonByTokens {
    param(
        $Children,
        [string[]]$Tokens
    )

    foreach ($child in @($Children)) {
        if (-not $child.Visible) { continue }
        $title = Normalize-UiText $child.Title
        if (-not $title) { continue }

        foreach ($token in $Tokens) {
            $needle = Normalize-UiText $token
            if (-not $needle) { continue }
            if ($title -eq $needle -or $title.Contains($needle)) {
                return $child
            }
        }
    }

    return $null
}

$result = [ordered]@{
    ok = $false
    timedOut = $false
    errorModalSeen = $false
    errorModalClosed = $false
    ejecutivoSingularPresent = $false
    agregarProcesoClicked = $false
    procesoCreated = $false
    error = $null
}

try {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Stop"
    Add-Type -TypeDefinition $win32Source -Language CSharp
    $ErrorActionPreference = $oldEap
} catch {
    $result.error = "Add-Type Win32PostSearch failed: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$mainHwnd = Parse-Handle $MainWindowHwnd
if ($mainHwnd -eq 0 -or -not [Win32PostSearch]::WindowExists($mainHwnd)) {
    $result.error = "Handle invalido para ventana principal de ICS."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$mainPid = [Win32PostSearch]::GetWindowPid($mainHwnd)
if ($mainPid -eq 0) {
    $result.error = "No se pudo resolver PID de ventana principal."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

[void][Win32PostSearch]::ActivateWindow($mainHwnd)
$deadline = (Get-Date).AddMilliseconds($TimeoutMs)

while ((Get-Date) -lt $deadline) {
    $topWindows = [Win32PostSearch]::SnapshotTopWindows()

    $errorModal = $topWindows | Where-Object {
        $_.Visible -and
        [int]$_.ProcessId -eq [int]$mainPid -and
        [string]$_.Hwnd -ne [string]$mainHwnd -and
        (
            (Normalize-UiText $_.Title).Contains("error") -or
            (Normalize-UiText $_.Title).Contains("advertencia") -or
            (Normalize-UiText $_.Title).Contains("atencion") -or
            (Normalize-UiText $_.Title).Contains("mensaje")
        )
    } | Select-Object -First 1

    if ($errorModal) {
        $result.errorModalSeen = $true
        [void][Win32PostSearch]::ActivateWindow([int64]$errorModal.Hwnd)
        Start-Sleep -Milliseconds 120

        $children = [Win32PostSearch]::SnapshotChildren([int64]$errorModal.Hwnd)
        $closeBtn = Find-FirstButtonByTokens -Children $children -Tokens @("Aceptar", "OK", "Cerrar", "Si")
        if ($closeBtn) {
            $result.errorModalClosed = [Win32PostSearch]::Click([int64]$closeBtn.Hwnd)
        } else {
            $result.errorModalClosed = $false
        }

        $result.ok = $result.errorModalClosed
        if (-not $result.ok) {
            $result.error = "Se detecto modal de error pero no se pudo cerrar."
        }
        $result | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }

    Start-Sleep -Milliseconds $PollMs
}

# Sin modal de error: seguimos el flujo sin agregar proceso.
$result.ok = $true
$result.timedOut = $false
$result | ConvertTo-Json -Depth 6 -Compress
