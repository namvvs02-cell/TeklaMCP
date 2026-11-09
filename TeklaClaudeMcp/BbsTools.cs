using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using ModelContextProtocol.Server;
using Tekla.Structures.DrawingInternal;
using TS = Tekla.Structures;
using TSD = Tekla.Structures.Drawing;
using TSM = Tekla.Structures.Model;

namespace TeklaClaudeMcp
{
    /// <summary>
    /// Bar Bending Schedule (BBS) cua mot cast unit / assembly, tinh lai tu model theo dung cong thuc
    /// cua template drawing 'BBS_Auto_5Col.tpl':
    ///   Mark = USERDEFINED.REBAR_SEQ_NO (tang dan), Qty = NUMBER, Dia = SIZE, Length = DIM_L,
    ///   Total length (m) = NUMBER * DIM_L / 1000, Weight (kg) = WEIGHT * NUMBER; dong giong nhau duoc cong gop.
    /// Tekla Open API khong doc duoc noi dung hien thi cua bang trong layout, nen tool tinh lai tu model.
    /// </summary>
    public static partial class DrawingTools
    {
        [McpServerTool(Name = "drawing_bbs", ReadOnly = true)]
        [Description(
            "Bang thong ke thep (BBS) cua cast unit trong drawing dang mo (hoac assemblyId), tinh lai tu model theo cong thuc template BBS_Auto_5Col: " +
            "Mark=REBAR_SEQ_NO, Qty=NUMBER, Dia=SIZE, Length=DIM_L, Shape, Total length (m)=Qty*L/1000, Weight (kg)=WEIGHT*Qty; dong giong nhau cong gop. " +
            "Tra ve tong trong luong, ten bang BBS co trong layout, va canh bao: thep chua danh so, mot Mark co nhieu Dia/Length/Shape.")]
        public static string DrawingBbs(
            [Description("Tuy chon: Tekla ID cua assembly/cast unit. Bo trong = cast unit cua drawing dang mo.")] long? assemblyId = null,
            [Description("So dong toi da tra ve (van tinh tong cho tat ca).")] int maxRows = 500)
        {
            return Run(delegate
            {
                var model = new TSM.Model();
                if (!model.GetConnectionStatus())
                    throw new InvalidOperationException("Khong ket noi duoc Tekla model.");

                string drawingName = null;
                var bbsTables = new List<string>();
                if (assemblyId == null)
                {
                    TSD.Drawing d = ActiveDrawing();
                    drawingName = d.Name;
                    var cud = d as TSD.CastUnitDrawing;
                    var ad = d as TSD.AssemblyDrawing;
                    if (cud != null) assemblyId = cud.CastUnitIdentifier.ID;
                    else if (ad != null) assemblyId = ad.AssemblyIdentifier.ID;
                    else throw new InvalidOperationException("Drawing dang mo khong phai Cast unit / Assembly drawing. Truyen assemblyId.");
                    bbsTables = LayoutTableNames().Where(n => n.IndexOf("BBS", StringComparison.OrdinalIgnoreCase) >= 0).Distinct().ToList();
                }

                var asm = model.SelectModelObject(new TS.Identifier((int)assemblyId.Value)) as TSM.Assembly;
                if (asm == null) throw new ArgumentException("Khong tim thay assembly " + assemblyId + ".");
                string pos = null, name = null;
                asm.GetReportProperty("ASSEMBLY_POS", ref pos);
                asm.GetReportProperty("NAME", ref name);

                // Thep cua moi part trong assembly, ke ca sub-assembly
                var parts = new List<TSM.ModelObject>();
                CollectParts(asm, parts);
                var bars = new List<BbsBar>();
                var seen = new HashSet<int>();
                foreach (TSM.ModelObject p in parts)
                {
                    var part = p as TSM.Part;
                    if (part == null) continue;
                    TSM.ModelObjectEnumerator en = part.GetReinforcements();
                    while (en.MoveNext())
                    {
                        var r = en.Current as TSM.Reinforcement;
                        if (r == null || !seen.Add(r.Identifier.ID)) continue;
                        bars.Add(ReadBar(r));
                    }
                }

                var rows = bars
                    .GroupBy(b => new { b.Seq, b.Size, b.L, b.Shape })
                    .Select(g => new
                    {
                        mark = g.Key.Seq,
                        qty = g.Sum(b => b.N),
                        dia = g.Key.Size,
                        length_mm = g.Key.L,
                        shape = g.Key.Shape,
                        total_length_m = Math.Round(g.Sum(b => b.N * (double)b.L) / 1000.0, 2),
                        weight_kg = Math.Round(g.Sum(b => b.W * b.N), 2),
                        rebar_ids = g.Select(b => b.Id).ToList()
                    })
                    .OrderBy(x => x.mark).ThenBy(x => x.length_mm)
                    .ToList();

                var warnings = new List<string>();
                int unnumbered = bars.Where(b => b.Seq == 0).Sum(b => b.N);
                if (unnumbered > 0) warnings.Add(unnumbered + " thanh chua co REBAR_SEQ_NO (Mark = 0).");
                foreach (var g in rows.Where(x => x.mark > 0).GroupBy(x => x.mark).Where(g => g.Count() > 1))
                    warnings.Add("Mark " + g.Key + " co " + g.Count() + " loai khac nhau: " +
                                 string.Join("; ", g.Select(x => "H" + x.dia + " L=" + x.length_mm + " shape " + x.shape)));

                return new
                {
                    drawing = drawingName,
                    assembly_id = assemblyId,
                    assembly_pos = pos,
                    assembly_name = name,
                    layout_bbs_tables = bbsTables,
                    parts = parts.Count,
                    rebar_objects = bars.Count,
                    rows_count = rows.Count,
                    total_bars = rows.Sum(x => x.qty),
                    total_length_m = Math.Round(rows.Sum(x => x.total_length_m), 2),
                    total_weight_kg = Math.Round(rows.Sum(x => x.weight_kg), 2),
                    weight_by_dia_kg = rows.GroupBy(x => x.dia).OrderBy(g => DiaValue(g.Key))
                                           .ToDictionary(g => g.Key ?? "", g => Math.Round(g.Sum(x => x.weight_kg), 2)),
                    warnings = warnings,
                    rows = rows.Take(Math.Max(1, maxRows)),
                    note = "Tinh lai tu model theo cong thuc template BBS_Auto_5Col (khong doc truc tiep bang hien thi tren layout)."
                };
            });
        }

        private sealed class BbsBar
        {
            public int Id, Seq, N;
            public string Size, Shape;
            public long L;
            public double W;
        }

        private static BbsBar ReadBar(TSM.Reinforcement r)
        {
            var b = new BbsBar { Id = r.Identifier.ID };
            int seq = 0; string seqText = null;
            if (r.GetReportProperty("USERDEFINED.REBAR_SEQ_NO", ref seq)) b.Seq = seq;
            else if (r.GetUserProperty("REBAR_SEQ_NO", ref seqText) && int.TryParse(seqText, out seq)) b.Seq = seq;
            else if (r.GetUserProperty("REBAR_SEQ_NO", ref seq)) b.Seq = seq;

            int n = 0; string size = null, shape = null; double l = 0, w = 0;
            r.GetReportProperty("NUMBER", ref n); b.N = n;
            r.GetReportProperty("SIZE", ref size); b.Size = size;
            r.GetReportProperty("SHAPE", ref shape); b.Shape = shape;
            r.GetReportProperty("DIM_L", ref l); b.L = (long)Math.Round(l, MidpointRounding.AwayFromZero);
            r.GetReportProperty("WEIGHT", ref w); b.W = w;
            return b;
        }

        private static void CollectParts(TSM.Assembly a, List<TSM.ModelObject> parts)
        {
            TSM.ModelObject main = a.GetMainPart();
            if (main != null) parts.Add(main);
            foreach (object o in a.GetSecondaries())
            {
                var mo = o as TSM.ModelObject;
                if (mo != null) parts.Add(mo);
            }
            foreach (object o in a.GetSubAssemblies())
            {
                var sub = o as TSM.Assembly;
                if (sub != null) CollectParts(sub, parts);
            }
        }

        private static double DiaValue(string size)
        {
            double d;
            return double.TryParse(size, out d) ? d : double.MaxValue;
        }

        /// <summary>Ten cac bang (template) trong layout cua drawing dang mo; API noi bo, loi thi tra rong.</summary>
        private static List<string> LayoutTableNames()
        {
            var names = new List<string>();
            try
            {
                foreach (int id in TableLayout.GetCurrentTables())
                {
                    var t = new LayoutTable { Id = id };
                    if (t.Select() && !string.IsNullOrEmpty(t.Name)) names.Add(t.Name);
                }
            }
            catch { }
            return names;
        }
    }
}
