param(
    [string]$MainWindowHwnd,
    [string]$LegalTabHwnd,
    [string]$IdentificationInputHwnd,
    [string]$BuscarButtonHwnd,
    [int]$StepDelayMs = 250,
    [int]$PanelWaitMs = 1800,
    [int]$PollMs = 120
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

$win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32LegalTabSwitcher
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

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hWnd, ref POINT pt);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] private static extern bool PostMessageW(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder text, int maxCount);

    private const uint GA_ROOT = 2;
    private const int SW_HIDE = 0;
    private const int SW_SHOW = 5;
    private const int SW_RESTORE = 9;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint WM_KEYDOWN = 0x0100;
    private const uint WM_KEYUP = 0x0101;
    private const uint VK_LEFT = 0x25;
    private const uint VK_RIGHT = 0x27;

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
        try { return IsWindow(new IntPtr(hwnd)); } catch { return false; }
    }

    public static bool IsVisible(long hwnd)
    {
        try { return IsWindowVisible(new IntPtr(hwnd)); } catch { return false; }
    }

    public static long GetParentHwnd(long hwnd)
    {
        try { return GetParent(new IntPtr(hwnd)).ToInt64(); } catch { return 0; }
    }

    public static long GetRootHwnd(long hwnd)
    {
        try
        {
            if (hwnd == 0) return 0;
            return GetAncestor(new IntPtr(hwnd), GA_ROOT).ToInt64();
        }
        catch { return 0; }
    }

    public static string GetTitle(long hwnd)
    {
        try
        {
            var h = new IntPtr(hwnd);
            int len = GetWindowTextLengthW(h);
            if (len < 0) len = 0;
            var sb = new StringBuilder(Math.Max(1, len + 2));
            GetWindowTextW(h, sb, sb.Capacity);
            return sb.ToString();
        }
        catch { return string.Empty; }
    }

    public static string GetClass(long hwnd)
    {
        try
        {
            var sb = new StringBuilder(256);
            GetClassNameW(new IntPtr(hwnd), sb, sb.Capacity);
            return sb.ToString();
        }
        catch { return string.Empty; }
    }

    public static uint GetPid(long hwnd)
    {
        try
        {
            uint pid;
            GetWindowThreadProcessId(new IntPtr(hwnd), out pid);
            return pid;
        }
        catch { return 0; }
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

    public static bool Show(long hwnd)
    {
        try { return ShowWindow(new IntPtr(hwnd), SW_SHOW); } catch { return false; }
    }

    public static bool Hide(long hwnd)
    {
        try { return ShowWindow(new IntPtr(hwnd), SW_HIDE); } catch { return false; }
    }

    public static int[] GetClientSize(long hwnd)
    {
        try
        {
            RECT r;
            if (!GetClientRect(new IntPtr(hwnd), out r)) return new int[] { 0, 0 };
            int w = Math.Max(0, r.Right - r.Left);
            int h = Math.Max(0, r.Bottom - r.Top);
            return new int[] { w, h };
        }
        catch { return new int[] { 0, 0 }; }
    }

    public static bool ClickClientPointGlobal(long hwnd, int x, int y)
    {
        try
        {
            if (!Exists(hwnd)) return false;
            var h = new IntPtr(hwnd);

            var pt = new POINT { X = Math.Max(1, x), Y = Math.Max(1, y) };
            if (!ClientToScreen(h, ref pt)) return false;

            POINT oldPt;
            bool hadOld = GetCursorPos(out oldPt);

            SetCursorPos(pt.X, pt.Y);
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);

            if (hadOld)
            {
                SetCursorPos(oldPt.X, oldPt.Y);
            }
            return true;
        }
        catch { return false; }
    }

    public static bool SendArrowKey(long hwnd, bool right)
    {
        try
        {
            if (!Exists(hwnd)) return false;
            var h = new IntPtr(hwnd);
            uint vk = right ? VK_RIGHT : VK_LEFT;
            PostMessageW(h, WM_KEYDOWN, new IntPtr(vk), IntPtr.Zero);
            PostMessageW(h, WM_KEYUP, new IntPtr(vk), IntPtr.Zero);
            return true;
        }
        catch { return false; }
    }

    public static List<ChildInfo> SnapshotDescendants(long rootHwnd, int maxNodes)
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
                ClassName = GetClass(child.ToInt64()),
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
}
"@

$result = [ordered]@{
    ok = $false
    method = "pbtab_scan_click"
    realClickTried = $false
    realClickHit = $false
    realClickAttempts = 0
    realClickMode = "none"
    realTabCandidates = 0
    realTabHandleUsed = "0"
    fallbackReason = $null
    selected = $false
    panelChanged = $false
    activePageBefore = $null
    activePageAfter = $null
    legalHandleUsed = "0"
    deudorHandleUsed = "0"
    parentGroupUsed = "0"
    mainWindowRequested = "0"
    mainWindowUsed = "0"
    mainWindowSource = "none"
    inputRoot = "0"
    buscarRoot = "0"
    legalRoot = "0"
    inputAncestorPage = $null
    buscarAncestorPage = $null
    hiddenCount = 0
    debug = [ordered]@{
        tabCandidates = @()
        directLegalClickCandidates = @()
        orderedPages = @()
        pbSource = @()
        attemptTrace = @()
    }
    error = $null
}

try {
    Add-Type -TypeDefinition $win32Source -Language CSharp -ErrorAction Stop
} catch {
    $result.error = "Add-Type Win32LegalTabSwitcher failed: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$wsh = $null
try { $wsh = New-Object -ComObject WScript.Shell } catch { $wsh = $null }

function Add-AttemptTrace {
    param(
        [string]$Phase,
        [string]$Mode,
        [int64]$TargetHwnd,
        [int]$X = -1,
        [int]$Y = -1,
        [string]$ActiveBefore = $null,
        [string]$ActiveAfter = $null,
        [bool]$Confirmed = $false,
        [string]$Note = $null
    )

    $current = @($result.debug.attemptTrace)
    $entry = [ordered]@{
        n = [int]($current.Count + 1)
        phase = $Phase
        mode = $Mode
        targetHwnd = [string]$TargetHwnd
        x = if ($X -ge 0) { [int]$X } else { $null }
        y = if ($Y -ge 0) { [int]$Y } else { $null }
        activeBefore = $ActiveBefore
        activeAfter = $ActiveAfter
        confirmed = [bool]$Confirmed
        note = $Note
        ts = (Get-Date).ToString("HH:mm:ss.fff")
    }

    $result.debug.attemptTrace = @($current + @([pscustomobject]$entry))
    if (@($result.debug.attemptTrace).Count -gt 120) {
        $result.debug.attemptTrace = @($result.debug.attemptTrace | Select-Object -Last 120)
    }
}

function Get-UniqueHandles {
    param([int64[]]$Handles)
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($h in @($Handles)) {
        if ($h -le 0) { continue }
        $k = [string]$h
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        [void]$out.Add([int64]$h)
    }
    return @($out)
}

function Resolve-MainWindowHandle {
    param(
        [int64]$Requested,
        [int64]$InputRoot,
        [int64]$BuscarRoot,
        [int64]$LegalRoot
    )

    $candidates = Get-UniqueHandles -Handles @($Requested, $InputRoot, $BuscarRoot, $LegalRoot)
    if ($candidates.Count -eq 0) { return $null }

    $best = $null
    foreach ($h in $candidates) {
        if (-not [Win32LegalTabSwitcher]::Exists($h)) { continue }
        $pid = [int][Win32LegalTabSwitcher]::GetPid($h)
        $procName = Get-ProcessNameSafe -ProcId $pid
        $procNorm = Normalize-UiText $procName
        $title = [string][Win32LegalTabSwitcher]::GetTitle($h)
        $titleNorm = Normalize-UiText $title
        $isIcs = $procNorm.Contains("ics_client")
        $isIcsTitle = $titleNorm.Contains("internet collection system")

        $score = 0
        if ($h -eq $Requested) { $score += 3 }
        if ($isIcs) { $score += 3 }
        if ($isIcsTitle) { $score += 2 }

        $candidate = [pscustomobject]@{
            hwnd = [int64]$h
            score = [int]$score
            source = if ($h -eq $Requested) { "requested" } elseif ($h -eq $InputRoot) { "input_root" } elseif ($h -eq $BuscarRoot) { "buscar_root" } elseif ($h -eq $LegalRoot) { "legal_root" } else { "candidate" }
        }

        if ($null -eq $best -or $candidate.score -gt $best.score) {
            $best = $candidate
        }
    }

    return $best
}

function Get-PeerPages {
    param(
        [int64]$MainHandle,
        [int64]$ParentHandle,
        [int]$MaxNodes = 2000
    )

    $rows = [Win32LegalTabSwitcher]::SnapshotDescendants($MainHandle, $MaxNodes)
    $peers = foreach ($r in $rows) {
        if ([int64]$r.ParentHwnd -ne $ParentHandle) { continue }
        $title = [string]$r.Title
        $titleNorm = Normalize-UiText $title
        if ([string]::IsNullOrWhiteSpace($titleNorm)) { continue }

        [pscustomobject]@{
            hwnd = [int64]$r.Hwnd
            parentHwnd = [int64]$r.ParentHwnd
            title = $title
            titleNorm = $titleNorm
            className = [string]$r.ClassName
            classNorm = Normalize-UiText $r.ClassName
            visible = [bool]$r.Visible
        }
    }

    $ordered = @($peers | Sort-Object @{ Expression = { $_.hwnd } })
    return $ordered
}

function Get-VisiblePeerPage {
    param($Peers)
    return @($Peers | Where-Object { [Win32LegalTabSwitcher]::IsVisible([int64]$_.hwnd) } | Select-Object -First 1)
}

function Wait-LegalVisible {
    param(
        [int64]$LegalHandle,
        $Peers,
        [int]$WaitMs,
        [int]$PollStepMs
    )

    $deadline = (Get-Date).AddMilliseconds([Math]::Max(300, $WaitMs))
    $stableHits = 0
    $lastVisible = $null

    while ((Get-Date) -lt $deadline) {
        $active = Get-VisiblePeerPage -Peers $Peers
        $activeNorm = if ($active.Count -eq 0) { "" } else { [string]$active[0].titleNorm }
        $isLegalVisible = [Win32LegalTabSwitcher]::IsVisible($LegalHandle)
        if ($isLegalVisible -and $activeNorm.Contains("legal")) {
            $stableHits++
            if ($stableHits -ge 2) {
                return [pscustomobject]@{
                    ok = $true
                    activeTitle = if ($active.Count -eq 0) { $null } else { [string]$active[0].title }
                }
            }
        } else {
            $stableHits = 0
        }

        if ($active.Count -gt 0) {
            $lastVisible = [string]$active[0].title
        }

        Start-Sleep -Milliseconds ([Math]::Max(20, $PollStepMs))
    }

    return [pscustomobject]@{
        ok = $false
        activeTitle = $lastVisible
    }
}

function Get-TabOrderIndex {
    param([string]$TitleNorm)

    $order = @(
        "deudor",
        "direcciones",
        "obligaciones",
        "cuentas",
        "codeudores",
        "legal",
        "promesas",
        "garantias",
        "negociaciones",
        "cheques",
        "visitas",
        "cartas",
        "bienes",
        "ahorro milagroso"
    )

    $t = Normalize-UiText $TitleNorm
    for ($i = 0; $i -lt $order.Count; $i++) {
        if ($t -eq $order[$i] -or $t.Contains($order[$i])) { return $i }
    }
    return -1
}

function Is-TopTabTitle {
    param([string]$TitleNorm)
    $t = Normalize-UiText $TitleNorm
    if ([string]::IsNullOrWhiteSpace($t)) { return $false }

    $topTokens = @(
        "deudor",
        "direcciones",
        "obligaciones",
        "cuentas",
        "codeudor",
        "legal",
        "promesas",
        "garantias",
        "negociaciones",
        "cheques",
        "visitas",
        "cartas",
        "bienes",
        "ahorro milagroso"
    )

    foreach ($tok in $topTokens) {
        if ($t -eq $tok -or $t.Contains($tok)) { return $true }
    }
    return $false
}

function Get-PresentTopTabCount {
    param($Peers)
    $seen = @{}
    foreach ($p in @($Peers)) {
        $ix = Get-TabOrderIndex -TitleNorm $p.titleNorm
        if ($ix -lt 0) { continue }
        $k = [string]$ix
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
    }
    return $seen.Keys.Count
}

function Test-TitleContainsToken {
    param(
        [string]$TitleNorm,
        [string]$Token
    )

    if ([string]::IsNullOrWhiteSpace($TitleNorm) -or [string]::IsNullOrWhiteSpace($Token)) { return $false }
    return ($TitleNorm -eq $Token -or $TitleNorm.Contains($Token))
}

function Get-OrderedTopPages {
    param($Peers)
    return @(
        @($Peers) |
            Sort-Object @{
                Expression = {
                    $ix = Get-TabOrderIndex -TitleNorm $_.titleNorm
                    if ($ix -ge 0) { $ix } else { 999 }
                }
            }, @{ Expression = { $_.hwnd } }
    )
}

function Get-PageIndexByHwnd {
    param(
        $Pages,
        [int64]$Hwnd
    )
    for ($i = 0; $i -lt @($Pages).Count; $i++) {
        if ([int64]$Pages[$i].hwnd -eq $Hwnd) { return $i }
    }
    return -1
}

function Get-TabWeight {
    param([string]$TitleNorm)

    $t = Normalize-UiText $TitleNorm
    if ([string]::IsNullOrWhiteSpace($t)) { return 8.0 }

    # Aproximacion de ancho visual del tab: base + longitud del texto.
    $len = [Math]::Max(4, [Math]::Min(22, $t.Length))
    return [double](6.0 + $len)
}

function Get-WeightedCenterX {
    param(
        $Pages,
        [int64]$TargetHwnd,
        [int]$Width
    )

    if ($Width -le 24) { return -1 }
    $list = @($Pages)
    if ($list.Count -eq 0) { return -1 }

    $targetIx = Get-PageIndexByHwnd -Pages $list -Hwnd $TargetHwnd
    if ($targetIx -lt 0) { return -1 }

    $total = 0.0
    foreach ($p in $list) {
        $total += (Get-TabWeight -TitleNorm $p.titleNorm)
    }
    if ($total -le 0.01) { return -1 }

    $before = 0.0
    for ($i = 0; $i -lt $targetIx; $i++) {
        $before += (Get-TabWeight -TitleNorm $list[$i].titleNorm)
    }

    $targetW = Get-TabWeight -TitleNorm $list[$targetIx].titleNorm
    $centerRatio = ($before + ($targetW / 2.0)) / $total
    $x = [int][Math]::Round($centerRatio * $Width)
    return [Math]::Max(12, [Math]::Min($Width - 12, $x))
}

$mainRequested = Parse-Handle $MainWindowHwnd
$providedLegalTabHandle = Parse-Handle $LegalTabHwnd
$legalHandle = $providedLegalTabHandle
$inputHandle = Parse-Handle $IdentificationInputHwnd
$buscarHandle = Parse-Handle $BuscarButtonHwnd

$result.mainWindowRequested = [string]$mainRequested

$inputRoot = [Win32LegalTabSwitcher]::GetRootHwnd($inputHandle)
$buscarRoot = [Win32LegalTabSwitcher]::GetRootHwnd($buscarHandle)
$legalRoot = [Win32LegalTabSwitcher]::GetRootHwnd($legalHandle)

$result.inputRoot = [string]$inputRoot
$result.buscarRoot = [string]$buscarRoot
$result.legalRoot = [string]$legalRoot

$mainChoice = Resolve-MainWindowHandle -Requested $mainRequested -InputRoot $inputRoot -BuscarRoot $buscarRoot -LegalRoot $legalRoot
if ($null -eq $mainChoice) {
    $result.error = "No se pudo resolver la ventana principal de ICS."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$mainHwnd = [int64]$mainChoice.hwnd
$result.mainWindowUsed = [string]$mainHwnd
$result.mainWindowSource = [string]$mainChoice.source

if (-not [Win32LegalTabSwitcher]::Exists($mainHwnd)) {
    $result.error = "Handle invalido para ventana principal de ICS."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

[void][Win32LegalTabSwitcher]::Activate($mainHwnd)
Start-Sleep -Milliseconds ([Math]::Max(60, $StepDelayMs))

$rowsBefore = [Win32LegalTabSwitcher]::SnapshotDescendants($mainHwnd, 2000)
$nodesBefore = foreach ($r in @($rowsBefore)) {
    [pscustomobject]@{
        hwnd = [int64]$r.Hwnd
        parentHwnd = [int64]$r.ParentHwnd
        title = [string]$r.Title
        titleNorm = Normalize-UiText $r.Title
        className = [string]$r.ClassName
        classNorm = Normalize-UiText $r.ClassName
        visible = [bool]$r.Visible
    }
}

$fnudoPages = @($nodesBefore | Where-Object { $_.classNorm -eq "fnudo3100" -and -not [string]::IsNullOrWhiteSpace($_.titleNorm) })
$fnudoGroupsMap = @{}
foreach ($p in @($fnudoPages)) {
    $k = [string]$p.parentHwnd
    if (-not $fnudoGroupsMap.ContainsKey($k)) {
        $fnudoGroupsMap[$k] = New-Object System.Collections.ArrayList
    }
    [void]$fnudoGroupsMap[$k].Add($p)
}

$bestGroup = $null
foreach ($entry in @($fnudoGroupsMap.GetEnumerator())) {
    $pages = @($entry.Value)
    if ($pages.Count -eq 0) { continue }

    $titles = @($pages | ForEach-Object { $_.titleNorm })
    $hasLegal = @($titles | Where-Object { Test-TitleContainsToken -TitleNorm $_ -Token "legal" }).Count -gt 0
    if (-not $hasLegal) { continue }

    $score = 0
    if (@($titles | Where-Object { Test-TitleContainsToken -TitleNorm $_ -Token "deudor" }).Count -gt 0) { $score += 6 }
    if ($hasLegal) { $score += 6 }

    foreach ($token in @("direcciones", "obligaciones", "cuentas", "codeudor", "promesas", "garantias", "negociaciones", "cheques", "visitas", "cartas", "bienes")) {
        if (@($titles | Where-Object { Test-TitleContainsToken -TitleNorm $_ -Token $token }).Count -gt 0) {
            $score += 1
        }
    }

    $visibleCount = @($pages | Where-Object { $_.visible }).Count
    $score += [Math]::Min(3, $visibleCount)
    $score += [Math]::Min(10, $pages.Count)

    $candidate = [pscustomobject]@{
        parentHwnd = [int64]$entry.Key
        pages = $pages
        score = [int]$score
        count = [int]$pages.Count
    }

    if ($null -eq $bestGroup -or $candidate.score -gt $bestGroup.score -or ($candidate.score -eq $bestGroup.score -and $candidate.count -gt $bestGroup.count)) {
        $bestGroup = $candidate
    }
}

$groupParent = 0
$peerPages = @()
$legalPage = @()

if ($null -ne $bestGroup) {
    $groupParent = [int64]$bestGroup.parentHwnd
    $peerPages = @(
        @($bestGroup.pages) |
            Sort-Object @{ Expression = { $ix = Get-TabOrderIndex -TitleNorm $_.titleNorm; if ($ix -ge 0) { $ix } else { 999 } } }, @{ Expression = { $_.hwnd } }
    )
    $legalPage = @($peerPages | Where-Object { Test-TitleContainsToken -TitleNorm $_.titleNorm -Token "legal" } | Select-Object -First 1)
    if ($legalPage.Count -eq 0) {
        $legalPage = @($peerPages | Select-Object -First 1)
    }
}

if ($legalPage.Count -gt 0) {
    $legalHandle = [int64]$legalPage[0].hwnd
} else {
    if ($legalHandle -eq 0 -or -not [Win32LegalTabSwitcher]::Exists($legalHandle)) {
        $result.error = "Handle invalido para la pestana Legal."
        $result | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }
    $groupParent = [Win32LegalTabSwitcher]::GetParentHwnd($legalHandle)
    if ($groupParent -eq 0 -or -not [Win32LegalTabSwitcher]::Exists($groupParent)) {
        $result.error = "No se pudo resolver el contenedor padre de la pestana Legal."
        $result | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }
    $peerPages = @(
        Get-PeerPages -MainHandle $mainHwnd -ParentHandle $groupParent |
            Sort-Object @{ Expression = { $ix = Get-TabOrderIndex -TitleNorm $_.titleNorm; if ($ix -ge 0) { $ix } else { 999 } } }, @{ Expression = { $_.hwnd } }
    )
    $legalPage = @($peerPages | Where-Object { [int64]$_.hwnd -eq $legalHandle } | Select-Object -First 1)
}

if ($groupParent -eq 0 -or -not [Win32LegalTabSwitcher]::Exists($groupParent)) {
    $result.error = "No se pudo resolver el contenedor padre de Legal."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}
$result.parentGroupUsed = [string]$groupParent

if ($peerPages.Count -eq 0) {
    $result.error = "No se encontraron paneles hermanos para alternar a Legal."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

# Filtramos solo tabs de la fila superior para evitar ruido de paginas internas.
$peerPagesTop = @($peerPages | Where-Object { Is-TopTabTitle -TitleNorm $_.titleNorm })
if (@($peerPagesTop).Count -ge 5 -and @($peerPagesTop | Where-Object { Test-TitleContainsToken -TitleNorm $_.titleNorm -Token "legal" }).Count -gt 0) {
    $peerPages = @(
        @($peerPagesTop) |
            Sort-Object @{ Expression = { $ix = Get-TabOrderIndex -TitleNorm $_.titleNorm; if ($ix -ge 0) { $ix } else { 999 } } }, @{ Expression = { $_.hwnd } }
    )
}

if ($legalPage.Count -eq 0) {
    $legalPage = @($peerPages | Where-Object { $_.titleNorm -eq "legal" -or $_.titleNorm.Contains("legal") } | Select-Object -First 1)
}
if ($legalPage.Count -eq 0) {
    $result.error = "No se pudo resolver la pagina Legal real."
    $result | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$legalHandle = [int64]$legalPage[0].hwnd
$deudorPage = @($peerPages | Where-Object { Test-TitleContainsToken -TitleNorm $_.titleNorm -Token "deudor" } | Select-Object -First 1)
if ($deudorPage.Count -gt 0) {
    $result.deudorHandleUsed = [string]$deudorPage[0].hwnd
}
$result.legalHandleUsed = [string]$legalHandle
$orderedTopPages = @(Get-OrderedTopPages -Peers $peerPages)
$legalIxByGroup = Get-PageIndexByHwnd -Pages $orderedTopPages -Hwnd $legalHandle
$result.debug.orderedPages = @(
    for ($i = 0; $i -lt @($orderedTopPages).Count; $i++) {
        $p = $orderedTopPages[$i]
        [pscustomobject]@{
            ix = [int]$i
            hwnd = [string]$p.hwnd
            parentHwnd = [string]$p.parentHwnd
            title = [string]$p.title
            className = [string]$p.className
            visible = [bool][Win32LegalTabSwitcher]::IsVisible([int64]$p.hwnd)
        }
    }
)

$directLegalClickCandidates = New-Object System.Collections.ArrayList
$directSeen = @{}
function Add-DirectLegalClickCandidate {
    param([int64]$Handle)
    if ($Handle -le 0) { return }
    if (-not [Win32LegalTabSwitcher]::Exists($Handle)) { return }
    $k = [string]$Handle
    if ($directSeen.ContainsKey($k)) { return }
    $directSeen[$k] = $true
    [void]$directLegalClickCandidates.Add($Handle)
}

# 1) Prioridad: HWND detectado de "Legal" desde identify-controls (suele ser el tab real clickable).
Add-DirectLegalClickCandidate -Handle $providedLegalTabHandle

# 2) Candidatos visibles con texto Legal que NO son el panel fnudo.
$labelLikeLegal = @(
    $nodesBefore | Where-Object {
        $_.visible -and
        (Test-TitleContainsToken -TitleNorm $_.titleNorm -Token "legal") -and
        $_.classNorm -ne "fnudo3100"
    } | Sort-Object @{ Expression = { -not $_.classNorm.Contains("pbtab") } }, @{ Expression = { -not $_.classNorm.Contains("static") } }, @{ Expression = { $_.hwnd } }
)
foreach ($c in @($labelLikeLegal)) {
    Add-DirectLegalClickCandidate -Handle ([int64]$c.hwnd)
}
$directLegalClickCandidates = @($directLegalClickCandidates | Where-Object {
    $h = [int64]$_
    $node = @($nodesBefore | Where-Object { [int64]$_.hwnd -eq $h } | Select-Object -First 1)
    if ($node.Count -eq 0) { return $true }
    return $node[0].classNorm -ne "fnudo3100"
})
$result.debug.directLegalClickCandidates = @(
    @($directLegalClickCandidates) | ForEach-Object { [string]$_ }
)
Add-AttemptTrace -Phase "direct_candidates" -Mode "prepare" -TargetHwnd 0 -ActiveBefore $null -ActiveAfter $null -Confirmed $false -Note ("count=" + [string](@($directLegalClickCandidates).Count))

$activeBefore = Get-VisiblePeerPage -Peers $peerPages
$result.activePageBefore = if ($activeBefore.Count -eq 0) { $null } else { [string]$activeBefore[0].title }
$preLegalVisible = [Win32LegalTabSwitcher]::IsVisible($legalHandle)
$preDeudorVisible = if ($deudorPage.Count -eq 0) { $false } else { [Win32LegalTabSwitcher]::IsVisible([int64]$deudorPage[0].hwnd) }

# 1) Intento principal: click real al tab "Legal"
$tabCandidates = New-Object System.Collections.ArrayList
$tabAdded = @{}

function Add-TabCandidate {
    param([int64]$Handle)
    if ($Handle -le 0) { return }
    if (-not [Win32LegalTabSwitcher]::Exists($Handle)) { return }
    $k = [string]$Handle
    if ($tabAdded.ContainsKey($k)) { return }
    $tabAdded[$k] = $true
    [void]$tabCandidates.Add([int64]$Handle)
}

$pbTabs = @(
    $nodesBefore |
        Where-Object { (Normalize-UiText $_.ClassName).Contains("pbtabcontrol32_100") } |
        ForEach-Object {
            [pscustomobject]@{
                hwnd = [int64]$_.hwnd
                parentHwnd = [int64]$_.parentHwnd
            }
        }
)

$groupParentParent = [Win32LegalTabSwitcher]::GetParentHwnd($groupParent)
$pbPreferred = @(
    $pbTabs | Where-Object {
        [int64]$_.parentHwnd -eq $groupParent -or
        [int64]$_.parentHwnd -eq $groupParentParent
    }
)

$pbSource = if ($pbPreferred.Count -gt 0) { $pbPreferred } else { $pbTabs }
foreach ($pb in @($pbSource)) {
    Add-TabCandidate -Handle ([int64]$pb.hwnd)
}

$result.debug.pbSource = @(
    @($pbSource) | ForEach-Object {
        [pscustomobject]@{
            hwnd = [string]$_.hwnd
            parentHwnd = [string]$_.parentHwnd
        }
    }
)

if ($pbSource.Count -eq 0) {
    # Fallback de tab container solo si no hay tabcontrol dedicado.
    Add-TabCandidate -Handle $groupParent
}
$result.realTabCandidates = @($tabCandidates).Count
$result.debug.tabCandidates = @(
    @($tabCandidates) | ForEach-Object { [string]$_ }
)
Add-AttemptTrace -Phase "tab_candidates" -Mode "prepare" -TargetHwnd 0 -ActiveBefore $null -ActiveAfter $null -Confirmed $false -Note ("count=" + [string]$result.realTabCandidates)

$selectedByRealClick = $false
$legalIx = if ($legalIxByGroup -ge 0) { $legalIxByGroup } else { 5 }
$topTabCount = [Math]::Max(1, @($orderedTopPages).Count)
$maxRealAttempts = [Math]::Max(14, [Math]::Min(20, [int]($topTabCount + 8)))

function Try-RealClickLegal {
    param(
        [int64]$MainHwnd,
        [int64]$TabHwnd,
        [int]$X,
        [int]$Y,
        [string]$Mode
    )

    if ([int]$result.realClickAttempts -ge $maxRealAttempts) { return $false }

    $result.realClickTried = $true
    $result.realClickAttempts = [int]$result.realClickAttempts + 1
    $result.realTabHandleUsed = [string]$TabHwnd
    $activeBeforeObj = Get-VisiblePeerPage -Peers $peerPages
    $activeBeforeTitle = if ($activeBeforeObj.Count -eq 0) { $null } else { [string]$activeBeforeObj[0].title }
    [void][Win32LegalTabSwitcher]::Activate($MainHwnd)
    Start-Sleep -Milliseconds 24

    $clicked = [Win32LegalTabSwitcher]::ClickClientPointGlobal($TabHwnd, [int]$X, [int]$Y)
    if (-not $clicked) {
        Add-AttemptTrace -Phase "click" -Mode $Mode -TargetHwnd $TabHwnd -X $X -Y $Y -ActiveBefore $activeBeforeTitle -ActiveAfter $null -Confirmed $false -Note "click_failed"
        return $false
    }

    $result.realClickMode = $Mode
    $confirm = Wait-LegalVisible -LegalHandle $legalHandle -Peers $peerPages -WaitMs ([Math]::Max(120, [Math]::Min(260, [int]($PanelWaitMs / 6)))) -PollStepMs ([Math]::Max(12, [int]($PollMs / 3)))
    $activeAfterObj = Get-VisiblePeerPage -Peers $peerPages
    $activeAfterTitle = if ($activeAfterObj.Count -eq 0) { $null } else { [string]$activeAfterObj[0].title }
    Add-AttemptTrace -Phase "click" -Mode $Mode -TargetHwnd $TabHwnd -X $X -Y $Y -ActiveBefore $activeBeforeTitle -ActiveAfter $activeAfterTitle -Confirmed ([bool]$confirm.ok) -Note $confirm.activeTitle
    if ($confirm.ok) {
        $result.realClickHit = $true
        return $true
    }

    return $false
}

function Try-RealClickHandleCenter {
    param(
        [int64]$MainHwnd,
        [int64]$Handle,
        [string]$Mode
    )

    if ($Handle -le 0 -or -not [Win32LegalTabSwitcher]::Exists($Handle)) { return $false }
    $size = [Win32LegalTabSwitcher]::GetClientSize($Handle)
    if ($null -eq $size -or $size.Length -lt 2) { return $false }

    $w = [int]$size[0]
    $h = [int]$size[1]
    if ($w -lt 10 -or $h -lt 8) { return $false }

    $xList = @(
        [Math]::Max(4, [Math]::Min($w - 4, [int]([Math]::Round($w * 0.46)))),
        [Math]::Max(4, [Math]::Min($w - 4, [int]([Math]::Round($w * 0.54))))
    ) | Select-Object -Unique

    $y = [Math]::Max(3, [Math]::Min($h - 3, [int]([Math]::Round($h * 0.45))))

    foreach ($x in @($xList)) {
        if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }
        $hit = Try-RealClickLegal -MainHwnd $MainHwnd -TabHwnd $Handle -X $x -Y $y -Mode $Mode
        if ($hit) { return $true }
    }

    return $false
}

function Try-KeyboardNavigateLegal {
    param(
        [int64]$MainHwnd,
        [int64]$TabHwnd,
        [int]$XFocus,
        [int]$YFocus
    )

    $activeNow = Get-VisiblePeerPage -Peers $peerPages
    if ($activeNow.Count -eq 0) { return $false }

    $activeNorm = [string]$activeNow[0].titleNorm
    if ($activeNorm.Contains("legal")) {
        $result.realClickHit = $true
        $result.realClickMode = "already_legal"
        Add-AttemptTrace -Phase "keyboard" -Mode "already_legal" -TargetHwnd $TabHwnd -ActiveBefore $activeNow[0].title -ActiveAfter $activeNow[0].title -Confirmed $true -Note "already_selected"
        return $true
    }

    $size = [Win32LegalTabSwitcher]::GetClientSize($TabHwnd)
    if ($null -eq $size -or $size.Length -lt 2) { return $false }
    $w = [int]$size[0]
    $h = [int]$size[1]
    if ($w -lt 40 -or $h -lt 10) { return $false }

    $slotCount = [Math]::Max(1, @($peerPages).Count)
    $pitch = [Math]::Max(18, [int]([Math]::Floor($w / $slotCount)))
    $sweepSteps = [Math]::Min(8, [Math]::Max(4, @($peerPages).Count + 1))
    $yCandidates = @(
        [Math]::Max(6, [Math]::Min($h - 3, [int]$YFocus)),
        [Math]::Max(6, [Math]::Min($h - 3, [int]($YFocus + 4))),
        [Math]::Max(6, [Math]::Min($h - 3, [int]($YFocus + 8)))
    ) | Select-Object -Unique

    Add-AttemptTrace -Phase "keyboard_plan" -Mode "cycle_right" -TargetHwnd $TabHwnd -ActiveBefore $activeNow[0].title -ActiveAfter $null -Confirmed $false -Note ("steps=" + [string]$sweepSteps + ",y=" + (@($yCandidates) -join ","))

    foreach ($yFocusEff in @($yCandidates)) {
        if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }

        $beforeFocusObj = Get-VisiblePeerPage -Peers $peerPages
        if ($beforeFocusObj.Count -eq 0) { break }
        $beforeFocusTitle = [string]$beforeFocusObj[0].title
        $beforeFocusIx = Get-PageIndexByHwnd -Pages $orderedTopPages -Hwnd ([int64]$beforeFocusObj[0].hwnd)
        if ($beforeFocusIx -lt 0) { $beforeFocusIx = 0 }
        $xActive = [Math]::Max(12, [Math]::Min($w - 12, [int]([Math]::Round(($beforeFocusIx + 0.5) * $pitch))))

        [void][Win32LegalTabSwitcher]::Activate($MainHwnd)
        Start-Sleep -Milliseconds 16
        [void][Win32LegalTabSwitcher]::ClickClientPointGlobal($TabHwnd, $xActive, [int]$yFocusEff)
        Start-Sleep -Milliseconds 20

        for ($i = 0; $i -lt $sweepSteps; $i++) {
            if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }

            $beforeObj = Get-VisiblePeerPage -Peers $peerPages
            $beforeTitle = if ($beforeObj.Count -eq 0) { $null } else { [string]$beforeObj[0].title }

            $result.realClickTried = $true
            $result.realClickAttempts = [int]$result.realClickAttempts + 1
            $result.realTabHandleUsed = [string]$TabHwnd
            $result.realClickMode = "keyboard_cycle_right"

            [void][Win32LegalTabSwitcher]::SendArrowKey($TabHwnd, $true)
            if ($null -ne $wsh) {
                try {
                    [void][Win32LegalTabSwitcher]::Activate($MainHwnd)
                    Start-Sleep -Milliseconds 8
                    $wsh.SendKeys("{RIGHT}")
                } catch {
                    # no-op
                }
            }

            $confirm = Wait-LegalVisible -LegalHandle $legalHandle -Peers $peerPages -WaitMs ([Math]::Max(110, [Math]::Min(260, [int]($PanelWaitMs / 7)))) -PollStepMs ([Math]::Max(12, [int]($PollMs / 3)))
            $afterObj = Get-VisiblePeerPage -Peers $peerPages
            $afterTitle = if ($afterObj.Count -eq 0) { $null } else { [string]$afterObj[0].title }
            Add-AttemptTrace -Phase "keyboard_step" -Mode $result.realClickMode -TargetHwnd $TabHwnd -X $xActive -Y $yFocusEff -ActiveBefore $beforeTitle -ActiveAfter $afterTitle -Confirmed ([bool]$confirm.ok) -Note ("step=" + [string]($i + 1))
            if ($confirm.ok) {
                $result.realClickHit = $true
                return $true
            }
            Start-Sleep -Milliseconds 22
        }
    }

    return $false
}

function Try-DirectedRoundLegal {
    param(
        [int64]$MainHwnd,
        [int64]$TabHwnd,
        [int]$Width,
        [int]$Pitch,
        [int]$XCenterWeighted,
        [int]$XCenter,
        [int]$XCenterRightBias
    )

    $activeNow = Get-VisiblePeerPage -Peers $peerPages
    if ($activeNow.Count -eq 0) { return $false }

    $activeNorm = [string]$activeNow[0].titleNorm
    $activeHwnd = [int64]$activeNow[0].hwnd
    $activeIx = Get-PageIndexByHwnd -Pages $orderedTopPages -Hwnd $activeHwnd
    if ($activeIx -lt 0) {
        $activeIx = Get-TabOrderIndex -TitleNorm $activeNorm
    }

    $xCandidates = New-Object System.Collections.ArrayList
    $xSeen = @{}
    function Add-XCandidate {
        param([int]$XValue)
        $xClamped = [Math]::Max(12, [Math]::Min($Width - 12, [int]$XValue))
        $k = [string]$xClamped
        if ($xSeen.ContainsKey($k)) { return }
        $xSeen[$k] = $true
        [void]$xCandidates.Add($xClamped)
    }

    if ($activeIx -ge 0) {
        $activeCenterEq = [Math]::Max(12, [Math]::Min($Width - 12, [int]([Math]::Round(($activeIx + 0.5) * $Pitch))))
        if ($activeNorm.Contains("cuentas")) {
            Add-XCandidate ([int]($activeCenterEq + [Math]::Round($Pitch * 2.00)))
            Add-XCandidate ([int]($activeCenterEq + [Math]::Round($Pitch * 2.20)))
            Add-XCandidate ([int]($activeCenterEq + [Math]::Round($Pitch * 1.80)))
        } elseif ($activeNorm.Contains("codeudor")) {
            Add-XCandidate ([int]($activeCenterEq + [Math]::Round($Pitch * 1.00)))
            Add-XCandidate ([int]($activeCenterEq + [Math]::Round($Pitch * 1.15)))
            Add-XCandidate ([int]($activeCenterEq + [Math]::Round($Pitch * 0.85)))
        } elseif ($legalIx -ge 0 -and $activeIx -ne $legalIx) {
            $delta = $legalIx - $activeIx
            Add-XCandidate ([int]($activeCenterEq + ($delta * $Pitch)))
            Add-XCandidate ([int]($activeCenterEq + ($delta * [Math]::Round($Pitch * 0.90))))
        }
    }

    if ($XCenterWeighted -gt 0) {
        Add-XCandidate $XCenterWeighted
        Add-XCandidate ([int]($XCenterWeighted + [Math]::Round($Pitch * 0.12)))
        Add-XCandidate ([int]($XCenterWeighted - [Math]::Round($Pitch * 0.10)))
    }

    Add-XCandidate $XCenterRightBias
    Add-XCandidate $XCenter
    Add-XCandidate ([int]($XCenter + [Math]::Round($Pitch * 0.28)))

    Add-AttemptTrace -Phase "directed_round_plan" -Mode "directed_global_attempt" -TargetHwnd $TabHwnd -ActiveBefore $activeNow[0].title -ActiveAfter $null -Confirmed $false -Note ("candidates=" + [string](@($xCandidates).Count))

    $yCandidates = @(
        9,
        11,
        13,
        15,
        18
    )

    foreach ($y in @($yCandidates)) {
        foreach ($x in @($xCandidates)) {
            if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }
            $hit = Try-RealClickLegal -MainHwnd $MainHwnd -TabHwnd $TabHwnd -X $x -Y $y -Mode "directed_global_attempt"
            if ($hit) { return $true }
        }
    }

    return $false
}

foreach ($tabHwnd in @($tabCandidates)) {
    if ($selectedByRealClick) { break }
    if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }

    $size = [Win32LegalTabSwitcher]::GetClientSize($tabHwnd)
    if ($null -eq $size -or $size.Length -lt 2) { continue }
    $w = [int]$size[0]
    $h = [int]$size[1]
    if ($w -lt 120 -or $h -lt 12) { continue }

    $slotCount = if ($topTabCount -gt 0) { [Math]::Max(8, [Math]::Min(28, [int]$topTabCount)) } else { 10 }
    $pitch = [Math]::Max(22, [int]([Math]::Floor($w / $slotCount)))
    $xCenterWeighted = Get-WeightedCenterX -Pages $orderedTopPages -TargetHwnd $legalHandle -Width $w
    $xCenter = if ($xCenterWeighted -gt 0) { $xCenterWeighted } else { [int]([Math]::Round(($legalIx + 0.5) * $pitch)) }
    $xCenter = [Math]::Max(12, [Math]::Min($w - 12, $xCenter))
    $xCenterRightBias = [Math]::Max(12, [Math]::Min($w - 12, [int]($xCenter + [Math]::Round($pitch * 0.18))))
    $yFocus = [Math]::Max(6, [Math]::Min($h - 4, 11))

    # 1) Intento mas directo: click al control Legal detectado (HWND label/tab).
    foreach ($hDirect in @($directLegalClickCandidates)) {
        if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }
        $hitDirect = Try-RealClickHandleCenter -MainHwnd $mainHwnd -Handle ([int64]$hDirect) -Mode "direct_legal_handle"
        if ($hitDirect) {
            $selectedByRealClick = $true
            $result.method = "direct_legal_handle"
            break
        }
    }
    if ($selectedByRealClick) { break }

    # 2) Ruta principal estable: flechas desde pestana activa hacia Legal.
    $hitKeyboard = Try-KeyboardNavigateLegal -MainHwnd $mainHwnd -TabHwnd $tabHwnd -XFocus $xCenter -YFocus $yFocus
    if ($hitKeyboard) {
        $selectedByRealClick = $true
        $result.method = "pbtab_keyboard"
        break
    }

    # 3) Respaldo principal: rondas dirigidas recalculando pestaña activa.
    $roundHit = $false
    for ($round = 0; $round -lt 2; $round++) {
        if ([int]$result.realClickAttempts -ge $maxRealAttempts) { break }
        $roundHit = Try-DirectedRoundLegal -MainHwnd $mainHwnd -TabHwnd $tabHwnd -Width $w -Pitch $pitch -XCenterWeighted $xCenterWeighted -XCenter $xCenter -XCenterRightBias $xCenterRightBias
        if ($roundHit) { break }
    }

    if ($roundHit) {
        $selectedByRealClick = $true
        $result.realClickMode = "directed_global"
        $result.method = "pbtab_scan_click"
        break
    }

    # 4) Ultimo intento simple al centro.
    $hitCenterB = Try-RealClickLegal -MainHwnd $mainHwnd -TabHwnd $tabHwnd -X $xCenter -Y $yFocus -Mode "guided_global_attempt"
    if ($hitCenterB) {
        $selectedByRealClick = $true
        $result.realClickMode = "global_mouse"
        $result.method = "pbtab_scan_click"
        break
    }
}

if (-not $selectedByRealClick) {
    $result.fallbackReason = "real_keyboard_and_click_not_confirmed"
}

$activeAfter = Get-VisiblePeerPage -Peers $peerPages
$result.activePageAfter = if ($activeAfter.Count -eq 0) { $null } else { [string]$activeAfter[0].title }

$postLegalVisible = [Win32LegalTabSwitcher]::IsVisible($legalHandle)
$postDeudorVisible = if ($deudorPage.Count -eq 0) { $false } else { [Win32LegalTabSwitcher]::IsVisible([int64]$deudorPage[0].hwnd) }
$afterNorm = Normalize-UiText $result.activePageAfter

$result.selected = $result.realClickHit -and $postLegalVisible -and $afterNorm.Contains("legal")
$result.panelChanged = ($result.activePageBefore -ne $result.activePageAfter) -or ($preLegalVisible -ne $postLegalVisible) -or ($preDeudorVisible -ne $postDeudorVisible)
$result.ok = $result.selected
Add-AttemptTrace -Phase "final_state" -Mode $result.method -TargetHwnd $legalHandle -ActiveBefore $result.activePageBefore -ActiveAfter $result.activePageAfter -Confirmed ([bool]$result.ok) -Note ("postLegalVisible=" + [string]$postLegalVisible)

if (-not $result.ok) {
    $result.error = "No se pudo activar Legal."
}

$result | ConvertTo-Json -Depth 6 -Compress
