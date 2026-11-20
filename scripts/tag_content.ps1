# Fixes the content of existing rebar marks (tags) in the active drawing, then puts each mark back where it was.
#  -RemoveDashSpaces : drop the SpaceElements on both sides of the "-" text (correct tag: "2H16-200", not "2H16 - 200").
#                      In the mark dialog "<--" = <BackSpace/> in the .rm file = no SpaceElement in the API.
#  -CcText 200       : replace the property after "-" (cc target / cc) with fixed text, e.g. when staggered bars give 206.
# Marks are found by rebar id (all views, or only -ViewName/-ViewType). Dry run unless -Apply.
# After Content + Modify() Tekla moves the mark sideways, so the script restores it: it keeps the bounding-box edge that
# faces the arrows (and the centre on the other axis), then puts every NormalLeaderLine start point back.
# The same steps worked 2026-11-17 on rotated group marks ("Leader lines to one point") in PPVC07a W_40 view W, run as two
# separate scripts. This merged script was only dry-run tested there; the restore for single-leader marks (Placing) is untested.
param([Parameter(Mandatory)][int[]]$RebarIds,[string]$ViewName='',[string]$ViewType='',
      [switch]$RemoveDashSpaces,[string]$CcText='',[switch]$Apply)
$env:SESSIONNAME="Console"; $T="C:\TeklaClaude\TeklaMcp\Tekla2020"
Add-Type -Path "$T\Tekla.Structures.dll"; Add-Type -Path "$T\Tekla.Structures.Model.dll"; Add-Type -Path "$T\Tekla.Structures.Drawing.dll"
if(-not $RemoveDashSpaces -and -not $CcText){ throw "Give -RemoveDashSpaces and/or -CcText" }
$dh=New-Object Tekla.Structures.Drawing.DrawingHandler; $dwg=$dh.GetActiveDrawing()
function P($x,$y){ New-Object Tekla.Structures.Geometry3d.Point([double]$x,[double]$y,0) }
function Code($x){ if($x -is [Tekla.Structures.Drawing.TextElement]){"'"+$x.Value+"'"} elseif($x -is [Tekla.Structures.Drawing.PropertyElement]){"<"+$x.Name+">"} elseif($x -is [Tekla.Structures.Drawing.NewLineElement]){"/"} elseif($x -is [Tekla.Structures.Drawing.SpaceElement]){"_"} else {"["+$x.GetType().Name+"]"} }
function Items($m){ $it=@(); $ce=$m.Attributes.Content.GetEnumerator(); while($ce.MoveNext()){ $it+=,$ce.Current }; ,$it }
function Leaders($m){ $r=@(); $c=$m.GetObjects(); while($c.MoveNext()){ $l=$c.Current; if($l -is [Tekla.Structures.Drawing.LeaderLine] -and "$($l.LeaderLineType)" -eq 'NormalLeaderLine'){ $r+=,$l } }; ,$r }
function IsDash($x){ $x -is [Tekla.Structures.Drawing.TextElement] -and $x.Value -eq '-' }
function FindMarks{ $r=@(); $ve=$dwg.GetSheet().GetAllViews(); while($ve.MoveNext()){ $w=$ve.Current
    if(-not ($w -is [Tekla.Structures.Drawing.View])){continue}; if($ViewName -and $w.Name -ne $ViewName){continue}; if($ViewType -and "$($w.ViewType)" -ne $ViewType){continue}
    $e=$w.GetAllObjects(); while($e.MoveNext()){ $m=$e.Current; if(-not ($m -is [Tekla.Structures.Drawing.Mark]) -or $m.Attributes.Content.Count -eq 0){continue}
      $q=$m.GetRelatedObjects(); while($q.MoveNext()){ if($q.Current -is [Tekla.Structures.Drawing.ModelObject] -and $RebarIds -contains $q.Current.ModelIdentifier.ID){ $r+=,@($w,$m,$q.Current.ModelIdentifier.ID) } } } }; ,$r }
function Refind($w,$id,$ins){ $best=$null; $bd=1e9; $e=$w.GetAllObjects(); while($e.MoveNext()){ $m=$e.Current; if(-not ($m -is [Tekla.Structures.Drawing.Mark]) -or $m.Attributes.Content.Count -eq 0){continue}
    $q=$m.GetRelatedObjects(); while($q.MoveNext()){ if($q.Current -is [Tekla.Structures.Drawing.ModelObject] -and $q.Current.ModelIdentifier.ID -eq $id){ $d=[math]::Abs($m.InsertionPoint.X-$ins.X)+[math]::Abs($m.InsertionPoint.Y-$ins.Y); if($d -lt $bd){$bd=$d;$best=$m} } } }; $best }
foreach($f in (FindMarks)){ $w=$f[0]; $m=$f[1]; $id=$f[2]
  $it=Items $m; $new=@()
  for($k=0;$k -lt $it.Count;$k++){ $x=$it[$k]
    if($RemoveDashSpaces -and $x -is [Tekla.Structures.Drawing.SpaceElement] -and (($k+1 -lt $it.Count -and (IsDash $it[$k+1])) -or ($k -gt 0 -and (IsDash $it[$k-1])))){ continue }
    $new+=,$x }
  if($CcText){ for($k=0;$k -lt $new.Count;$k++){ if(IsDash $new[$k]){ $j=$k+1; while($j -lt $new.Count -and $new[$j] -is [Tekla.Structures.Drawing.SpaceElement]){$j++}
        if($j -lt $new.Count -and $new[$j] -is [Tekla.Structures.Drawing.PropertyElement]){ $new[$j]=New-Object Tekla.Structures.Drawing.TextElement($CcText,$new[$j].Font) } } } }
  $was=($it|%{Code $_}) -join ' '; $now=($new|%{Code $_}) -join ' '
  if($was -eq $now){ "{0} view {1}: no change :: {2}" -f $id,$w.Name,$was; continue }
  if(-not $Apply){ "{0} view {1}: WOULD CHANGE {2}  ->  {3}" -f $id,$w.Name,$was,$now; continue }
  $ins0=$m.InsertionPoint; $bb0=$m.GetAxisAlignedBoundingBox(); $arr=@(); foreach($l in (Leaders $m)){ $arr+=,@($l.StartPoint.X,$l.StartPoint.Y) }
  $pl=$null; if($m.Placing -is [Tekla.Structures.Drawing.LeaderLinePlacing]){ $pl=$m.Placing.StartPoint }
  $ax=$bb0.LowerLeft.X; $ay=$bb0.LowerLeft.Y; $bx=$bb0.UpperRight.X; $by=$bb0.UpperRight.Y
  $mx=($ax+$bx)/2; $my=($ay+$by)/2; if($arr.Count){ $mx=($arr|%{$_[0]}|Measure -Average).Average; $my=($arr|%{$_[1]}|Measure -Average).Average } elseif($pl){ $mx=$pl.X; $my=$pl.Y }
  $anchor= if($my -gt $by){'top'} elseif($my -lt $ay){'bottom'} elseif($mx -lt $ax){'left'} elseif($mx -gt $bx){'right'} else {'centre'}
  $m.Attributes.Content.Clear(); foreach($x in $new){ $m.Attributes.Content.Add($x) }; [void]$m.Modify(); [void]$dwg.CommitChanges(); $m=Refind $w $id $ins0
  for($pass=0;$pass -lt 4;$pass++){ $bb=$m.GetAxisAlignedBoundingBox()
    $cx0=($ax+$bx)/2; $cy0=($ay+$by)/2; $cx=($bb.LowerLeft.X+$bb.UpperRight.X)/2; $cy=($bb.LowerLeft.Y+$bb.UpperRight.Y)/2
    switch($anchor){ 'top'{$dx=$cx0-$cx;$dy=$by-$bb.UpperRight.Y} 'bottom'{$dx=$cx0-$cx;$dy=$ay-$bb.LowerLeft.Y} 'left'{$dx=$ax-$bb.LowerLeft.X;$dy=$cy0-$cy} 'right'{$dx=$bx-$bb.UpperRight.X;$dy=$cy0-$cy} default{$dx=$cx0-$cx;$dy=$cy0-$cy} }
    if([math]::Abs($dx) -lt 0.5 -and [math]::Abs($dy) -lt 0.5){ break }
    $p0=$m.InsertionPoint; $m.InsertionPoint=P ($p0.X+$dx) ($p0.Y+$dy); [void]$m.Modify(); [void]$dwg.CommitChanges(); $m=Refind $w $id (P ($p0.X+$dx) ($p0.Y+$dy)) }
  if($pl -and $arr.Count -le 1){ $m.Placing=New-Object Tekla.Structures.Drawing.LeaderLinePlacing($pl); [void]$m.Modify(); [void]$dwg.CommitChanges(); $m=Refind $w $id $m.InsertionPoint }
  $ls=Leaders $m; for($k=0;$k -lt $ls.Count -and $k -lt $arr.Count;$k++){ $ls[$k].StartPoint=P $arr[$k][0] $arr[$k][1]; [void]$ls[$k].Modify() }
  [void]$dwg.CommitChanges(); $m=Refind $w $id $m.InsertionPoint; $bb=$m.GetAxisAlignedBoundingBox()
  $now2=@(); foreach($l in (Leaders $m)){ $now2+=("({0:F0},{1:F0})" -f $l.StartPoint.X,$l.StartPoint.Y) }
  "{0} view {1}: {2}  ->  {3} | keep {4} | bb x {5:F0}..{6:F0} y {7:F0}..{8:F0} (was x {9:F0}..{10:F0} y {11:F0}..{12:F0}) arrows {13}" -f $id,$w.Name,$was,((Items $m|%{Code $_}) -join ' '),$anchor,$bb.LowerLeft.X,$bb.UpperRight.X,$bb.LowerLeft.Y,$bb.UpperRight.Y,$ax,$bx,$ay,$by,($now2 -join ' ') }
