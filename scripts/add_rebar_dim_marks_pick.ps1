# Creates rebar dimension marks for rebar groups with no manual click.
# Cause of "no dim mark created" (found 2026-11-16): acmd_create_marks_selected / RebarNewDimMark waits for
# "Pick position" in the drawing window. Without a pick nothing is created. This script answers the pick by
# posting a left click (WM_LBUTTONDOWN/UP) to the akit view window ("View_NN window_1"), then Escape to end the command.
# Then dim_modify with the same file stores prefix/tags in the new marks (RebarNewDimMark leaves them empty).
# Move the dim line afterwards with set_dim_line_y.ps1 (the pick only sets a rough position).
param([Parameter(Mandatory)][int[]]$RebarIds, [string]$ViewName = "U", [string]$ViewType = "SectionView",
      [string]$PropertyFile = "WH_ArialNarr_2mm_Trans_Rebar Dim_no pic_cc max",
      [string]$TeklaDir = "C:\TeklaClaude\TeklaMcp\Tekla2020", [string]$MacroDir = "C:\TeklaStructures\2020.0\Environments\common\macros\drawings")
$env:SESSIONNAME = "Console"
Add-Type -Path "$TeklaDir\Tekla.Structures.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Model.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Drawing.dll"
if (-not ('TkWin' -as [type])) { Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class TkWin { public delegate bool CB(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(CB cb, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, CB cb, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
 public struct RECT { public int L, T, R, B; }
 public static IntPtr Find(uint pid, string prefix) { IntPtr found = IntPtr.Zero;
  EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p != pid) return true;
   EnumChildWindows(h, (c, x) => { var t = new StringBuilder(256); GetWindowText(c, t, 256);
    if (found == IntPtr.Zero && IsWindowVisible(c) && t.ToString().StartsWith(prefix) && t.ToString().EndsWith("window_1")) found = c; return true; }, IntPtr.Zero);
   return true; }, IntPtr.Zero); return found; }
 public static string Title(IntPtr h) { var t = new StringBuilder(256); GetWindowText(h, t, 256); return t.ToString(); }
}
"@ }
$dh = New-Object Tekla.Structures.Drawing.DrawingHandler; $dwg = $dh.GetActiveDrawing()
$tv = $null; $ve = $dwg.GetSheet().GetAllViews()
while ($ve.MoveNext()) { $v = $ve.Current; if ($v -is [Tekla.Structures.Drawing.View] -and $v.Name -eq $ViewName -and "$($v.ViewType)" -eq $ViewType) { $tv = $v } }
if (-not $tv) { throw "view not found" }
if ($dwg.IsFrozen) { throw "drawing is frozen: dialog commands do nothing. Ask the user before unfreezing." }
function Key($s) { $se = $s.GetObjects(); $k = ""; while ($se.MoveNext()) { $d = $se.Current; if ($d -is [Tekla.Structures.Drawing.StraightDimension]) { $k += "{0:F0},{1:F0},{2:F0},{3:F0};" -f $d.StartPoint.X,$d.StartPoint.Y,$d.EndPoint.X,$d.EndPoint.Y } }; $k }
function Keys { $r = @(); $e = $tv.GetAllObjects(); while ($e.MoveNext()) { $s = $e.Current; if ($s -is [Tekla.Structures.Drawing.StraightDimensionSet]) { $r += (Key $s) } }; $r }
function RunMacro($name, $body) {
  @"
#pragma warning disable 1633
#pragma reference "Tekla.Macros.Akit"
#pragma reference "Tekla.Macros.Runtime"
#pragma warning restore 1633
namespace UserMacros { public sealed class Macro { [Tekla.Macros.Runtime.MacroEntryPointAttribute()]
public static void Run(Tekla.Macros.Runtime.IMacroRuntime runtime) {
Tekla.Macros.Akit.IAkitScriptHost akit = runtime.Get<Tekla.Macros.Akit.IAkitScriptHost>();
$body
}}}
"@ | Set-Content -Path (Join-Path $MacroDir $name) -Encoding utf8
  [void][Tekla.Structures.Model.Operations.Operation]::RunMacro("..\drawings\$name") }
$p = Get-Process TeklaStructures | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$hv = [TkWin]::Find([uint32]$p.Id, "View_"); if ($hv -eq [IntPtr]::Zero) { throw "drawing view window (View_NN window_1) not found" }
$win = [TkWin]::Title($hv); "akit window: $win"
$before = @(Keys)
$al = New-Object System.Collections.ArrayList
$e = $tv.GetAllObjects(); while ($e.MoveNext()) { $o = $e.Current; if ($o -is [Tekla.Structures.Drawing.ReinforcementBase] -and $RebarIds -contains $o.ModelIdentifier.ID) { [void]$al.Add($o) } }
"rebars found: $($al.Count) / $($RebarIds.Count)"
$sel = $dh.GetDrawingObjectSelector(); [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($al, $false)
try {
  RunMacro "Claude_DimMark.cs" @"
akit.Callback("acmd_display_attr_dialog", "rebar_dim_dial", "main_frame");
akit.ValueChange("rebar_dim_dial", "gr_dim_get_menu", "$PropertyFile");
akit.PushButton("gr_dim_get", "rebar_dim_dial");
akit.PushButton("dim_apply", "rebar_dim_dial");
akit.PushButton("dim_ok", "rebar_dim_dial");
akit.Callback("acmd_create_marks_selected", "RebarNewDimMark", "$win");
"@
  Start-Sleep -Milliseconds 1500
  # answer "Pick position": click in the middle of the view window (client coords), then Escape ends the command
  $r = New-Object TkWin+RECT; [void][TkWin]::GetClientRect($hv, [ref]$r)
  $x = [int](($r.R - $r.L) / 2); $y = [int](($r.B - $r.T) / 2); $lp = [IntPtr](($y -shl 16) -bor $x)
  [void][TkWin]::PostMessage($hv, 0x0200, [IntPtr]0, $lp); Start-Sleep -Milliseconds 200
  [void][TkWin]::PostMessage($hv, 0x0201, [IntPtr]1, $lp); Start-Sleep -Milliseconds 100
  [void][TkWin]::PostMessage($hv, 0x0202, [IntPtr]0, $lp); Start-Sleep -Milliseconds 1500
  [void][TkWin]::PostMessage($hv, 0x0100, [IntPtr]0x1B, [IntPtr]0x00010001); [void][TkWin]::PostMessage($hv, 0x0101, [IntPtr]0x1B, [IntPtr]0xC0010001)
  $deadline = (Get-Date).AddSeconds(10)
  do { Start-Sleep -Milliseconds 700; $new = @(Keys | Where-Object { $before -notcontains $_ }) } until ($new.Count -ge $al.Count -or (Get-Date) -gt $deadline)
  "new dim sets: $($new.Count)"
  if ($new.Count -gt 0) {
    $nl = New-Object System.Collections.ArrayList
    $e = $tv.GetAllObjects(); while ($e.MoveNext()) { $s = $e.Current; if ($s -is [Tekla.Structures.Drawing.StraightDimensionSet] -and $new -contains (Key $s)) { [void]$nl.Add($s) } }
    [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($nl, $false)
    RunMacro "Claude_DimMarkModify.cs" @"
akit.Callback("acmd_display_attr_dialog", "rebar_dim_dial", "main_frame");
akit.ValueChange("rebar_dim_dial", "gr_dim_get_menu", "$PropertyFile");
akit.PushButton("gr_dim_get", "rebar_dim_dial");
akit.PushButton("dim_modify", "rebar_dim_dial");
akit.PushButton("dim_ok", "rebar_dim_dial");
"@
    Start-Sleep -Seconds 2
  }
} finally { Get-ChildItem $MacroDir -Filter "Claude_DimMark*.cs*" | Remove-Item -Force -ErrorAction SilentlyContinue }
$e = $tv.GetAllObjects(); while ($e.MoveNext()) { $s = $e.Current
  if ($s -is [Tekla.Structures.Drawing.StraightDimensionSet] -and $new -contains (Key $s)) {
    $rel = @(); $q = $s.GetRelatedObjects(); while ($q.MoveNext()) { if ($q.Current -is [Tekla.Structures.Drawing.ModelObject]) { $rel += $q.Current.ModelIdentifier.ID } }
    $se = $s.GetObjects(); while ($se.MoveNext()) { $d = $se.Current; if ($d -is [Tekla.Structures.Drawing.StraightDimension]) {
      "NEW ({0:F0},{1:F0})-({2:F0},{3:F0}) up=({4:F0},{5:F0}) line y={6:F0} rebar {7}" -f $d.StartPoint.X,$d.StartPoint.Y,$d.EndPoint.X,$d.EndPoint.Y,$d.UpDirection.X,$d.UpDirection.Y,($d.StartPoint.Y + $d.UpDirection.Y * $s.Distance),($rel -join ','); break } } } }
