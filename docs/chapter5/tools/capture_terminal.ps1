# Runs a command in a real Windows Terminal window and saves a screenshot of that window (only that window) as PNG.
# The window shows the exact command line and its unmodified output.
#   powershell -ExecutionPolicy Bypass -File tools\capture_terminal.ps1 -Title "baymax-unit" -WorkDir <dir> -Command "<cmd>" -Out <png>
param(
  [Parameter(Mandatory)] [string] $Title,
  [Parameter(Mandatory)] [string] $WorkDir,
  [Parameter(Mandatory)] [string] $CommandFile,   # a text file holding the exact command line (keeps its quotes intact)
  [Parameter(Mandatory)] [string] $Out,
  [int] $Cols = 178,
  [int] $Rows = 46,
  [int] $TimeoutSec = 900
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr Find(string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { if (!IsWindowVisible(h)) return true; var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
      if (sb.ToString() == title) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
}
'@
[Win]::SetProcessDPIAware() | Out-Null
$Command = (Get-Content -Raw -Path $CommandFile).Trim()
$marker = Join-Path $env:TEMP "capture_$Title.done"
Remove-Item $marker -ErrorAction SilentlyContinue
$script = Join-Path $env:TEMP "capture_$Title.ps1"
@"
`$Host.UI.RawUI.WindowTitle = '$Title'
`$env:TEMP = 'D:\tmp\flutter'; `$env:TMP = 'D:\tmp\flutter'
Set-Location '$WorkDir'
Write-Host ('PS ' + (Get-Location).Path + '> $($Command.Replace("'", "''"))') -ForegroundColor Yellow
$Command
New-Item -ItemType File -Path '$marker' -Force | Out-Null
"@ | Set-Content -Path $script -Encoding UTF8
Start-Process wt.exe -ArgumentList @('-w', 'new', '--title', $Title, '--suppressApplicationTitle', '--size', "$Cols,$Rows",
  'powershell.exe', '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script)
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while (-not (Test-Path $marker)) {
  if ((Get-Date) -gt $deadline) { throw "timed out waiting for '$Command'" }
  Start-Sleep -Milliseconds 500
}
Start-Sleep -Seconds 2   # let the terminal finish drawing
$h = [Win]::Find($Title)
if ($h -eq [IntPtr]::Zero) { throw "terminal window '$Title' not found" }
[Win]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 700
$r = New-Object Win+RECT
[Win]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [Win]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT: captures this window only
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
[Win]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null   # WM_CLOSE
"saved $Out (${w}x$hgt, PrintWindow=$ok)"
