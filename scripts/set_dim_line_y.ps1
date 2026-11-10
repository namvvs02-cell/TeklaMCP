# Iteratively moves horizontal dim sets (matched by x range) until the dim line sits at the target y.
param([string[]]$Spec, [string]$ViewName = "W", [int]$Iter = 4, [string]$TeklaDir = "D:\TeklaClaude\TeklaMcp\Tekla2020")
if (-not $env:SESSIONNAME) { $env:SESSIONNAME = "Console" }
Add-Type -Path "$TeklaDir\Tekla.Structures.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Model.dll"; Add-Type -Path "$TeklaDir\Tekla.Structures.Drawing.dll"
$dh = New-Object Tekla.Structures.Drawing.DrawingHandler
$dwg = $dh.GetActiveDrawing()
$tv = $null; $ve0 = $dwg.GetSheet().GetAllViews()
while ($ve0.MoveNext()) { $vv = $ve0.Current; if ($vv -is [Tekla.Structures.Drawing.View] -and $vv.Name -eq $ViewName) { $tv = $vv } }
function Get($x0w, $x1w) {
  $e = $tv.GetAllObjects()
  while ($e.MoveNext()) { $s = $e.Current; if (-not ($s -is [Tekla.Structures.Drawing.StraightDimensionSet])) { continue }
    $se = $s.GetObjects(); $d = $null; while ($se.MoveNext()) { if ($se.Current -is [Tekla.Structures.Drawing.StraightDimension]) { $d = $se.Current; break } }
    if (-not $d -or [math]::Abs($d.UpDirection.X) -gt 0.01) { continue }
    $x0 = [math]::Min($d.StartPoint.X, $d.EndPoint.X); $x1 = [math]::Max($d.StartPoint.X, $d.EndPoint.X)
    if ([math]::Abs($x0 - $x0w) -lt 2 -and [math]::Abs($x1 - $x1w) -lt 2) { return @($s, $d) } }
  $null }
foreach ($sp in $Spec) { $a = $sp -split ',' | % { [double]$_ }
  for ($i = 0; $i -lt $Iter; $i++) {
    $r = Get $a[0] $a[1]; $s = $r[0]; $d = $r[1]
    $ly = $d.StartPoint.Y + $d.UpDirection.Y * $d.Distance
    if ([math]::Abs($ly - $a[2]) -lt 3) { break }
    $s.Distance = $s.Distance + ($a[2] - $ly) / $d.UpDirection.Y; [void]$s.Modify(); [void]$dwg.CommitChanges()
  }
  $r = Get $a[0] $a[1]; $d = $r[1]
  "{0:F0}..{1:F0}: line y = {2:F0} (target {3:F0}, {4} tries)" -f $a[0],$a[1],($d.StartPoint.Y + $d.UpDirection.Y * $d.Distance),$a[2],$i
}
