# Move (default) or copy the drawing objects that are SELECTED in Tekla by (DX, DY), with no screen picks.
# Works for objects the API cannot see (cover-ups): the user selects them, this script moves them exactly.
# Names come from macros the user recorded in a Tekla 2020 drawing (2026-11-11):
#   Copy special > Linear...: CommandStart("ail_grCopyObjects", "", <window>), dialog grCopy, fields dx / dy,
#     buttons gr_copy_apply then gr_copy_cancel, then wpf Common.Interrupt (else Tekla stays in "Pick two points").
#   Delete: Callback("acmd_delete_selected_dr", "", <window>).
# Drawings have no numeric Move dialog (Move > Linear only picks two points), so Move = copy, then delete the
# originals (they stay selected after the copy). Tested on a sheet text: dy 9.375 moved it exactly 9.375.
# Units: sheet mm for sheet-level objects (BBS row 9.375, next table 67.1 on PPVC12 W_4010).
# -SelectIds: optionally select these sheet-level objects through the API first (else keeps the user's selection).
#
# Selection guard (always on, before anything runs):
#   - Refuses when the selection holds anything that is not a plain 2D graphic/text (Plugin, marks, dimensions,
#     views, parts...): the macro would copy + delete those too. -Force skips this check.
#   - -Box "x1,y1,x2,y2" (sheet mm): every API-visible object must lie fully inside this box, i.e. inside the band
#     of BBS rows that share this one offset. Stops a stray object from another cell group being moved.
#   - -DryRun: only print the check, never run the macro.
#   Cover-ups are invisible to the API: the guard cannot count or check them. The user checks them by eye.
param([double]$DX = 0, [double]$DY = 0, [switch]$Copy, [int[]]$SelectIds = @(), [string]$Window = "View_10 window_1",
      [string]$Box = "", [switch]$DryRun, [switch]$Force,
      [string]$TeklaDir = "D:\TeklaClaude\TeklaMcp\Tekla2020",
      [string]$MacroDir = "C:\TeklaStructures\2020.0\Environments\common\macros\drawings")
if (-not $env:SESSIONNAME) { $env:SESSIONNAME = "Console" }
Add-Type -Path "$TeklaDir\Tekla.Structures.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Model.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Drawing.dll"
$dh = New-Object Tekla.Structures.Drawing.DrawingHandler; $dwg = $dh.GetActiveDrawing()
if (-not $dwg) { throw "no active drawing" }
$inv = [Globalization.CultureInfo]::InvariantCulture
$idProp = [Tekla.Structures.Drawing.DatabaseObject].GetProperty("Identifier", [Reflection.BindingFlags]"NonPublic,Public,Instance")
if ($SelectIds.Count) {
  $al = New-Object System.Collections.ArrayList; $e = $dwg.GetSheet().GetAllObjects()
  while ($e.MoveNext()) { if ($SelectIds -contains $idProp.GetValue($e.Current, $null).ID) { [void]$al.Add($e.Current) } }
  $sel = $dh.GetDrawingObjectSelector(); [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($al, $false)
  "selected through API: $($al.Count) / $($SelectIds.Count)"
}

# ---- selection guard ----
$okTypes = @('Line', 'Polyline', 'Polygon', 'Text', 'Circle', 'Arc', 'Rectangle', 'Cloud', 'Symbol')
function Pts($o) {
  switch ($o.GetType().Name) {
    'Line'      { @($o.StartPoint, $o.EndPoint) }
    'Arc'       { @($o.StartPoint, $o.EndPoint) }
    'Polyline'  { @($o.Points) }
    'Polygon'   { @($o.Points) }
    'Cloud'     { @($o.Points) }
    'Text'      { @($o.InsertionPoint) }
    'Symbol'    { @($o.InsertionPoint) }
    'Circle'    { @($o.CenterPoint) }
    'Rectangle' { @($o.StartPoint) }
    default     { @() } } }
$bx = $null
if ($Box) { $bx = @($Box.Split(',') | % { [double]::Parse($_.Trim(), $inv) })
  if ($bx.Count -ne 4) { throw "-Box needs x1,y1,x2,y2" }
  $bx = @([math]::Min($bx[0], $bx[2]), [math]::Min($bx[1], $bx[3]), [math]::Max($bx[0], $bx[2]), [math]::Max($bx[1], $bx[3])) }
$bad = @(); $out = @(); $n = 0; $byType = @{}
$xmin = 1e9; $ymin = 1e9; $xmax = -1e9; $ymax = -1e9
$g = $dh.GetDrawingObjectSelector().GetSelected()
while ($g.MoveNext()) { $o = $g.Current; $n++; $tn = $o.GetType().Name; $id = $idProp.GetValue($o, $null).ID
  $byType[$tn] = 1 + [int]$byType[$tn]
  if ($okTypes -notcontains $tn) { $nm = ''; try { $nm = " '$($o.Name)'" } catch {}; $bad += "  $id $tn$nm : not a 2D graphic/text"; continue }
  $vw = $null; try { $vw = $o.GetView() } catch {}
  if ($vw -and $vw.GetType().Name -ne 'ContainerView') { $bad += "  $id $tn : inside a drawing view, not on the sheet (offset would be in view units)" }
  foreach ($p in (Pts $o)) { if (-not $p) { continue }
    $xmin = [math]::Min($xmin, $p.X); $ymin = [math]::Min($ymin, $p.Y); $xmax = [math]::Max($xmax, $p.X); $ymax = [math]::Max($ymax, $p.Y)
    if ($bx -and ($p.X -lt $bx[0] - 0.01 -or $p.X -gt $bx[2] + 0.01 -or $p.Y -lt $bx[1] - 0.01 -or $p.Y -gt $bx[3] + 0.01)) {
      $out += "  $id $tn : point ({0:F2},{1:F2}) outside -Box" -f $p.X, $p.Y; break } } }
"selection (API-visible): $n  [" + (($byType.Keys | sort | % { "$_ $($byType[$_])" }) -join ', ') + "]"
if ($n) { "  extent x {0:F2}..{1:F2}  y {2:F2}..{3:F2}" -f $xmin, $xmax, $ymin, $ymax }
else { "  WARNING: API sees nothing selected. Cover-ups alone are fine, but nothing can be checked." }
"  cover-ups: invisible to the API, not counted - check them by eye after the move."
$stop = $false
if ($bad.Count) { "BLOCKED - objects that must not be moved:"; $bad; if ($Force) { "  (-Force: ignored)" } else { $stop = $true } }
if ($out.Count) { "BLOCKED - objects outside -Box (another cell group?):"; $out; $stop = $true }
if ($stop) { "Nothing moved. Unselect these objects in Tekla (Ctrl+click) or re-select with a left-to-right window, then run again."; exit 2 }
"guard OK"
if ($DryRun) { "-DryRun: macro not run (would $(if ($Copy) { 'copy' } else { 'move' }) dX=$DX dY=$DY)"; exit 0 }

$del = if ($Copy) { "" } else { "akit.Callback(""acmd_delete_selected_dr"", """", ""$Window"");" }
$name = "Claude_Translate.cs"
@"
#pragma warning disable 1633
#pragma reference "Tekla.Macros.Akit"
#pragma reference "Tekla.Macros.Wpf.Runtime"
#pragma reference "Tekla.Macros.Runtime"
#pragma warning restore 1633
namespace UserMacros { public sealed class Macro { [Tekla.Macros.Runtime.MacroEntryPointAttribute()]
public static void Run(Tekla.Macros.Runtime.IMacroRuntime runtime) {
Tekla.Macros.Akit.IAkitScriptHost akit = runtime.Get<Tekla.Macros.Akit.IAkitScriptHost>();
Tekla.Macros.Wpf.Runtime.IWpfMacroHost wpf = runtime.Get<Tekla.Macros.Wpf.Runtime.IWpfMacroHost>();
akit.CommandStart("ail_grCopyObjects", "", "$Window");
akit.ValueChange("grCopy", "dx", "$($DX.ToString($inv))");
akit.ValueChange("grCopy", "dy", "$($DY.ToString($inv))");
akit.PushButton("gr_copy_apply", "grCopy");
akit.PushButton("gr_copy_cancel", "grCopy");
wpf.InvokeCommand("CommandRepository", "Common.Interrupt");
$del
}}}
"@ | Set-Content -Path (Join-Path $MacroDir $name) -Encoding utf8
$ok = [Tekla.Structures.Model.Operations.Operation]::RunMacro("..\drawings\$name")
while ([Tekla.Structures.Model.Operations.Operation]::IsMacroRunning()) { Start-Sleep -Milliseconds 200 }
"macro $name ($(if ($Copy) { 'copy' } else { 'move = copy + delete originals' }) dX=$DX dY=$DY) started=$ok"
