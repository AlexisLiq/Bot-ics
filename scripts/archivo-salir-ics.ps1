param(
    [string]$WindowTitleHint = "Internet Collection System",
    [int]$TimeoutMs = 12000,
    [int]$PollMs = 120,
    [int]$CommandId = 57665,
    [string]$GestionarWindowHwnd = ""
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_ics-window-common.ps1")
. (Join-Path $PSScriptRoot "_common-utils.ps1")

if (-not (Initialize-IcsWindowCommonType)) {
    [pscustomobject]@{
        ok = $false
        windowFound = $false
        sent = $false
        gestionarClosed = $false
        method = $null
        error = "Add-Type Win32IcsWindowCommon failed: $(Get-IcsWindowCommonInitError)"
    } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}

$menuSource = @"
using System;
using System.Runtime.InteropServices;

public static class Win32IcsArchivoMenuOps
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool PostMessageW(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetMenu(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetSubMenu(IntPtr hMenu, int nPos);
    [DllImport("user32.dll")] private static extern int GetMenuItemCount(IntPtr hMenu);
    [DllImport("user32.dll")] private static extern uint GetMenuItemID(IntPtr hMenu, int nPos);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetMenuStringW(IntPtr hMenu, uint uIDItem, System.Text.StringBuilder lpString, int nMaxCount, uint uFlag);

    private const uint WM_COMMAND = 0x0111;
    private const uint MF_BYPOSITION = 0x0400;

    public static bool PostMenuCommand(long hwnd, int commandId)
    {
        if (commandId <= 0) return false;
        try { return PostMessageW(new IntPtr(hwnd), WM_COMMAND, new IntPtr(commandId), IntPtr.Zero); }
        catch { return false; }
    }

    public static int ResolveArchivoSalirCommandId(long hwnd)
    {
        try
        {
            var root = new IntPtr(hwnd);
            var menu = GetMenu(root);
            if (menu == IntPtr.Zero) return -1;

            int topCount = GetMenuItemCount(menu);
            if (topCount <= 0) return -1;

            int fromArchivo = ResolveFromTopMenu(menu, topCount, true);
            if (fromArchivo > 0) return fromArchivo;

            int fromAny = ResolveFromTopMenu(menu, topCount, false);
            return fromAny > 0 ? fromAny : -1;
        }
        catch { return -1; }
    }

    private static int ResolveFromTopMenu(IntPtr menu, int topCount, bool onlyArchivoTop)
    {
        for (int i = 0; i < topCount; i++)
        {
            string topText = NormalizeMenuText(GetMenuTextByPos(menu, i));
            if (onlyArchivoTop && !topText.Contains("archivo")) continue;

            var sub = GetSubMenu(menu, i);
            if (sub == IntPtr.Zero) continue;

            int subCount = GetMenuItemCount(sub);
            for (int j = 0; j < subCount; j++)
            {
                string itemText = NormalizeMenuText(GetMenuTextByPos(sub, j));
                if (!itemText.Contains("salir")) continue;

                uint id = GetMenuItemID(sub, j);
                if (id != 0xFFFFFFFF && id > 0) return (int)id;
            }
        }
        return -1;
    }

    private static string GetMenuTextByPos(IntPtr menu, int position)
    {
        var sb = new System.Text.StringBuilder(256);
        GetMenuStringW(menu, (uint)position, sb, sb.Capacity, MF_BYPOSITION);
        return sb.ToString();
    }

    private static string NormalizeMenuText(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        string t = text.Replace("&", "");
        int tab = t.IndexOf('\t');
        if (tab >= 0) t = t.Substring(0, tab);
        return t.Trim().ToLowerInvariant();
    }
}
"@

if (-not ("Win32IcsArchivoMenuOps" -as [type])) {
    try {
        Add-Type -TypeDefinition $menuSource -Language CSharp -ErrorAction Stop
    } catch {
        [pscustomobject]@{
            ok = $false
            windowFound = $false
            sent = $false
            gestionarClosed = $false
            method = $null
            error = "Add-Type Win32IcsArchivoMenuOps failed: $($_.Exception.Message)"
        } | ConvertTo-Json -Depth 6 -Compress
        exit 0
    }
}

function Test-GestionarVisibleForPid {
    param([int]$Pid)

    $wins = [Win32IcsWindowCommon]::SnapshotWindows()
    foreach ($w in $wins) {
        if (-not $w.Visible -or $w.Iconic) { continue }
        if ([int]$w.ProcessId -ne $Pid) { continue }

        $titleNorm = Normalize-UiText $w.Title
        if ($titleNorm.Contains("informacion del deudor") -or $titleNorm -eq "deudor") {
            return $true
        }
    }
    return $false
}

function Test-GestionarClosedByHwnd {
    param([int64]$Hwnd)

    if ($Hwnd -eq 0) { return $false }
    $wins = [Win32IcsWindowCommon]::SnapshotWindows()
    $match = @($wins | Where-Object { [string]$_.Hwnd -eq [string]$Hwnd } | Select-Object -First 1)
    if ($match.Count -eq 0) { return $true }

    $w = $match[0]
    if (-not $w.Visible -or $w.Iconic) { return $true }
    return $false
}

$result = [ordered]@{
    ok = $false
    windowFound = $false
    sent = $false
    gestionarClosed = $false
    method = $null
    commandIdUsed = 0
    window = $null
    error = $null
}

$deadline = (Get-Date).AddMilliseconds($TimeoutMs)
$gestionarHwnd = Parse-Handle $GestionarWindowHwnd

while ((Get-Date) -lt $deadline) {
    $window = Find-IcsWindow -WindowTitleHint $WindowTitleHint
    if (-not $window) {
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    $result.windowFound = $true
    $result.window = $window

    $hwnd = Parse-Handle $window.hwnd
    if ($hwnd -eq 0) {
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    [void][Win32IcsWindowCommon]::ActivateWindow($hwnd)
    Start-Sleep -Milliseconds 120

    $allWins = [Win32IcsWindowCommon]::SnapshotWindows()
    $currentWin = @($allWins | Where-Object { [string]$_.Hwnd -eq [string]$window.hwnd } | Select-Object -First 1)
    $mainPid = if ($currentWin.Count -gt 0) { [int]$currentWin[0].ProcessId } else { 0 }

    if ($gestionarHwnd -ne 0 -and $gestionarHwnd -eq $hwnd) {
        $gestionarHwnd = 0
    }

    $resolvedCommandId = [int]$CommandId
    $dynamicCommandId = [Win32IcsArchivoMenuOps]::ResolveArchivoSalirCommandId($hwnd)
    if ($dynamicCommandId -gt 0) {
        $resolvedCommandId = [int]$dynamicCommandId
    }

    if ([Win32IcsArchivoMenuOps]::PostMenuCommand($hwnd, $resolvedCommandId)) {
        $result.sent = $true
        $result.method = "wm_command"
        $result.commandIdUsed = $resolvedCommandId
    }

    if (-not $result.sent) {
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    if ($mainPid -le 0) {
        $result.gestionarClosed = $true
        $result.ok = $true
        break
    }

    $closeDeadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $closeDeadline) {
        $closed = $false
        if ($gestionarHwnd -ne 0) {
            $closed = Test-GestionarClosedByHwnd -Hwnd $gestionarHwnd
        } else {
            $closed = -not (Test-GestionarVisibleForPid -Pid $mainPid)
        }

        if ($closed) {
            $result.gestionarClosed = $true
            $result.ok = $true
            break
        }
        Start-Sleep -Milliseconds $PollMs
    }

    if ($result.ok) { break }
    $result.error = "Se envio Archivo -> Salir, pero la ventana Gestionar sigue visible."
    break
}

if (-not $result.windowFound) {
    $result.error = "No se encontro ventana principal de ICS para enviar Archivo -> Salir."
} elseif (-not $result.sent) {
    $result.error = "No se pudo invocar Archivo -> Salir por WM_COMMAND."
} elseif (-not $result.gestionarClosed) {
    if (-not $result.error) {
        $result.error = "Archivo -> Salir no cerro la ventana Gestionar."
    }
}

$result | ConvertTo-Json -Depth 7 -Compress
