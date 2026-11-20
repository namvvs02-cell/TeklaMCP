# Creates real reinforcement marks for rebars selected by API, with a mark property file (e.g. "Leader lines to one point").
# Found 2026-11-17: open rebar_mark_dial, load the file (gr_rebar_mark_get_menu + gr_rebar_get), rebar_apply, rebar_ok,
# then akit.Callback("acmdCreateAppliedMarksSelected", "", "View_NN window_1") = Tekla "add marks with applied settings".
# acmd_create_marks_selected with "" creates nothing for rebars. The dialog's Modify button is "rebar_mark_modify".
# Each step of the macro is logged to -LogFile. Move the marks afterwards with the API (rotation, insertion point, leaders).
param([Parameter(Mandatory)][int[]]$RebarIds,[string]$ViewName='W',[string]$ViewType='SectionView',
      [string]$PropertyFile='WH_ArialNarr_2mm_Trans_Rebar Group to one point with Spacing',[string]$CmdParam='',[string]$Cmd='acmdCreateAppliedMarksSelected',[string]$LogFile=(Join-Path $env:TEMP 'claude_rebar_mark_macro_log.txt'),
      [string]$MacroDir="C:\TeklaStructures\2020.0\Environments\common\macros\drawings")
$env:SESSIONNAME="Console"; $T="C:\TeklaClaude\TeklaMcp\Tekla2020"
Add-Type -Path "$T\Tekla.Structures.dll"; Add-Type -Path "$T\Tekla.Structures.Model.dll"; Add-Type -Path "$T\Tekla.Structures.Drawing.dll"
if (-not ('TkWin2' -as [type])) { Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class TkWin2 { public delegate bool CB(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(CB cb, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, CB cb, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 public static string Find(uint pid) { string found = null;
  EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p != pid) return true;
   EnumChildWindows(h, (c, x) => { var t = new StringBuilder(256); GetWindowText(c, t, 256); var s = t.ToString();
    if (found == null && IsWindowVisible(c) && s.StartsWith("View_") && s.EndsWith("window_1")) found = s; return true; }, IntPtr.Zero); return true; }, IntPtr.Zero); return found; } }
"@ }
$dh=New-Object Tekla.Structures.Drawing.DrawingHandler; $dwg=$dh.GetActiveDrawing()
function TV { $ve=$dwg.GetSheet().GetAllViews(); while($ve.MoveNext()){ $w=$ve.Current; if($w -is [Tekla.Structures.Drawing.View] -and $w.Name -eq $ViewName -and "$($w.ViewType)" -eq $ViewType){ return $w } } }
function Marks { $r=@{}; $e=(TV).GetAllObjects(); while($e.MoveNext()){ $o=$e.Current; if($o -is [Tekla.Structures.Drawing.Mark] -and $o.Attributes.Content.Count -gt 0){ $q=$o.GetRelatedObjects(); while($q.MoveNext()){ if($q.Current -is [Tekla.Structures.Drawing.ModelObject] -and $RebarIds -contains $q.Current.ModelIdentifier.ID){ $id=$q.Current.ModelIdentifier.ID; if(-not $r[$id]){$r[$id]=@()}; $r[$id]+=$o } } } }; $r }
$p=Get-Process TeklaStructures | ? { $_.MainWindowHandle -ne 0 } | Select -First 1; $win=[TkWin2]::Find([uint32]$p.Id); "window $win"
$before=Marks; $nb=0; foreach($k in $before.Keys){ $nb+=$before[$k].Count }; "visible marks before: $nb"
$al=New-Object System.Collections.ArrayList; $e=(TV).GetAllObjects(); while($e.MoveNext()){ $o=$e.Current; if($o -is [Tekla.Structures.Drawing.ReinforcementBase] -and $RebarIds -contains $o.ModelIdentifier.ID){ [void]$al.Add($o) } }
$sel=$dh.GetDrawingObjectSelector(); [void]$sel.UnselectAllObjects(); [void]$sel.SelectObjects($al,$false); "selected rebars $($al.Count)"
$name="Claude_RebarMarkCreate.cs"
@"
#pragma warning disable 1633
#pragma reference "Tekla.Macros.Akit"
#pragma reference "Tekla.Macros.Runtime"
#pragma warning restore 1633
namespace UserMacros { public sealed class Macro { [Tekla.Macros.Runtime.MacroEntryPointAttribute()]
public static void Run(Tekla.Macros.Runtime.IMacroRuntime runtime) {
Tekla.Macros.Akit.IAkitScriptHost akit = runtime.Get<Tekla.Macros.Akit.IAkitScriptHost>();
string log = @"$LogFile"; System.IO.File.WriteAllText(log, "start\r\n");
System.Action<string, System.Action> step = (n, a) => { try { a(); System.IO.File.AppendAllText(log, "ok " + n + "\r\n"); } catch (System.Exception ex) { System.IO.File.AppendAllText(log, "ERR " + n + ": " + ex.Message + "\r\n"); } };
step("open", () => akit.Callback("acmd_display_attr_dialog", "rebar_mark_dial", "main_frame"));
step("load", () => akit.ValueChange("rebar_mark_dial", "gr_rebar_mark_get_menu", "$PropertyFile"));
step("get", () => akit.PushButton("gr_rebar_get", "rebar_mark_dial"));
step("apply", () => akit.PushButton("rebar_apply", "rebar_mark_dial"));
step("ok", () => akit.PushButton("rebar_ok", "rebar_mark_dial"));
step("create", () => akit.Callback("$Cmd", "$CmdParam", "$win"));
}}}
"@ | Set-Content (Join-Path $MacroDir $name) -Encoding utf8
try { [void][Tekla.Structures.Model.Operations.Operation]::RunMacro("..\drawings\$name") } finally { Start-Sleep -Seconds 4; Get-ChildItem $MacroDir -Filter "Claude_RebarMarkCreate.cs*" | Remove-Item -Force -ErrorAction SilentlyContinue }
$after=Marks
foreach($id in $RebarIds){ $b=@($before[$id]).Count; if(-not $before[$id]){$b=0}; $list=@($after[$id]); if(-not $after[$id]){ "rebar $id : no visible mark"; continue }
 foreach($m in $list){ $t=@(); $ce=$m.Attributes.Content.GetEnumerator(); while($ce.MoveNext()){ $x=$ce.Current; if($x -is [Tekla.Structures.Drawing.TextElement]){$t+="'"+$x.Value+"'"} elseif($x -is [Tekla.Structures.Drawing.PropertyElement]){$t+="<"+$x.Value.Name+">"} elseif($x -is [Tekla.Structures.Drawing.NewLineElement]){$t+="/"} elseif($x -is [Tekla.Structures.Drawing.SpaceElement]){} else {$t+=$x.GetType().Name} }
  $nl=0; $c=$m.GetObjects(); while($c.MoveNext()){ if("$($c.Current.LeaderLineType)" -eq 'NormalLeaderLine'){$nl++} }
  "rebar {0}: mark ins({1:F0},{2:F0}) leaders {3} :: {4}" -f $id,$m.InsertionPoint.X,$m.InsertionPoint.Y,$nl,($t -join '') } }



