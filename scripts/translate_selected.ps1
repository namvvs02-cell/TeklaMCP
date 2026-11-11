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
param([double]$DX = 0, [double]$DY = 0, [switch]$Copy, [int[]]$SelectIds = @(), [string]$Window = "View_10 window_1",
      [string]$TeklaDir = "D:\TeklaClaude\TeklaMcp\Tekla2020",
      [string]$MacroDir = "C:\TeklaStructures\2020.0\Environments\common\macros\drawings")
if (-not $env:SESSIONNAME) { $env:SESSIONNAME = "Console" }
Add-Type -Path "$TeklaDir\Tekla.Structures.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Model.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Drawing.dll"
$dh = New-Object Tekla.Structures.Drawing.DrawingHandler; $dwg = $dh.GetActiveDrawing()
if (-not $dwg) { throw "no active drawing" }
$inv = [Globalization.CultureInfo]::InvariantCulture
if ($SelectIds.Count) {
  $idProp = [Tekla.Structures.Drawing.DatabaseObject].GetProperty("Identifier", [Reflection.BindingFlags]"NonPublic,Public,Instance")
  $al = New-Object System.Collections.ArrayList; $e = $dwg.GetSheet().GetAllObjects()
  while ($e.MoveNext()) { if ($SelectIds -contains $idProp.GetValue($e.Current, $null).ID) { [void]$al.Add($e.Current) } }
  $sel = $dh.GetDrawingObjectSelector(); [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($al, $false)
  "selected through API: $($al.Count) / $($SelectIds.Count)"
}
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
