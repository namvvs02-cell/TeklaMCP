# Places rebar marks with the agreed mark properties loaded from the start, in one run.
#   1. Make sure every rebar has a mark in the view (creates an empty one with the API if missing).
#   2. Selects the marks and runs a temporary macro: open "rebar_mark_dial", load the property file, Modify.
#      This is how the leader type (e.g. "Leader lines to one point") gets set - the 2020 API cannot set it.
#   3. Optional: replaces <<cc target>> with fixed text (-SpacingText), moves the tag to the tag column
#      (-TagX, centred on the bars), and moves each arrow to the bar end on -Side.
# Dry run by default; add -Apply to write. Tekla 2020, drawing open.
# Example: .\place_rebar_marks.ps1 -ViewName N -ViewType DetailView -RebarIds 358097497 -Kind group -TagX -966.6 -SpacingText 200 -Apply
param(
    [Parameter(Mandatory)][int[]]$RebarIds,
    [Parameter(Mandatory)][string]$ViewName,
    [Parameter(Mandatory)][string]$ViewType,
    [ValidateSet('group', 'single')][string]$Kind = 'group',
    [string]$PropertyFile = '',
    [double]$TagX = [double]::NaN,
    [ValidateSet('left', 'right', 'bottom', 'top')][string]$Side = 'left',
    [string]$SpacingText = '',
    [string[]]$TagXY = @(),     # per rebar "x,y" (view coords): tag insertion point; overrides -TagX
    [string[]]$ArrowXY = @(),   # per rebar "x,y": arrow point for a single-leader mark; overrides -Side
    [string]$ExtraText = '',    # second line under the mark text (e.g. "CAPPING BAR", "WALL VER. BAR")
    [switch]$Apply,
    [string]$TeklaDir = "D:\TeklaClaude\TeklaMcp\Tekla2020",
    [string]$MacroDir = "C:\TeklaStructures\2020.0\Environments\common\macros\drawings"
)
$ErrorActionPreference = 'Stop'
if (-not $env:SESSIONNAME) { $env:SESSIONNAME = "Console" }
Add-Type -Path "$TeklaDir\Tekla.Structures.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Model.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Drawing.dll"
if (-not $PropertyFile) {
    $PropertyFile = if ($Kind -eq 'group') { 'WH_ArialNarr_2mm_Trans_Rebar Group to one point with Spacing' } else { 'WH_ArialNarr_2mm_Trans_Rebar' }
}
$TSD = 'Tekla.Structures.Drawing'
$dh = New-Object "$TSD.DrawingHandler"
$dwg = $dh.GetActiveDrawing(); if (-not $dwg) { throw "no active drawing" }
$tv = $null; $ve = $dwg.GetSheet().GetAllViews()
while ($ve.MoveNext()) { $v = $ve.Current; if ($v -is [Tekla.Structures.Drawing.View] -and $v.Name -eq $ViewName -and "$($v.ViewType)" -eq $ViewType) { $tv = $v } }
if (-not $tv) { throw "view $ViewName/$ViewType not found" }

# --- bar end points (view display coordinates) on the requested side
$model = New-Object Tekla.Structures.Model.Model
$wph = $model.GetWorkPlaneHandler(); $savedPlane = $wph.GetCurrentTransformationPlane()
$ends = @{}
try {
    [void]$wph.SetCurrentTransformationPlane((New-Object Tekla.Structures.Model.TransformationPlane($tv.DisplayCoordinateSystem)))
    foreach ($id in $RebarIds) {
        $mo = $model.SelectModelObject((New-Object Tekla.Structures.Identifier($id)))
        if (-not $mo) { throw "rebar $id not in model" }
        $list = @()
        foreach ($g in $mo.GetRebarGeometries($false)) {
            $p0 = $g.Shape.Points[0]; $p1 = $g.Shape.Points[$g.Shape.Points.Count - 1]
            $pick = switch ($Side) { 'left' { if ($p0.X -le $p1.X) { $p0 } else { $p1 } } 'right' { if ($p0.X -ge $p1.X) { $p0 } else { $p1 } }
                                     'bottom' { if ($p0.Y -le $p1.Y) { $p0 } else { $p1 } } 'top' { if ($p0.Y -ge $p1.Y) { $p0 } else { $p1 } } }
            $list += New-Object Tekla.Structures.Geometry3d.Point($pick.X, $pick.Y, 0)
        }
        $ends[$id] = $list
    }
} finally { [void]$wph.SetCurrentTransformationPlane($savedPlane) }

# --- marks per rebar in the view
function Get-Marks {
    $res = @{}; $e = $tv.GetAllObjects()
    while ($e.MoveNext()) { $o = $e.Current; if (-not ($o -is [Tekla.Structures.Drawing.Mark])) { continue }
        $r = $o.GetRelatedObjects(); while ($r.MoveNext()) { if ($r.Current -is [Tekla.Structures.Drawing.ModelObject] -and $RebarIds -contains $r.Current.ModelIdentifier.ID) { $res[$r.Current.ModelIdentifier.ID] = $o } } }
    return $res
}
$marks = Get-Marks
foreach ($id in $RebarIds) {
    $n = $ends[$id].Count
    $info = "rebar $id : $n bar(s), mark " + $(if ($marks.ContainsKey($id)) { "exists" } else { "missing -> will create" })
    if (-not [double]::IsNaN($TagX)) { $info += ", tag at ({0:F1},{1:F1})" -f $TagX, (($ends[$id] | Measure-Object -Property Y -Average).Average) }
    $info
}
"property file: $PropertyFile"
if (-not $Apply) { "dry run - add -Apply to write"; return }

# 1. create missing marks
$e = $tv.GetAllObjects(); $rbs = @{}
while ($e.MoveNext()) { $o = $e.Current; if ($o -is [Tekla.Structures.Drawing.ReinforcementBase] -and $RebarIds -contains $o.ModelIdentifier.ID) { $rbs[$o.ModelIdentifier.ID] = $o } }
foreach ($id in $RebarIds) { if (-not $marks.ContainsKey($id)) { $mk = New-Object "$TSD.Mark" -ArgumentList $rbs[$id]; [void]$mk.Insert() } }
[void]$dwg.CommitChanges(); $marks = Get-Marks

# 2. load property file + Modify on the selected marks (temporary macro)
$sel = $dh.GetDrawingObjectSelector(); [void]$sel.UnselectAllObjects()
$al = New-Object System.Collections.ArrayList; foreach ($id in $RebarIds) { [void]$al.Add($marks[$id]) }; [void]$sel.SelectObjects($al, $false)
$macroName = "Claude_ApplyRebarMark.cs"
@"
#pragma warning disable 1633
#pragma reference "Tekla.Macros.Akit"
#pragma reference "Tekla.Macros.Runtime"
#pragma warning restore 1633
namespace UserMacros { public sealed class Macro { [Tekla.Macros.Runtime.MacroEntryPointAttribute()]
public static void Run(Tekla.Macros.Runtime.IMacroRuntime runtime) {
Tekla.Macros.Akit.IAkitScriptHost akit = runtime.Get<Tekla.Macros.Akit.IAkitScriptHost>();
akit.Callback("acmd_display_attr_dialog", "rebar_mark_dial", "main_frame");
akit.ValueChange("rebar_mark_dial", "gr_rebar_mark_get_menu", "$PropertyFile");
akit.PushButton("gr_rebar_get", "rebar_mark_dial");
akit.PushButton("rebar_modify", "rebar_mark_dial");
akit.PushButton("rebar_mark_modify", "rebar_mark_dial");
akit.PushButton("dia_modify", "rebar_mark_dial");
akit.PushButton("mark_modify", "rebar_mark_dial");
}}}
"@ | Set-Content -Path (Join-Path $MacroDir $macroName) -Encoding utf8
try {
    [void][Tekla.Structures.Model.Operations.Operation]::RunMacro("..\drawings\$macroName")
    $deadline = (Get-Date).AddSeconds(15)
    do { Start-Sleep -Milliseconds 700; $marks = Get-Marks; $ready = $true; foreach ($id in $RebarIds) { [void]$marks[$id].Select(); if ($marks[$id].Attributes.Content.Count -eq 0) { $ready = $false } } } until ($ready -or (Get-Date) -gt $deadline)
    if (-not $ready) { throw "marks still empty after macro - check that the property file exists in the model attributes folder" }
} finally {
    Get-ChildItem $MacroDir -Filter "Claude_ApplyRebarMark.cs*" | Remove-Item -Force
    # close the dialog the macro left open (WM_CLOSE = Cancel; the Modify is already done)
    # (FindWindow by title does not find it; enumerate top-level windows instead)
    if (-not ('ClaudeWin' -as [type])) { Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public class ClaudeWin { public delegate bool P(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(P p, IntPtr l);
[DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
public static IntPtr Find(string title) { IntPtr r = IntPtr.Zero; EnumWindows((h, l) => { if (IsWindowVisible(h)) { var s = new StringBuilder(256); GetWindowText(h, s, 256); if (s.ToString().Trim() == title) { r = h; return false; } } return true; }, IntPtr.Zero); return r; } }
'@ }
    $hw = [ClaudeWin]::Find("Reinforcement Mark Properties"); if ($hw -ne [IntPtr]::Zero) { [void][ClaudeWin]::PostMessage($hw, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
}

# 3. spacing text + tag position (mark level first; leader edits must come last, a mark Modify resets them)
foreach ($id in $RebarIds) {
    $mk = $marks[$id]; [void]$mk.Select(); $changed = $false
    if ($true) {
        # Content is not indexable. Walk it with GetEnumerator(): foreach/pipelines in PowerShell unroll the
        # nested ContainerElement (the oval frame around REBAR_SEQ_NO) and the frame is lost.
        $c = $mk.Attributes.Content
        $items = New-Object System.Collections.ArrayList; $en = $c.GetEnumerator()
        while ($en.MoveNext()) { $x = $en.Current
            if ($SpacingText -and $x.GetType().Name -eq 'LengthPropertyElement' -and $x.Name -eq 'CC_TARGET') {
                $t = New-Object "$TSD.TextElement" -ArgumentList $SpacingText; $t.Font = $x.Font; [void]$items.Add($t); $changed = $true
            } else { [void]$items.Add($x) } }
        # the property file leaves a space on both sides of "-"; the agreed look is "2H16-200" (no spaces)
        for ($i = $items.Count - 1; $i -ge 0; $i--) {
            if ($items[$i].GetType().Name -ne 'SpaceElement') { continue }
            $prev = if ($i -gt 0) { $items[$i - 1] } else { $null }; $next = if ($i + 1 -lt $items.Count) { $items[$i + 1] } else { $null }
            if (($prev -is [Tekla.Structures.Drawing.TextElement] -and $prev.Value -eq '-') -or ($next -is [Tekla.Structures.Drawing.TextElement] -and $next.Value -eq '-')) { $items.RemoveAt($i); $changed = $true }
        }
        if ($ExtraText) {
            $font = $null; foreach ($x in $items) { if ($x.PSObject.Properties['Font'] -and $x.Font) { $font = $x.Font; break } }
            $t = New-Object "$TSD.TextElement" -ArgumentList $ExtraText; if ($font) { $t.Font = $font }
            [void]$items.Add((New-Object "$TSD.NewLineElement")); [void]$items.Add($t); $changed = $true
        }
        if ($changed) { $c.Clear(); for ($i = 0; $i -lt $items.Count; $i++) { $c.Add($items[$i]) } }
    }
    $k = [array]::IndexOf($RebarIds, $id)
    if ($TagXY.Count -gt $k -and $TagXY[$k]) {
        $xy = $TagXY[$k] -split ','; $mk.InsertionPoint = New-Object Tekla.Structures.Geometry3d.Point([double]$xy[0], [double]$xy[1], 0); $changed = $true
    } elseif (-not [double]::IsNaN($TagX)) {
        $axis = if ($Side -in 'left', 'right') { 'Y' } else { 'X' }
        $mid = ($ends[$id] | Measure-Object -Property $axis -Average).Average
        $mk.InsertionPoint = if ($axis -eq 'Y') { New-Object Tekla.Structures.Geometry3d.Point($TagX, $mid, 0) } else { New-Object Tekla.Structures.Geometry3d.Point($mid, $TagX, 0) }
        $changed = $true
    }
    if ($ArrowXY.Count -gt $k -and $ArrowXY[$k]) {
        $xy = $ArrowXY[$k] -split ','
        $mk.Placing = New-Object "$TSD.LeaderLinePlacing" -ArgumentList (New-Object Tekla.Structures.Geometry3d.Point([double]$xy[0], [double]$xy[1], 0)); $changed = $true
    }
    if ($changed) { [void]$mk.Modify() }
}
[void]$dwg.CommitChanges()

# 4. arrows to the bar ends on -Side (nearest bar per leader)
$marks = Get-Marks
foreach ($id in $RebarIds) {
    $k = [array]::IndexOf($RebarIds, $id); if ($ArrowXY.Count -gt $k -and $ArrowXY[$k]) { continue }   # arrow already set explicitly
    $ch = $marks[$id].GetObjects()
    while ($ch.MoveNext()) { $ll = $ch.Current
        if (-not ($ll -is [Tekla.Structures.Drawing.LeaderLine]) -or "$($ll.LeaderLineType)" -ne 'NormalLeaderLine') { continue }
        $sp = $ll.StartPoint
        $near = $ends[$id] | Sort-Object { if ($Side -in 'left', 'right') { [math]::Abs($_.Y - $sp.Y) } else { [math]::Abs($_.X - $sp.X) } } | Select-Object -First 1
        $ll.StartPoint = $near; [void]$ll.Modify()
    }
}
[void]$dwg.CommitChanges()

# report
$marks = Get-Marks
foreach ($id in $RebarIds) {
    $mk = $marks[$id]; [void]$mk.Select()
    $txt = ($mk.Attributes.Content | ForEach-Object { if ($_.GetType().Name -eq 'TextElement') { "'$($_.Value)'" } elseif ($_.Name) { $_.Name } else { $_.GetType().Name } }) -join ' '
    $arrows = @(); $ch = $mk.GetObjects(); while ($ch.MoveNext()) { if ($ch.Current -is [Tekla.Structures.Drawing.LeaderLine] -and "$($ch.Current.LeaderLineType)" -eq 'NormalLeaderLine') { $arrows += ("({0:F0},{1:F0})" -f $ch.Current.StartPoint.X, $ch.Current.StartPoint.Y) } }
    "rebar $id : tag {0} | {1} | arrows {2}" -f $mk.InsertionPoint, $txt, ($arrows -join ' ')
}
