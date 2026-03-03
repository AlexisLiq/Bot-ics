param(
    [string]$WindowTitleHint = "Internet Collection System",
    [int]$TimeoutMs = 60000,
    [int]$PollMs = 500
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

$win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32IcsControlFinder
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
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
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
        public bool Visible { get; set; }
        public bool Iconic { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public sealed class ChildWindowInfo
    {
        public long Hwnd { get; set; }
        public long ParentHwnd { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Right { get; set; }
        public int Bottom { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public static List<TopWindowInfo> SnapshotTopWindows()
    {
        var list = new List<TopWindowInfo>();
        EnumWindows((hWnd, lParam) =>
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            RECT r;
            bool hasRect = GetWindowRect(hWnd, out r);
            list.Add(new TopWindowInfo
            {
                Hwnd = hWnd.ToInt64(),
                ProcessId = pid,
                Title = GetText(hWnd),
                Visible = IsWindowVisible(hWnd),
                Iconic = IsIconic(hWnd),
                Width = hasRect ? Math.Max(0, r.Right - r.Left) : 0,
                Height = hasRect ? Math.Max(0, r.Bottom - r.Top) : 0
            });
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static List<ChildWindowInfo> SnapshotDescendants(long rootHwnd, int maxNodes)
    {
        var list = new List<ChildWindowInfo>();
        var root = new IntPtr(rootHwnd);
        EnumChildWindows(root, (child, lParam) =>
        {
            if (list.Count >= maxNodes) return false;

            RECT r;
            bool hasRect = GetWindowRect(child, out r);
            list.Add(new ChildWindowInfo
            {
                Hwnd = child.ToInt64(),
                ParentHwnd = rootHwnd,
                Title = GetText(child),
                ClassName = GetClass(child),
                Visible = IsWindowVisible(child),
                Left = hasRect ? r.Left : 0,
                Top = hasRect ? r.Top : 0,
                Right = hasRect ? r.Right : 0,
                Bottom = hasRect ? r.Bottom : 0,
                Width = hasRect ? Math.Max(0, r.Right - r.Left) : 0,
                Height = hasRect ? Math.Max(0, r.Bottom - r.Top) : 0
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
        found = @{
            identificationInput = $false
            buscarButton = $false
            legalTab = $false
        }
        error = "Add-Type Win32IcsControlFinder failed: $($_.Exception.Message)"
    } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

function To-ControlSummary {
    param($Control)
    if ($null -eq $Control) { return $null }
    return [pscustomobject]@{
        hwnd = [string]$Control.hwnd
        title = [string]$Control.title
        className = [string]$Control.className
        left = [int]$Control.left
        top = [int]$Control.top
        right = [int]$Control.right
        bottom = [int]$Control.bottom
        width = [int]$Control.width
        height = [int]$Control.height
    }
}

function Find-IcsMainWindow {
    param([string]$TitleHint)

    $hint = Normalize-UiText $TitleHint
    $wins = [Win32IcsControlFinder]::SnapshotTopWindows()

    $candidates = foreach ($w in $wins) {
        if (-not $w.Visible -or $w.Iconic) { continue }
        if ($w.Width -lt 500 -or $w.Height -lt 300) { continue }
        if ([string]::IsNullOrWhiteSpace($w.Title)) { continue }

        $title = Normalize-UiText $w.Title
        if (-not ($title.Contains("internet collection system") -or ($hint -and $title.Contains($hint)))) { continue }

        $proc = Get-ProcessNameSafe -ProcId ([int]$w.ProcessId)
        $procNorm = Normalize-UiText $proc
        if ($procNorm -eq "java" -or $procNorm.Contains("javaws") -or $procNorm.Contains("javaw") -or $procNorm.Contains("jp2launcher")) {
            continue
        }

        [pscustomobject]@{
            hwnd = [string]$w.Hwnd
            processId = [int]$w.ProcessId
            processName = $proc
            title = [string]$w.Title
            isIcsProcess = $procNorm.Contains("ics_client")
        }
    }

    if (-not $candidates) { return $null }
    return $candidates | Sort-Object @{ Expression = { -not $_.isIcsProcess } }, @{ Expression = { $_.title.Length * -1 } } | Select-Object -First 1
}

function Get-RootCandidates {
    param($MainWindow)

    $wins = [Win32IcsControlFinder]::SnapshotTopWindows()
    $mainPid = [int]$MainWindow.processId
    $roots = @($MainWindow)

    foreach ($w in $wins) {
        if (-not $w.Visible -or $w.Iconic) { continue }
        if ([int]$w.ProcessId -ne $mainPid) { continue }
        if ([string]$w.Hwnd -eq [string]$MainWindow.hwnd) { continue }
        if ($w.Width -lt 220 -or $w.Height -lt 110) { continue }

        $title = Normalize-UiText $w.Title
        if ($title.Contains("iniciando aplicacion") -or $title.Contains("tratando de conectarse") -or $title.Contains("starting application")) {
            continue
        }

        $proc = Get-ProcessNameSafe -ProcId ([int]$w.ProcessId)
        $roots += [pscustomobject]@{
            hwnd = [string]$w.Hwnd
            processId = [int]$w.ProcessId
            processName = $proc
            title = [string]$w.Title
            isIcsProcess = (Normalize-UiText $proc).Contains("ics_client")
        }
    }

    $seen = @{}
    $unique = @()
    foreach ($r in $roots) {
        $key = [string]$r.hwnd
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique += $r
    }

    return $unique | Sort-Object @{ Expression = { -not (Normalize-UiText $_.title).Contains("informacion del deudor") } }, @{ Expression = { -not $_.isIcsProcess } }
}

function Find-ControlsInRoot {
    param($Root)

    $rootHwnd = 0
    try { $rootHwnd = [int64]$Root.hwnd } catch { $rootHwnd = 0 }
    if ($rootHwnd -eq 0) {
        return [pscustomobject]@{
            root = $Root
            legalTab = $null
            buscarButton = $null
            identificationInput = $null
            foundCount = 0
        }
    }

    $raw = [Win32IcsControlFinder]::SnapshotDescendants($rootHwnd, 2000)
    $controls = foreach ($c in $raw) {
        [pscustomobject]@{
            hwnd = [string]$c.Hwnd
            parentHwnd = [string]$c.ParentHwnd
            title = [string]$c.Title
            titleNorm = Normalize-UiText $c.Title
            className = [string]$c.ClassName
            classNorm = Normalize-UiText $c.ClassName
            left = [int]$c.Left
            top = [int]$c.Top
            right = [int]$c.Right
            bottom = [int]$c.Bottom
            width = [int]$c.Width
            height = [int]$c.Height
        }
    }

    $text = @($controls | Where-Object { -not [string]::IsNullOrWhiteSpace($_.titleNorm) })
    $legalCandidates = @($text | Where-Object { $_.titleNorm -eq "legal" -or $_.titleNorm -like "*legal*" })
    $buscar = $text | Where-Object { $_.titleNorm -eq "buscar" -or $_.titleNorm -like "*buscar*" } | Select-Object -First 1
    $idLabel = $text | Where-Object { $_.titleNorm -like "*identificacion*" } | Select-Object -First 1

    $legal = $null
    if ($legalCandidates.Count -gt 0) {
        if ($buscar) {
            $alignedWithBuscar = @($legalCandidates | Where-Object {
                [Math]::Abs([int]$_.top - [int]$buscar.top) -le 45
            } | Sort-Object @{ Expression = { [Math]::Abs([int]$_.left - [int]$buscar.left) } }, @{ Expression = { $_.left } })

            if ($alignedWithBuscar.Count -gt 0) {
                $legal = $alignedWithBuscar[0]
            }
        }

        if (($null -eq $legal) -and $idLabel) {
            $alignedWithId = @($legalCandidates | Where-Object {
                [Math]::Abs([int]$_.top - [int]$idLabel.top) -le 70 -and $_.left -gt $idLabel.left
            } | Sort-Object @{ Expression = { $_.left } })

            if ($alignedWithId.Count -gt 0) {
                $legal = $alignedWithId[0]
            }
        }

        if ($null -eq $legal) {
            $legal = $legalCandidates | Sort-Object @{ Expression = { $_.top } }, @{ Expression = { $_.left } } | Select-Object -First 1
        }
    }

    $edits = @($controls | Where-Object {
        ($_.classNorm.Contains("edit") -or $_.classNorm.Contains("textbox") -or $_.classNorm.Contains("textfield")) -and
        $_.width -ge 50 -and $_.height -ge 12 -and $_.height -le 60
    })

    $input = $null
    if ($idLabel -and $edits.Count -gt 0) {
        $row = @($edits | Where-Object {
            $_.left -ge ($idLabel.right - 10) -and $_.top -le ($idLabel.bottom + 10) -and $_.bottom -ge ($idLabel.top - 10)
        } | Sort-Object @{ Expression = { $_.left } })
        if ($row.Count -gt 0) { $input = $row[0] }
    }

    if (($null -eq $input) -and $buscar -and $edits.Count -gt 0) {
        $leftOfBuscar = @($edits | Where-Object {
            $_.right -le ($buscar.left + 10) -and $_.top -le ($buscar.bottom + 10) -and $_.bottom -ge ($buscar.top - 10)
        } | Sort-Object @{ Expression = { $_.right } } -Descending)
        if ($leftOfBuscar.Count -gt 0) { $input = $leftOfBuscar[0] }
    }

    $count = 0
    if ($legal) { $count++ }
    if ($buscar) { $count++ }
    if ($input) { $count++ }

    return [pscustomobject]@{
        root = $Root
        legalTab = $legal
        buscarButton = $buscar
        identificationInput = $input
        foundCount = $count
    }
}

$result = [ordered]@{
    ok = $false
    windowFound = $false
    window = $null
    controls = @{
        identificationInput = $null
        buscarButton = $null
        legalTab = $null
    }
    found = @{
        identificationInput = $false
        buscarButton = $false
        legalTab = $false
    }
    error = $null
}

$deadline = (Get-Date).AddMilliseconds($TimeoutMs)
$mainWindow = $null

while ((Get-Date) -lt $deadline) {
    $mainWindow = Find-IcsMainWindow -TitleHint $WindowTitleHint
    if ($mainWindow) { break }
    Start-Sleep -Milliseconds $PollMs
}

if (-not $mainWindow) {
    $result.error = "No se encontro la ventana principal de ICS dentro del timeout."
    $result | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

$result.windowFound = $true

while ((Get-Date) -lt $deadline) {
    $best = $null
    $roots = Get-RootCandidates -MainWindow $mainWindow

    foreach ($root in $roots) {
        $candidate = Find-ControlsInRoot -Root $root
        if (($null -eq $best) -or ($candidate.foundCount -gt $best.foundCount)) {
            $best = $candidate
        }
        if ($candidate.foundCount -ge 3) { break }
    }

    if ($best) {
        $result.window = $best.root
        $result.controls.legalTab = To-ControlSummary -Control $best.legalTab
        $result.controls.buscarButton = To-ControlSummary -Control $best.buscarButton
        $result.controls.identificationInput = To-ControlSummary -Control $best.identificationInput

        $result.found.legalTab = $null -ne $best.legalTab
        $result.found.buscarButton = $null -ne $best.buscarButton
        $result.found.identificationInput = $null -ne $best.identificationInput
        $result.ok = $result.found.buscarButton -and $result.found.identificationInput
    }

    if ($result.ok) { break }
    Start-Sleep -Milliseconds $PollMs
}

if (-not $result.ok) {
    $result.error = "No se pudieron identificar todos los controles requeridos en Gestionar."
}

$result | ConvertTo-Json -Depth 8 -Compress
