# Places existing rebar marks (tags) and their arrows, and fixes their content, in one run.
#   1. Missing marks are created as real reinforcement marks with the property file by add_rebar_marks_applied.ps1
#      (same folder: dialog Apply + acmdCreateAppliedMarksSelected). Never "new Mark(rebar)": Tekla treats that as an
#      associated note, and the 2020 API cannot set the leader type ("Leader lines to one point").
#      Marks that already exist keep their properties (the old dialog Modify step was removed 2026-11-17: it pushed
#      buttons of other dialogs and did nothing).
#   2. Optional: replaces <<cc target>> with fixed text (-SpacingText), removes spaces around "-", moves the tag to the
#      tag column (-TagX, centred on the bars), and moves each arrow to the bar end on -Side.
# Dry run by default; add -Apply to write. Tekla 2020, drawing open and not frozen.
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
    [double]$Angle = [double]::NaN,   # mark rotation in degrees (90 = vertical tag, e.g. bars seen as dots in a section)
    [double]$ArrowY = [double]::NaN,  # bars seen as dots: arrows go to (bar x, ArrowY) instead of the bar end on -Side
    [switch]$Apply,
    [string]$TeklaDir = "C:\TeklaClaude\TeklaMcp\Tekla2020",
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
    # reset to the global plane first: when the user has rotated the model work plane, setting the view plane directly
    # gives wrong bar coordinates (seen 2026-11-17, PPVC07a: x ~17000 instead of view coordinates)
    [void]$wph.SetCurrentTransformationPlane((New-Object Tekla.Structures.Model.TransformationPlane))
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
        # hidden marks sit at (0,0) with no content (e.g. left over from a rebar dim mark): not a tag, ignore
        # (a mark just created by the API also sits at (0,0), but it has Tekla's default content: keep it)
        if ([math]::Abs($o.InsertionPoint.X) -lt 0.5 -and [math]::Abs($o.InsertionPoint.Y) -lt 0.5 -and $o.Attributes.Content.Count -eq 0) { continue }
        $r = $o.GetRelatedObjects(); while ($r.MoveNext()) { if ($r.Current -is [Tekla.Structures.Drawing.ModelObject] -and $RebarIds -contains $r.Current.ModelIdentifier.ID) { $res[$r.Current.ModelIdentifier.ID] = $o } } }
    return $res
}
$marks = Get-Marks
foreach ($id in $RebarIds) {
    $n = $ends[$id].Count
    $info = "rebar $id : $n bar(s), mark " + $(if ($marks.ContainsKey($id)) { "exists" } else { "missing -> will create with add_rebar_marks_applied.ps1" })
    if (-not [double]::IsNaN($TagX)) { $info += ", tag at ({0:F1},{1:F1})" -f $TagX, (($ends[$id] | Measure-Object -Property Y -Average).Average) }
    $info
}
"property file: $PropertyFile"
if (-not $Apply) { "dry run - add -Apply to write"; return }

# 1. create missing marks as real reinforcement marks (property file + leader type from the dialog)
$missing = @($RebarIds | Where-Object { -not $marks.ContainsKey($_) })
if ($missing.Count) {
    & (Join-Path $PSScriptRoot 'add_rebar_marks_applied.ps1') -RebarIds $missing -ViewName $ViewName -ViewType $ViewType -PropertyFile $PropertyFile
    $marks = Get-Marks
    foreach ($id in $missing) { if (-not $marks.ContainsKey($id)) { throw "no mark was created for rebar $id - stop, do not retry (see PPVC_Drawing_workflow.md)" } }
}

# 2. spacing text + tag position (mark level first; leader edits must come last, a mark Modify resets them)
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
        # older property files leave a space on both sides of "-"; the agreed look is "2H16-200" (no spaces)
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
    if (-not [double]::IsNaN($Angle)) { $mk.Attributes.RotationAngle = $Angle; $changed = $true }
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

# 3. arrows to the bar ends on -Side (nearest bar per leader)
$marks = Get-Marks
foreach ($id in $RebarIds) {
    $k = [array]::IndexOf($RebarIds, $id); if ($ArrowXY.Count -gt $k -and $ArrowXY[$k]) { continue }   # arrow already set explicitly
    $ch = $marks[$id].GetObjects(); $used = @()
    while ($ch.MoveNext()) { $ll = $ch.Current
        if (-not ($ll -is [Tekla.Structures.Drawing.LeaderLine]) -or "$($ll.LeaderLineType)" -ne 'NormalLeaderLine') { continue }
        $sp = $ll.StartPoint
        # one leader per bar: nearest bar not yet taken (leaders of a new mark often start at the same point)
        $free = @($ends[$id] | Where-Object { $used -notcontains $_ }); if ($free.Count -eq 0) { $free = $ends[$id] }
        $near = $free | Sort-Object { if ($Side -in 'left', 'right') { [math]::Abs($_.Y - $sp.Y) } else { [math]::Abs($_.X - $sp.X) } } | Select-Object -First 1
        $used += $near
        if (-not [double]::IsNaN($ArrowY)) { $near = New-Object Tekla.Structures.Geometry3d.Point($near.X, $ArrowY, 0) }
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
