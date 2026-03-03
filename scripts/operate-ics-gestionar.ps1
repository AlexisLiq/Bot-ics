param(
    [string]$MainWindowHwnd,
    [string]$IdentificationInputHwnd,
    [string]$BuscarButtonHwnd,
    [string]$Cedula,
    [int]$StepDelayMs = 450,
    [int]$BeforeLegalDelayMs = 1200
)

$ErrorActionPreference = "SilentlyContinue"

. (Join-Path $PSScriptRoot "_common-utils.ps1")

$win32Source = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class Win32IcsOps
{
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

    [StructLayout(LayoutKind.Sequential)]
    private struct NMHDR
    {
        public IntPtr hwndFrom;
        public UIntPtr idFrom;
        public int code;
    }

    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hWnd, ref POINT pt);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool SetWindowTextW(IntPtr hWnd, string text);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")] private static extern IntPtr SendMessageText(IntPtr hWnd, uint msg, IntPtr wParam, string lParam);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")] private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")] private static extern IntPtr SendMessageRect(IntPtr hWnd, uint msg, IntPtr wParam, ref RECT lParam);
    [DllImport("user32.dll", EntryPoint = "SendMessageW")] private static extern IntPtr SendMessageNotify(IntPtr hWnd, uint msg, IntPtr wParam, ref NMHDR lParam);
    [DllImport("user32.dll")] private static extern bool PostMessageW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);

    private const int SW_RESTORE = 9;
    private const uint WM_SETTEXT = 0x000C;
    private const uint WM_NOTIFY = 0x004E;
    private const uint BM_CLICK = 0x00F5;
    private const uint TCM_GETCURSEL = 0x130B;
    private const uint TCM_SETCURSEL = 0x130C;
    private const uint TCM_GETITEMRECT = 0x130A;
    private const uint WM_LBUTTONDOWN = 0x0201;
    private const uint WM_LBUTTONUP = 0x0202;
    private const int MK_LBUTTON = 0x0001;
    private const int TCN_SELCHANGE = -551;
    private const int TCN_SELCHANGING = -552;

    public static bool Exists(long hwnd)
    {
        try { return IsWindow(new IntPtr(hwnd)); } catch { return false; }
    }

    public static bool Activate(long hwnd)
    {
        try
        {
            var h = new IntPtr(hwnd);
            ShowWindow(h, SW_RESTORE);
            return SetForegroundWindow(h);
        }
        catch { return false; }
    }

    public static bool SetText(long hwnd, string value)
    {
        try
        {
            var h = new IntPtr(hwnd);
            bool a = SetWindowTextW(h, value ?? string.Empty);
            bool b = SendMessageText(h, WM_SETTEXT, IntPtr.Zero, value ?? string.Empty) != IntPtr.Zero;
            return a || b;
        }
        catch { return false; }
    }

    public static string ReadText(long hwnd)
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

    public static bool SelectTab(long tabHwnd, int index)
    {
        if (!Exists(tabHwnd)) return false;

        var tab = ResolveTabControl(new IntPtr(tabHwnd));
        if (tab == IntPtr.Zero) return false;

        bool byIndexClick = ClickTabIndex(tab, index);
        if (GetTabSelection(tab) == index) return true;

        bool byMessage = false;
        try
        {
            NotifyParentTabChange(tab, TCN_SELCHANGING);
            SendMessage(tab, TCM_SETCURSEL, new IntPtr(index), IntPtr.Zero);
            NotifyParentTabChange(tab, TCN_SELCHANGE);
            byMessage = GetTabSelection(tab) == index;
        }
        catch { }

        bool byParentClick = ClickParentAtChildCenter(tabHwnd);
        bool byDirectClick = ClickMouseCenter(tabHwnd);

        int current = GetTabSelection(tab);
        if (current >= 0) {
            return current == index;
        }

        return byIndexClick || byMessage || byParentClick || byDirectClick;
    }

    public static int GetTabSelectionFromChild(long tabHwnd)
    {
        if (!Exists(tabHwnd)) return -1;
        try
        {
            var tab = ResolveTabControl(new IntPtr(tabHwnd));
            if (tab == IntPtr.Zero) return -1;
            return GetTabSelection(tab);
        }
        catch { return -1; }
    }

    public static bool ClickButton(long hwnd)
    {
        if (!Exists(hwnd)) return false;
        try
        {
            var h = new IntPtr(hwnd);
            SendMessage(h, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
            return true;
        }
        catch { return false; }
    }

    public static bool ClickMouseCenter(long hwnd)
    {
        if (!Exists(hwnd)) return false;
        try
        {
            var h = new IntPtr(hwnd);
            RECT rect;
            if (!GetClientRect(h, out rect)) return false;

            int width = Math.Max(2, rect.Right - rect.Left);
            int height = Math.Max(2, rect.Bottom - rect.Top);
            int x = Math.Max(1, width / 2);
            int y = Math.Max(1, height / 2);
            int lParam = ((y & 0xFFFF) << 16) | (x & 0xFFFF);

            bool down = PostMessageW(h, WM_LBUTTONDOWN, new IntPtr(MK_LBUTTON), new IntPtr(lParam));
            bool up = PostMessageW(h, WM_LBUTTONUP, IntPtr.Zero, new IntPtr(lParam));
            return down && up;
        }
        catch { return false; }
    }

    public static bool ClickParentAtChildCenter(long childHwnd)
    {
        if (!Exists(childHwnd)) return false;
        try
        {
            var child = new IntPtr(childHwnd);
            var parent = GetParent(child);
            if (parent == IntPtr.Zero) return false;

            RECT childRect;
            if (!GetWindowRect(child, out childRect)) return false;

            var pt = new POINT
            {
                X = childRect.Left + Math.Max(1, (childRect.Right - childRect.Left) / 2),
                Y = childRect.Top + Math.Max(1, (childRect.Bottom - childRect.Top) / 2)
            };
            if (!ScreenToClient(parent, ref pt)) return false;

            int lParam = ((pt.Y & 0xFFFF) << 16) | (pt.X & 0xFFFF);
            bool down = PostMessageW(parent, WM_LBUTTONDOWN, new IntPtr(MK_LBUTTON), new IntPtr(lParam));
            bool up = PostMessageW(parent, WM_LBUTTONUP, IntPtr.Zero, new IntPtr(lParam));
            return down && up;
        }
        catch { return false; }
    }

    private static IntPtr ResolveTabControl(IntPtr maybeTabOrChild)
    {
        try
        {
            if (maybeTabOrChild == IntPtr.Zero) return IntPtr.Zero;

            string cls = GetClass(maybeTabOrChild);
            if (cls.Contains("systabcontrol32")) return maybeTabOrChild;

            var parent = GetParent(maybeTabOrChild);
            if (parent == IntPtr.Zero) return IntPtr.Zero;
            string pcls = GetClass(parent);
            if (pcls.Contains("systabcontrol32")) return parent;

            return parent;
        }
        catch { return IntPtr.Zero; }
    }

    private static int GetTabSelection(IntPtr tab)
    {
        try
        {
            var sel = SendMessage(tab, TCM_GETCURSEL, IntPtr.Zero, IntPtr.Zero).ToInt64();
            if (sel < 0 || sel > int.MaxValue) return -1;
            return (int)sel;
        }
        catch { return -1; }
    }

    private static bool ClickTabIndex(IntPtr tab, int index)
    {
        try
        {
            if (tab == IntPtr.Zero || index < 0) return false;
            RECT item = new RECT();
            var ok = SendMessageRect(tab, TCM_GETITEMRECT, new IntPtr(index), ref item);
            if (ok == IntPtr.Zero) return false;

            int x = Math.Max(1, item.Left + Math.Max(1, (item.Right - item.Left) / 2));
            int y = Math.Max(1, item.Top + Math.Max(1, (item.Bottom - item.Top) / 2));
            int lParam = ((y & 0xFFFF) << 16) | (x & 0xFFFF);

            bool down = PostMessageW(tab, WM_LBUTTONDOWN, new IntPtr(MK_LBUTTON), new IntPtr(lParam));
            bool up = PostMessageW(tab, WM_LBUTTONUP, IntPtr.Zero, new IntPtr(lParam));
            return down && up;
        }
        catch { return false; }
    }

    private static bool NotifyParentTabChange(IntPtr tab, int code)
    {
        try
        {
            if (tab == IntPtr.Zero) return false;
            var parent = GetParent(tab);
            if (parent == IntPtr.Zero) return false;
            int id = GetDlgCtrlID(tab);
            if (id < 0) id = 0;

            var hdr = new NMHDR
            {
                hwndFrom = tab,
                idFrom = (UIntPtr)(uint)id,
                code = code
            };

            SendMessageNotify(parent, WM_NOTIFY, new IntPtr(id), ref hdr);
            return true;
        }
        catch { return false; }
    }

    private static string GetClass(IntPtr hWnd)
    {
        var sb = new StringBuilder(256);
        GetClassNameW(hWnd, sb, sb.Capacity);
        return sb.ToString().ToLowerInvariant();
    }
}
"@

$result = [ordered]@{
    ok = $false
    windowActivated = $false
    legalTargetIndex = 5
    legalSelectedIndex = -1
    steps = [ordered]@{
        legalSelected = $false
        legalConfirmed = $false
        identificationSet = $false
        buscarClicked = $false
    }
    identificationReadback = $null
    error = $null
}

if ([string]::IsNullOrWhiteSpace($Cedula)) {
    $result.error = "Falta la cedula para ejecutar la busqueda en Gestionar."
    $result | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

try {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Stop"
    Add-Type -TypeDefinition $win32Source -Language CSharp
    $ErrorActionPreference = $oldEap
} catch {
    $result.error = "Add-Type Win32IcsOps failed: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

$mainHwnd = Parse-Handle $MainWindowHwnd
$inputHwnd = Parse-Handle $IdentificationInputHwnd
$buscarHwnd = Parse-Handle $BuscarButtonHwnd

if ($mainHwnd -eq 0 -or -not [Win32IcsOps]::Exists($mainHwnd)) {
    $result.error = "Handle invalido para la ventana principal de ICS."
    $result | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
if ($inputHwnd -eq 0 -or -not [Win32IcsOps]::Exists($inputHwnd)) {
    $result.error = "Handle invalido para el campo de Identificacion."
    $result | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
if ($buscarHwnd -eq 0 -or -not [Win32IcsOps]::Exists($buscarHwnd)) {
    $result.error = "Handle invalido para el boton Buscar."
    $result | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

$result.windowActivated = [Win32IcsOps]::Activate($mainHwnd)
Start-Sleep -Milliseconds $StepDelayMs

$result.steps.identificationSet = [Win32IcsOps]::SetText($inputHwnd, $Cedula)
$result.identificationReadback = [Win32IcsOps]::ReadText($inputHwnd)
Start-Sleep -Milliseconds $StepDelayMs

$result.steps.buscarClicked = [Win32IcsOps]::ClickButton($buscarHwnd)
Start-Sleep -Milliseconds $BeforeLegalDelayMs

$result.ok = $result.steps.identificationSet -and $result.steps.buscarClicked
if (-not $result.ok) {
    $result.error = "No se pudo completar la secuencia Cedula -> Buscar en Gestionar."
}

$result | ConvertTo-Json -Depth 5 -Compress
