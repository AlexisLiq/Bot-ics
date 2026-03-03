param(
    [string]$MainWindowHwnd,
    [int]$SampleLimit = 20,
    [int]$MaxNodes = 3000
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

$win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32IcsLegalInspector
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder text, int maxCount);

    private const int SW_RESTORE = 9;
    private const int SW_SHOW = 5;

    public sealed class ChildInfo
    {
        public long Hwnd { get; set; }
        public long ParentHwnd { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
    }

    public static bool Exists(long hwnd)
    {
        try { return IsWindow(new IntPtr(hwnd)); }
        catch { return false; }
    }

    public static bool Activate(long hwnd)
    {
        try
        {
            var h = new IntPtr(hwnd);
            ShowWindow(h, SW_RESTORE);
            ShowWindow(h, SW_SHOW);
            return SetForegroundWindow(h);
        }
        catch { return false; }
    }

    public static List<ChildInfo> SnapshotChildren(long rootHwnd, int maxNodes)
    {
        var list = new List<ChildInfo>();
        var root = new IntPtr(rootHwnd);

        EnumChildWindows(root, (child, lParam) =>
        {
            if (list.Count >= maxNodes) return false;

            list.Add(new ChildInfo
            {
                Hwnd = child.ToInt64(),
                ParentHwnd = GetParent(child).ToInt64(),
                Title = GetText(child),
                ClassName = GetClass(child),
                Visible = IsWindowVisible(child)
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

$result = [ordered]@{
    ok = $false
    selectedPageTitle = $null
    selectedPageHwnd = "0"
    legalPanel = $null
    deudorPanel = $null
    pages = @()
    error = $null
}

try {
    Add-Type -TypeDefinition $win32Source -Language CSharp -ErrorAction Stop
} catch {
    $result.error = "Add-Type Win32IcsLegalInspector failed: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

$mainHwnd = Parse-Handle $MainWindowHwnd
if ($mainHwnd -eq 0 -or -not [Win32IcsLegalInspector]::Exists($mainHwnd)) {
    $result.error = "Handle invalido de ventana principal."
    $result | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

[void][Win32IcsLegalInspector]::Activate($mainHwnd)

$raw = [Win32IcsLegalInspector]::SnapshotChildren($mainHwnd, [Math]::Max(600, $MaxNodes))
$nodes = foreach ($c in @($raw)) {
    $titleNorm = Normalize-UiText $c.Title
    $classNorm = Normalize-UiText $c.ClassName
    [pscustomobject]@{
        hwnd = [int64]$c.Hwnd
        parentHwnd = [int64]$c.ParentHwnd
        title = [string]$c.Title
        titleNorm = $titleNorm
        className = [string]$c.ClassName
        classNorm = $classNorm
        visible = [bool]$c.Visible
    }
}

$map = @{}
foreach ($n in @($nodes)) {
    $k = [string]$n.parentHwnd
    if (-not $map.ContainsKey($k)) { $map[$k] = @() }
    $map[$k] += $n
}

function Get-Descendants {
    param(
        [hashtable]$ChildrenByParent,
        [int64]$RootHwnd,
        [int]$MaxVisitNodes = 20000
    )

    $out = New-Object System.Collections.ArrayList
    $queue = New-Object System.Collections.Queue
    $visited = @{}
    $queued = @{}

    if ($RootHwnd -ne 0) {
        $queue.Enqueue($RootHwnd)
        $queued[[string]$RootHwnd] = $true
    }

    while ($queue.Count -gt 0 -and $out.Count -lt $MaxVisitNodes) {
        $current = [int64]$queue.Dequeue()
        $currKey = [string]$current
        if ($visited.ContainsKey($currKey)) { continue }
        $visited[$currKey] = $true

        $children = @($ChildrenByParent[[string]$current])
        foreach ($child in @($children)) {
            [void]$out.Add($child)

            $childHwnd = [int64]$child.hwnd
            if ($childHwnd -eq 0) { continue }
            $childKey = [string]$childHwnd
            if (-not $queued.ContainsKey($childKey)) {
                $queued[$childKey] = $true
                $queue.Enqueue($childHwnd)
            }

            if ($out.Count -ge $MaxVisitNodes) { break }
        }
    }

    return @($out)
}

function Build-PanelStats {
    param(
        $Page,
        [hashtable]$ChildrenByParent,
        [int]$Limit,
        [int]$MaxVisitNodes = 20000
    )

    if ($null -eq $Page) { return $null }

    $desc = @(Get-Descendants -ChildrenByParent $ChildrenByParent -RootHwnd ([int64]$Page.hwnd) -MaxVisitNodes $MaxVisitNodes)
    $visible = @($desc | Where-Object { $_.visible })
    $visibleText = @($visible | Where-Object { -not [string]::IsNullOrWhiteSpace($_.titleNorm) })
    $pbdw = @($visible | Where-Object { $_.classNorm.Contains("pbdw") })

    $classes = @(
        $visible |
            Group-Object classNorm |
            Sort-Object Count -Descending |
            Select-Object -First 8 |
            ForEach-Object {
                [pscustomobject]@{
                    className = $_.Name
                    count = $_.Count
                }
            }
    )

    $sampleText = @(
        $visibleText |
            Select-Object -ExpandProperty title -First ([Math]::Max(1, $Limit))
    )

    return [ordered]@{
        hwnd = [string]$Page.hwnd
        title = [string]$Page.title
        visible = [bool]$Page.visible
        descendantCount = $desc.Count
        visibleDescendantCount = $visible.Count
        visiblePbdwCount = $pbdw.Count
        visibleTextCount = $visibleText.Count
        visibleTextSample = $sampleText
        visibleTopClasses = $classes
    }
}

$pages = @($nodes | Where-Object {
        $_.classNorm -eq "fnudo3100" -and -not [string]::IsNullOrWhiteSpace($_.titleNorm)
    })

$selected = @($pages | Where-Object { $_.visible } | Select-Object -First 1)
$selectedPage = if ($selected.Count -gt 0) { $selected[0] } else { $null }

$legal = @($pages | Where-Object { $_.titleNorm -eq "legal" } | Select-Object -First 1)
if ($legal.Count -eq 0) {
    $legal = @($pages | Where-Object { $_.titleNorm.Contains("legal") } | Select-Object -First 1)
}
$legal = if ($legal.Count -gt 0) { $legal[0] } else { $null }

$deudor = @($pages | Where-Object { $_.titleNorm -eq "deudor" } | Select-Object -First 1)
$deudor = if ($deudor.Count -gt 0) { $deudor[0] } else { $null }

$result.selectedPageTitle = if ($null -eq $selectedPage) { $null } else { [string]$selectedPage.title }
$result.selectedPageHwnd = if ($null -eq $selectedPage) { "0" } else { [string]$selectedPage.hwnd }
$maxWalk = [Math]::Max(3000, [Math]::Min(50000, [int]($MaxNodes * 4)))
$result.legalPanel = Build-PanelStats -Page $legal -ChildrenByParent $map -Limit ([Math]::Max(4, $SampleLimit)) -MaxVisitNodes $maxWalk
$result.deudorPanel = Build-PanelStats -Page $deudor -ChildrenByParent $map -Limit ([Math]::Max(4, $SampleLimit)) -MaxVisitNodes $maxWalk

$result.pages = @(
    $pages | Sort-Object parentHwnd, hwnd | ForEach-Object {
        [pscustomobject]@{
            hwnd = [string]$_.hwnd
            parentHwnd = [string]$_.parentHwnd
            title = [string]$_.title
            visible = [bool]$_.visible
        }
    }
)

$result.ok = $true
$result | ConvertTo-Json -Depth 8 -Compress
