param(
    [int]$TimeoutMs = 45000,
    [int]$PollMs = 500
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

Add-Type -AssemblyName System.Core
$wsh = $null
try { $wsh = New-Object -ComObject WScript.Shell } catch { $wsh = $null }

$win32Source = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32JavaModalWatcher
{
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr hWndParent, EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr SendMessageW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private const uint BM_CLICK = 0x00F5;
    private const int SW_RESTORE = 9;
    private const int SW_SHOW = 5;

    public sealed class ChildWindowInfo
    {
        public long Hwnd { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
    }

    public sealed class TopLevelWindowInfo
    {
        public long Hwnd { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool Visible { get; set; }
        public List<ChildWindowInfo> Children { get; set; }

        public TopLevelWindowInfo()
        {
            this.Children = new List<ChildWindowInfo>();
        }
    }

    public static List<TopLevelWindowInfo> SnapshotTopLevelWindows(int maxChildrenPerWindow)
    {
        var list = new List<TopLevelWindowInfo>();
        EnumWindows((hWnd, lParam) =>
        {
            var info = new TopLevelWindowInfo
            {
                Hwnd = hWnd.ToInt64(),
                ProcessId = GetPid(hWnd),
                Title = GetText(hWnd),
                ClassName = GetClass(hWnd),
                Visible = IsWindowVisible(hWnd)
            };

            int childCount = 0;
            EnumChildWindows(hWnd, (child, l2) =>
            {
                if (childCount >= maxChildrenPerWindow)
                {
                    return false;
                }

                info.Children.Add(new ChildWindowInfo
                {
                    Hwnd = child.ToInt64(),
                    Title = GetText(child),
                    ClassName = GetClass(child),
                    Visible = IsWindowVisible(child)
                });
                childCount++;
                return true;
            }, IntPtr.Zero);

            list.Add(info);
            return true;
        }, IntPtr.Zero);

        return list;
    }

    public static bool ClickWindow(long hwnd)
    {
        try
        {
            SendMessageW(new IntPtr(hwnd), BM_CLICK, IntPtr.Zero, IntPtr.Zero);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static bool ActivateWindow(long hwnd)
    {
        try
        {
            var h = new IntPtr(hwnd);
            ShowWindow(h, SW_RESTORE);
            ShowWindow(h, SW_SHOW);
            return SetForegroundWindow(h);
        }
        catch
        {
            return false;
        }
    }

    public static bool WindowExists(long hwnd)
    {
        try
        {
            return IsWindow(new IntPtr(hwnd));
        }
        catch
        {
            return false;
        }
    }

    private static uint GetPid(IntPtr hWnd)
    {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return pid;
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
    [ordered]@{
        updatePromptSeen = $false
        updatePromptHandled = $false
        runPromptSeen = $false
        runPromptHandled = $false
        actions = @()
        observations = @()
        errors = @("Add-Type Win32 watcher failed: " + $_.Exception.Message)
    } | ConvertTo-Json -Depth 4 -Compress
    exit 0
}

function Find-ChildByText {
    param(
        $Children,
        [string[]]$Candidates
    )
    foreach ($child in @($Children)) {
        $childTextNorm = Normalize-UiText $child.Title
        if (-not $childTextNorm) { continue }
        foreach ($candidate in $Candidates) {
            $candNorm = Normalize-UiText $candidate
            if ($candNorm -and ($childTextNorm -eq $candNorm -or $childTextNorm.Contains($candNorm))) {
                return $child
            }
        }
    }
    return $null
}

function Select-ButtonLikeChildren {
    param($Children)
    return @($Children | Where-Object {
        $classNorm = Normalize-UiText $_.ClassName
        $titleNorm = Normalize-UiText $_.Title
        $classNorm.Contains("button") -or
        $classNorm.Contains("windowsforms10.button") -or
        $titleNorm -in @("ejecutar", "run", "cancelar", "cancel", "mas tarde", "later")
    })
}

function SleepMs {
    param([int]$Ms)
    Start-Sleep -Milliseconds $Ms
}

$updateLaterCandidates = @("Mas tarde", "Later")
$result = [ordered]@{
    updatePromptSeen = $false
    updatePromptHandled = $false
    runPromptSeen = $false
    runPromptHandled = $false
    actions = @()
    observations = @()
    errors = @()
}

$hotkeyAttempts = @{}
$deadline = (Get-Date).AddMilliseconds($TimeoutMs)

while ((Get-Date) -lt $deadline) {
    try {
        $snapshot = [Win32JavaModalWatcher]::SnapshotTopLevelWindows(60)

        foreach ($w in $snapshot) {
            if ($result.runPromptHandled) { break }
            if (-not $w.Visible) { continue }

            $procName = Get-ProcessNameSafe -ProcId ([int]$w.ProcessId)
            $procNorm = Normalize-UiText $procName
            if (-not $procNorm) { continue }

            $classNorm = Normalize-UiText $w.ClassName
            $titleNorm = Normalize-UiText $w.Title
            $buttons = Select-ButtonLikeChildren -Children $w.Children

            #Verificamos si es el prompt de actualización de Java y hacemos click en "Más tarde" si no lo hemos manejado ya
            if ((Contains-AnyToken -Haystack $procNorm -Tokens @("jucheck", "jusched")) -and (-not $result.updatePromptHandled)) {
                $laterButton = Find-ChildByText -Children $buttons -Candidates $updateLaterCandidates
                if ($laterButton) {
                    $result.updatePromptSeen = $true
                    if ([Win32JavaModalWatcher]::ClickWindow([int64]$laterButton.Hwnd)) {
                        $result.updatePromptHandled = $true
                        $result.actions += [pscustomobject]@{
                            type = "java_update_later"
                            button = $laterButton.Title
                            process = $procName
                            pid = [int]$w.ProcessId
                            title = $w.Title
                            hwnd = [string]$w.Hwnd
                            timestamp = (Get-Date).ToString("s")
                        }
                        SleepMs 700
                        continue
                    }
                }
            }
    
            # Verificamos si es el prompt de seguridad de Java y enviamos ALT+R para intentar hacer click en "Ejecutar" si no lo hemos manejado ya
            $isSecurity =
                (Contains-AnyToken -Haystack $procNorm -Tokens @("jp2launcher")) -and
                (Contains-AnyToken -Haystack $classNorm -Tokens @("sunawtdialog")) -and
                (Contains-AnyToken -Haystack $titleNorm -Tokens @("informacion de seguridad", "security")) -and
                (-not (Contains-AnyToken -Haystack $titleNorm -Tokens @("iniciando aplicacion", "starting application")))

            if ($isSecurity -and (-not $result.runPromptHandled)) {
                $result.runPromptSeen = $true

                $hotkeyKey = "hwnd|$($w.Hwnd)"
                if (-not $hotkeyAttempts.ContainsKey($hotkeyKey)) {
                    $hotkeyAttempts[$hotkeyKey] = 0
                }

                if ([int]$hotkeyAttempts[$hotkeyKey] -lt 1) {
                    $hotkeyAttempts[$hotkeyKey] = [int]$hotkeyAttempts[$hotkeyKey] + 1

                    if ($null -ne $wsh) {
                        [void][Win32JavaModalWatcher]::ActivateWindow([int64]$w.Hwnd)
                        Start-Sleep -Milliseconds 200
                        $wsh.SendKeys("%r")
                        $result.actions += [pscustomobject]@{
                            type = "java_security_hotkey_attempt"
                            button = "ALT+R"
                            process = $procName
                            pid = [int]$w.ProcessId
                            title = $w.Title
                            hwnd = [string]$w.Hwnd
                            timestamp = (Get-Date).ToString("s")
                        }

                        Start-Sleep -Milliseconds 700
                        if (-not [Win32JavaModalWatcher]::WindowExists([int64]$w.Hwnd)) {
                            $result.runPromptHandled = $true
                            $result.actions += [pscustomobject]@{
                                type = "java_security_hotkey_success"
                                button = "ALT+R"
                                process = $procName
                                pid = [int]$w.ProcessId
                                title = $w.Title
                                hwnd = [string]$w.Hwnd
                                timestamp = (Get-Date).ToString("s")
                            }
                            break
                        }
                    }
                }
            }
        }

        if ($result.runPromptHandled) { break }
    } catch {
        $result.errors += [string]$_.Exception.Message
    }

    SleepMs $PollMs
}

$result | ConvertTo-Json -Depth 6 -Compress
