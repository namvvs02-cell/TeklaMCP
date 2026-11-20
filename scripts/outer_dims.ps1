# Read-only: per rebar id: bar diameter (RebarGeometry.Diameter), centre-line legs, bend angles, Tekla DIM_* values,
# and out-to-out leg lengths. Rule (checked against Tekla DIM of marks 73, 85, 84, 9 on PPVC07a W_40):
#   out = CL + sum over the leg's end bends whose OUTER side is on the measured face of (d/2)*tan(theta/2); take the face with the max.
param([int[]]$Ids)
$env:SESSIONNAME = "Console"; $T = "C:\TeklaClaude\TeklaMcp\Tekla2020"
Add-Type -Path "$T\Tekla.Structures.dll"; Add-Type -Path "$T\Tekla.Structures.Model.dll"
if (-not ('OD' -as [type])) { Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Text;
public static class OD {
  static double[] S(double[] a, double[] b) { return new[] { b[0]-a[0], b[1]-a[1], b[2]-a[2] }; }
  static double Dt(double[] a, double[] b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
  static double L(double[] a) { return Math.Sqrt(Dt(a,a)); }
  static double[] N(double[] a) { double l = L(a); return new[] { a[0]/l, a[1]/l, a[2]/l }; }
  public static string Run(double[] xs, double[] ys, double[] zs, double d) {
    int n = xs.Length; var p = new List<double[]>(); for (int i = 0; i < n; i++) p.Add(new[] { xs[i], ys[i], zs[i] });
    var lg = new List<double[]>(); for (int i = 0; i < n-1; i++) lg.Add(S(p[i], p[i+1]));
    var sb = new StringBuilder(); double h = d / 2;
    for (int i = 0; i < lg.Count; i++) {
      var u = N(lg[i]); var cands = new List<Tuple<double[], double>>(); var info = new List<string>();
      for (int k = -1; k <= 1; k += 2) { int j = i + k; if (j < 0 || j >= lg.Count) continue;
        var a = N(k < 0 ? lg[j] : lg[i]); var b = N(k < 0 ? lg[i] : lg[j]);
        double th = Math.Acos(Math.Max(-1, Math.Min(1, Dt(a, b)))); double c = h * Math.Tan(th / 2);
        var t = S(a, b); // turn direction; outer side = -(component of t perpendicular to this leg)
        double tu = Dt(t, u); var o = new[] { -(t[0]-tu*u[0]), -(t[1]-tu*u[1]), -(t[2]-tu*u[2]) };
        if (L(o) > 1e-9) { o = N(o); cands.Add(Tuple.Create(o, c)); }
        info.Add(string.Format("{0} {1:F1}deg +{2:F2}", k < 0 ? "prev" : "next", th*180/Math.PI, c)); }
      double best = 0; foreach (var f in cands) { double s = 0; foreach (var q in cands) if (Dt(f.Item1, q.Item1) > 0.7) s += q.Item2; best = Math.Max(best, s); }
      double cl = L(lg[i]);
      sb.AppendLine(string.Format("  leg {0}: CL {1,8:F2}  out {2,8:F2} -> {3,5}   [{4}]", i+1, cl, cl+best, Math.Round(cl+best, MidpointRounding.AwayFromZero), string.Join("  ", info)));
    }
    return sb.ToString(); } }
'@ }
$m = New-Object Tekla.Structures.Model.Model; $wph = $m.GetWorkPlaneHandler(); $sp = $wph.GetCurrentTransformationPlane()
[void]$wph.SetCurrentTransformationPlane((New-Object Tekla.Structures.Model.TransformationPlane))
try { foreach ($id in $Ids) {
  $r = $m.SelectModelObject((New-Object Tekla.Structures.Identifier $id))
  $seq = 0; [void]$r.GetReportProperty('USERDEFINED.REBAR_SEQ_NO', [ref]$seq); $sh = ''; [void]$r.GetReportProperty('SHAPE', [ref]$sh)
  $dm = @(); foreach ($k in 'A','B','C','D','E','F','G','H','R') { $v = 0.0; if ($r.GetReportProperty("DIM_$k", [ref]$v) -and $v -ne 0) { $dm += "$k=$([math]::Round($v,1))" } }
  $g = $r.GetRebarGeometries($false)[0]; $pts = @($g.Shape.Points)
  "=== id $id seq $seq shape $sh size $($r.Size) d $($g.Diameter) | DIM: $($dm -join ' ')"
  [OD]::Run([double[]]($pts | % { $_.X }), [double[]]($pts | % { $_.Y }), [double[]]($pts | % { $_.Z }), [double]$g.Diameter)
} } finally { [void]$wph.SetCurrentTransformationPlane($sp) }
