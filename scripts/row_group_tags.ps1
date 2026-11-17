# Rotated (90 deg) group marks in a row: Spec "id|centerX|top/bot|x1,x2,...", arrows at (xi, DotY), one bar dot per leader.
# InsertionPoint is the mark centre, so the script aligns the bounding box: top row by its bottom edge (TopY), bottom row by its top edge (BotY).
# Used 2026-11-17 for the group tags of PPVC07a W_40 view W (roof bars cut as dots).
param([string[]]$Spec,[string]$ViewName='W',[string]$ViewType='SectionView',[double]$TopY=3300,[double]$BotY=2200,[double]$DotY=2867)
$env:SESSIONNAME="Console"; $T="D:\TeklaClaude\TeklaMcp\Tekla2020"
Add-Type -Path "$T\Tekla.Structures.dll"; Add-Type -Path "$T\Tekla.Structures.Model.dll"; Add-Type -Path "$T\Tekla.Structures.Drawing.dll"
$dh=New-Object Tekla.Structures.Drawing.DrawingHandler; $dwg=$dh.GetActiveDrawing()
function TV { $ve=$dwg.GetSheet().GetAllViews(); while($ve.MoveNext()){ $w=$ve.Current; if($w -is [Tekla.Structures.Drawing.View] -and $w.Name -eq $ViewName -and "$($w.ViewType)" -eq $ViewType){ return $w } } }
function P($x,$y){ New-Object Tekla.Structures.Geometry3d.Point([double]$x,[double]$y,0) }
function MarkOf($id){ $e=(TV).GetAllObjects(); while($e.MoveNext()){ $o=$e.Current; if($o -is [Tekla.Structures.Drawing.Mark] -and $o.Attributes.Content.Count -gt 0){ $q=$o.GetRelatedObjects(); while($q.MoveNext()){ if($q.Current -is [Tekla.Structures.Drawing.ModelObject] -and $q.Current.ModelIdentifier.ID -eq $id){ return $o } } } } }
function Leaders($o){ $r=@(); $c=$o.GetObjects(); while($c.MoveNext()){ $l=$c.Current; if($l -is [Tekla.Structures.Drawing.LeaderLine] -and "$($l.LeaderLineType)" -eq 'NormalLeaderLine'){ $r+=,$l } }; ,$r }
foreach($sp in $Spec){ $a=$sp -split '\|'; $id=[int]$a[0]; $cx=[double]$a[1]; $xs=@($a[3] -split ',' | % {[double]$_})
  $o=MarkOf $id; if(-not $o){ "NO MARK $id"; continue }
  if($o.Attributes.RotationAngle -ne 90){ $o.Attributes.RotationAngle=90; [void]$o.Modify(); [void]$dwg.CommitChanges(); $o=MarkOf $id }
  for($pass=0;$pass -lt 3;$pass++){
    $bb=$o.GetAxisAlignedBoundingBox(); $L=$bb.UpperRight.Y-$bb.LowerLeft.Y; $dx=$o.InsertionPoint.X-($bb.LowerLeft.X+$bb.UpperRight.X)/2; $dy=$o.InsertionPoint.Y-($bb.LowerLeft.Y+$bb.UpperRight.Y)/2
    $cy= if($a[2] -eq 'top'){ $TopY+$L/2 } else { $BotY-$L/2 }
    $tx=$cx+$dx; $ty=$cy+$dy
    if([math]::Abs($o.InsertionPoint.X-$tx) -lt 1 -and [math]::Abs($o.InsertionPoint.Y-$ty) -lt 1){ break }
    $o.InsertionPoint=P $tx $ty; [void]$o.Modify(); [void]$dwg.CommitChanges(); $o=MarkOf $id }
  $ls=Leaders $o; $used=@()
  foreach($l in $ls){ $free=@($xs | ? { $used -notcontains $_ }); if($free.Count -eq 0){ $free=$xs }
    $nx=$free | Sort-Object { [math]::Abs($_-$l.StartPoint.X) } | Select -First 1; $used+=$nx
    if([math]::Abs($l.StartPoint.X-$nx) -gt 1 -or [math]::Abs($l.StartPoint.Y-$DotY) -gt 1){ $l.StartPoint=P $nx $DotY; [void]$l.Modify() } }
  [void]$dwg.CommitChanges(); $o=MarkOf $id; $bb=$o.GetAxisAlignedBoundingBox()
  $now=@(); foreach($l in (Leaders $o)){ $now+=("({0:F0},{1:F0})" -f $l.StartPoint.X,$l.StartPoint.Y) }
  $ext=$null; $c=$o.GetObjects(); while($c.MoveNext()){ if("$($c.Current.LeaderLineType)" -eq 'ExtensionLeaderLine'){ $ext=$c.Current.StartPoint } }
  "{0} ang{1} ins({2:F0},{3:F0}) bb({4:F0},{5:F0})-({6:F0},{7:F0}) ext({8:F0},{9:F0}) arrows {10}" -f $id,$o.Attributes.RotationAngle,$o.InsertionPoint.X,$o.InsertionPoint.Y,$bb.LowerLeft.X,$bb.LowerLeft.Y,$bb.UpperRight.X,$bb.UpperRight.Y,$ext.X,$ext.Y,($now -join ' ') }
