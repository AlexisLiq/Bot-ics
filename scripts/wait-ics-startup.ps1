param(
    [string]$WindowTitleHint = "Internet Collection System",
    [int]$TimeoutMs = 25000,
    [int]$PollMs = 250,
    [int]$StablePolls = 2
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

$win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32IcsStartupWatcher
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public sealed class TopWindowInfo
    {
        public long Hwnd { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
        public bool Iconic { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public static List<TopWindowInfo> SnapshotWindows()
    {
        var list = new List<TopWindowInfo>();
        EnumWindows((hWnd, lParam) =>
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);

            RECT r;
            bool hasRect = GetWindowRect(hWnd, out r);
            int width = hasRect ? Math.Max(0, r.Right - r.Left) : 0;
            int height = hasRect ? Math.Max(0, r.Bottom - r.Top) : 0;

            list.Add(new TopWindowInfo
            {
                Hwnd = hWnd.ToInt64(),
                ProcessId = pid,
                Title = GetText(hWnd),
                ClassName = GetClass(hWnd),
                Visible = IsWindowVisible(hWnd),
                Iconic = IsIconic(hWnd),
                Width = width,
                Height = height
            });
            return true;
        }, IntPtr.Zero);
        return list;
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

try {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Stop"
    Add-Type -TypeDefinition $win32Source -Language CSharp
    $ErrorActionPreference = $oldEap
} catch {
    [pscustomobject]@{
        ok = $false
        windowFound = $false
        ready = $false
        error = "Add-Type Win32IcsStartupWatcher failed: $($_.Exception.Message)"
    } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

function Find-IcsMainWindow {
    param([string]$TitleHint)

    $hintNorm = Normalize-UiText $TitleHint
    $snapshot = [Win32IcsStartupWatcher]::SnapshotWindows()

    $primary = foreach ($w in $snapshot) {
        if (-not $w.Visible -or $w.Iconic) { continue }
        if ($w.Width -lt 500 -or $w.Height -lt 300) { continue }

        $procName = Get-ProcessNameSafe -ProcId ([int]$w.ProcessId)
        $procNorm = Normalize-UiText $procName
        $titleNorm = Normalize-UiText $w.Title

        if (-not $procNorm.Contains("ics_client")) { continue }
        if (-not ($titleNorm.Contains("internet collection system") -or ($hintNorm -and $titleNorm.Contains($hintNorm)))) {
            continue
        }

        [pscustomobject]@{
            hwnd = [string]$w.Hwnd
            processId = [int]$w.ProcessId
            processName = $procName
            title = [string]$w.Title
            className = [string]$w.ClassName
            width = [int]$w.Width
            height = [int]$w.Height
        }
    }

    if (-not $primary) { return $null }

    return $primary | Sort-Object `
        @{ Expression = { -not (Normalize-UiText $_.processName).Contains("ics_client") } }, `
        @{ Expression = { ([int64]$_.width * [int64]$_.height) * -1 } } | Select-Object -First 1
}

function Get-BlockingStartupWindows {
    param($MainWindow)

    $snapshot = [Win32IcsStartupWatcher]::SnapshotWindows()
    $mainPid = [int]$MainWindow.processId
    $mainHwnd = [string]$MainWindow.hwnd
    $mainArea = [int64]([Math]::Max(1, ([int64]$MainWindow.width * [int64]$MainWindow.height)))

    $blocking = foreach ($w in $snapshot) {
        if (-not $w.Visible -or $w.Iconic) { continue }
        if ([string]$w.Hwnd -eq $mainHwnd) { continue }
        if ([int]$w.ProcessId -ne $mainPid) { continue }

        $titleNorm = Normalize-UiText $w.Title
        $classNorm = Normalize-UiText $w.ClassName
        $area = [int64]([int64]$w.Width * [int64]$w.Height)

        $isBlocking =
            $titleNorm -eq "logon" -or
            $titleNorm.Contains("tratando de conectarse") -or
            $classNorm.Contains("sunawtdialog") -or
            (
                $titleNorm.Contains("internet collection system") -and
                $area -gt 0 -and
                $area -lt ($mainArea * 0.9)
            )

        if (-not $isBlocking) { continue }

        [pscustomobject]@{
            hwnd = [string]$w.Hwnd
            process = Get-ProcessNameSafe -ProcId ([int]$w.ProcessId)
            pid = [int]$w.ProcessId
            title = [string]$w.Title
            className = [string]$w.ClassName
            width = [int]$w.Width
            height = [int]$w.Height
        }
    }

    return @($blocking)
}

$result = [ordered]@{
    ok = $false
    windowFound = $false
    ready = $false
    window = $null
    waitedMs = 0
    stablePollsRequired = [Math]::Max(1, $StablePolls)
    blockingObserved = @()
    error = $null
}

$startAt = Get-Date
$deadline = $startAt.AddMilliseconds($TimeoutMs)
$mainWindow = $null

while ((Get-Date) -lt $deadline) {
    $mainWindow = Find-IcsMainWindow -TitleHint $WindowTitleHint
    if ($null -ne $mainWindow) { break }
    Start-Sleep -Milliseconds $PollMs
}

if ($null -eq $mainWindow) {
    $result.error = "No se encontro la ventana principal de ICS dentro del timeout."
    $result.waitedMs = [int]((Get-Date) - $startAt).TotalMilliseconds
    $result | ConvertTo-Json -Depth 7 -Compress
    exit 0
}

$result.windowFound = $true
$result.window = $mainWindow

$stableCount = 0
$lastBlocking = @()

while ((Get-Date) -lt $deadline) {
    $blocking = Get-BlockingStartupWindows -MainWindow $mainWindow
    $lastBlocking = $blocking

    if ($blocking.Count -eq 0) {
        $stableCount++
    } else {
        $stableCount = 0
    }

    if ($stableCount -ge $result.stablePollsRequired) {
        $result.ok = $true
        $result.ready = $true
        break
    }

    Start-Sleep -Milliseconds $PollMs
}

$result.waitedMs = [int]((Get-Date) - $startAt).TotalMilliseconds

if (-not $result.ready) {
    $result.blockingObserved = @($lastBlocking | Select-Object -First 5)
    $titles = @($result.blockingObserved | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_.title)) { $_.title } else { "<sin titulo>" }
    })
    $detail = if ($titles.Count -gt 0) { $titles -join " || " } else { "sin detalle" }
    $result.error = "ICS aun muestra ventanas de inicializacion. Detectadas: $detail"
}

$result | ConvertTo-Json -Depth 8 -Compress
