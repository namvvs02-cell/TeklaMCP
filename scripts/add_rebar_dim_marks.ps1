# Creates rebar dimension marks for the given rebar groups without a GUI pick:
# loads the dim mark property file into rebar_dim_dial, selects the rebars, then runs acmd_create_marks_selected / RebarNewDimMark.
# Marks made by RebarNewDimMark show their text but keep EMPTY stored prefix/tags (Get returns nothing), so step 2
# selects the new marks and runs dim_modify with the same file; after that Get / copy to other groups works.
# Always reuse one property file (default: the cc max file saved from a correct user mark); for _ADD bars pass
# -PropertyFile "WH_ArialNarr_2mm_Trans_Rebar Dim_no pic_ADDITIONAL BAR TEXT" (same content + tag D "ADDITIONAL BAR").
param([Parameter(Mandatory)][int[]]$RebarIds, [string]$ViewName = "W", [string]$ViewType = "",
      [string]$PropertyFile = "WH_ArialNarr_2mm_Trans_Rebar Dim_no pic_cc max", [string]$Window = "View_10 window_1",
      [string]$TeklaDir = "D:\TeklaClaude\TeklaMcp\Tekla2020", [string]$MacroDir = "C:\TeklaStructures\2020.0\Environments\common\macros\drawings")
if (-not $env:SESSIONNAME) { $env:SESSIONNAME = "Console" }
Add-Type -Path "$TeklaDir\Tekla.Structures.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Model.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Drawing.dll"
$dh = New-Object Tekla.Structures.Drawing.DrawingHandler
$dwg = $dh.GetActiveDrawing()
$tv = $null; $ve0 = $dwg.GetSheet().GetAllViews()
while ($ve0.MoveNext()) { $vv = $ve0.Current; if ($vv -is [Tekla.Structures.Drawing.View] -and $vv.Name -eq $ViewName -and (-not $ViewType -or "$($vv.ViewType)" -eq $ViewType)) { $tv = $vv } }
if (-not $tv) { throw "view not found" }
function Key($s) { $se = $s.GetObjects(); $k = ""; while ($se.MoveNext()) { $d = $se.Current; if ($d -is [Tekla.Structures.Drawing.StraightDimension]) { $k += "{0:F0},{1:F0},{2:F0},{3:F0};" -f $d.StartPoint.X,$d.StartPoint.Y,$d.EndPoint.X,$d.EndPoint.Y } }; $k }
function DimSets { $r = @(); $e = $tv.GetAllObjects(); while ($e.MoveNext()) { if ($e.Current -is [Tekla.Structures.Drawing.StraightDimensionSet]) { $r += $e.Current } }; $r }
function RunMacro($name, $body) {
  @"
#pragma warning disable 1633
#pragma reference "Tekla.Macros.Akit"
#pragma reference "Tekla.Macros.Runtime"
#pragma warning restore 1633
namespace UserMacros { public sealed class Macro { [Tekla.Macros.Runtime.MacroEntryPointAttribute()]
public static void Run(Tekla.Macros.Runtime.IMacroRuntime runtime) {
Tekla.Macros.Akit.IAkitScriptHost akit = runtime.Get<Tekla.Macros.Akit.IAkitScriptHost>();
akit.Callback("acmd_display_attr_dialog", "rebar_dim_dial", "main_frame");
akit.ValueChange("rebar_dim_dial", "gr_dim_get_menu", "$PropertyFile");
akit.PushButton("gr_dim_get", "rebar_dim_dial");
$body
}}}
"@ | Set-Content -Path (Join-Path $MacroDir $name) -Encoding utf8
  [void][Tekla.Structures.Model.Operations.Operation]::RunMacro("..\drawings\$name")
}
$beforeIds = @((DimSets) | % { Key $_ }); "dim sets before: $($beforeIds.Count)"
$al = New-Object System.Collections.ArrayList
$e = $tv.GetAllObjects(); while ($e.MoveNext()) { $o = $e.Current; if ($o -is [Tekla.Structures.Drawing.ReinforcementBase] -and $RebarIds -contains $o.ModelIdentifier.ID) { [void]$al.Add($o) } }
"rebars found in view: $($al.Count) / $($RebarIds.Count)"
$sel = $dh.GetDrawingObjectSelector(); [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($al, $false)
try {
  # 1. create
  RunMacro "Claude_DimMark.cs" @"
akit.PushButton("dim_apply", "rebar_dim_dial");
akit.PushButton("dim_ok", "rebar_dim_dial");
akit.Callback("acmd_create_marks_selected", "RebarNewDimMark", "$Window");
"@
  $deadline = (Get-Date).AddSeconds(15)
  do { Start-Sleep -Milliseconds 800; $new = @((DimSets) | ? { $beforeIds -notcontains (Key $_) }) } until ($new.Count -ge $al.Count -or (Get-Date) -gt $deadline)
  "new dim sets: $($new.Count)"
  # 2. store the properties in the new marks (Modify with the same file)
  if ($new.Count -gt 0) {
    $nl = New-Object System.Collections.ArrayList; $new | % { [void]$nl.Add($_) }
    [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($nl, $false)
    RunMacro "Claude_DimMarkModify.cs" @"
akit.PushButton("dim_modify", "rebar_dim_dial");
akit.PushButton("dim_ok", "rebar_dim_dial");
"@
    Start-Sleep -Seconds 3
    $new = @((DimSets) | ? { $beforeIds -notcontains (Key $_) })
  }
} finally { Get-ChildItem $MacroDir -Filter "Claude_DimMark*.cs*" | Remove-Item -Force -ErrorAction SilentlyContinue }
foreach ($s in $new) {
  $se = $s.GetObjects(); $pts = @()
  while ($se.MoveNext()) { $d = $se.Current; if ($d -is [Tekla.Structures.Drawing.StraightDimension]) { $pts += ("({0:F0},{1:F0})-({2:F0},{3:F0}) up=({4:F2},{5:F2}) dist={6:F0}" -f $d.StartPoint.X,$d.StartPoint.Y,$d.EndPoint.X,$d.EndPoint.Y,$d.UpDirection.X,$d.UpDirection.Y,$d.Distance) } }
  "SET dist=$($s.Distance) " + ($pts -join ' ; ')
}
