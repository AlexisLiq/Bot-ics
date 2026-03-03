$script:IcsWindowCommonInitError = $null

. (Join-Path $PSScriptRoot "_common-utils.ps1")

function Initialize-IcsWindowCommonType {
    if ("Win32IcsWindowCommon" -as [type]) {
        return $true
    }

    $win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32IcsWindowCommon
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);

    private const int SW_RESTORE = 9;

    public sealed class TopWindowInfo
    {
        public long Hwnd { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
        public bool Visible { get; set; }
        public bool Iconic { get; set; }
    }

    public static List<TopWindowInfo> SnapshotWindows()
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
                Visible = IsWindowVisible(hWnd),
                Iconic = IsIconic(hWnd)
            });
            return true;
        }, IntPtr.Zero);
        return list;
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

    try {
        Add-Type -TypeDefinition $win32Source -Language CSharp -ErrorAction Stop
        return $true
    } catch {
        $script:IcsWindowCommonInitError = $_.Exception.Message
        return $false
    }
}

function Get-IcsWindowCommonInitError {
    return $script:IcsWindowCommonInitError
}

function Find-IcsWindow {
    param([string]$WindowTitleHint = "Internet Collection System")

    $hint = ""
    if (-not [string]::IsNullOrWhiteSpace($WindowTitleHint)) {
        $hint = $WindowTitleHint.ToLowerInvariant().Trim()
    }

    $wins = [Win32IcsWindowCommon]::SnapshotWindows()
    $candidates = foreach ($w in $wins) {
        if (-not $w.Visible -or $w.Iconic) { continue }
        if ([string]::IsNullOrWhiteSpace($w.Title)) { continue }

        $title = $w.Title.ToLowerInvariant()
        if (-not $title.Contains("internet collection system") -and (-not $hint -or -not $title.Contains($hint))) {
            continue
        }

        $proc = Get-ProcessNameSafe -ProcId ([int]$w.ProcessId)
        if ([string]::IsNullOrWhiteSpace($proc)) { continue }

        $procNorm = $proc.ToLowerInvariant()
        if ($procNorm -eq "java" -or $procNorm.Contains("javaws") -or $procNorm.Contains("javaw") -or $procNorm.Contains("jp2launcher")) {
            continue
        }

        [pscustomobject]@{
            hwnd = [string]$w.Hwnd
            processName = $proc
            title = [string]$w.Title
            isIcsProcess = $procNorm.Contains("ics_client")
        }
    }

    if (-not $candidates) { return $null }
    return $candidates |
        Sort-Object @{ Expression = { -not $_.isIcsProcess } }, @{ Expression = { $_.title.Length * -1 } } |
        Select-Object -First 1
}
