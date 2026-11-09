using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using ModelContextProtocol.Server;
using Newtonsoft.Json;
using Tekla.Structures.DrawingInternal;
using TSD = Tekla.Structures.Drawing;
using TSG = Tekla.Structures.Geometry3d;
using TSM = Tekla.Structures.Model;

namespace TeklaClaudeMcp
{
    /// <summary>
    /// Cong cu doc drawing va tao/xoa rebar mark trong Tekla Structures 2020 SP14.
    /// Moi tool tra ve chuoi JSON; loi tra ve {"error": "..."}.
    /// Tool ghi (add_rebar_mark, delete_drawing_mark) mac dinh khong ghi gi neu chua xac nhan.
    /// </summary>
    [McpServerToolType]
    public static partial class DrawingTools
    {
        // =================================================================== DOC

        [McpServerTool(Name = "drawing_views", ReadOnly = true)]
        [Description("Liet ke cac view trong drawing dang mo: index, ten, loai, ty le, kich thuoc, so rebar va so mark trong moi view.")]
        public static string DrawingViews()
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                var result = new List<object>();
                int index = 0;
                foreach (TSD.View view in AllViews(drawing))
                {
                    int rebars = 0, marks = 0;
                    TSD.DrawingObjectEnumerator objs = view.GetAllObjects();
                    while (objs.MoveNext())
                    {
                        if (objs.Current is TSD.ReinforcementBase) rebars++;
                        else if (objs.Current is TSD.Mark) marks++;
                    }
                    result.Add(new
                    {
                        index = index,
                        name = view.Name,
                        view_type = view.ViewType.ToString(),
                        scale = view.Attributes.Scale,
                        width = view.Width,
                        height = view.Height,
                        rebar_count = rebars,
                        mark_count = marks
                    });
                    index++;
                }
                return new { drawing = drawing.Name, drawing_mark = drawing.Mark, views = result };
            });
        }

        [McpServerTool(Name = "view_rebars", ReadOnly = true)]
        [Description("Liet ke rebar trong mot view cua drawing dang mo (chon view bang ten hoac '#index'). Loc duoc theo REBAR_SEQ_NO. Moi rebar kem so mark da co.")]
        public static string ViewRebars(
            [Description("Ten view (khop mot phan, khong phan biet hoa thuong) hoac '#2' theo index cua drawing_views.")] string view,
            [Description("Tuy chon: chi lay rebar co REBAR_SEQ_NO nay. 0 = lay tat ca.")] int rebarSeqNo = 0)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                TSD.View v = FindView(drawing, view);
                var model = new TSM.Model();
                var list = new List<object>();

                foreach (TSD.ReinforcementBase rb in RebarsInView(v))
                {
                    RebarInfo info = DescribeRebar(model, rb);
                    if (rebarSeqNo > 0 && info.SeqNo != rebarSeqNo) continue;
                    list.Add(info.ToJson());
                }
                return new { view = v.Name, count = list.Count, rebars = list };
            });
        }

        [McpServerTool(Name = "view_marks", ReadOnly = true)]
        [Description("Liet ke mark (tag) trong mot view: id, diem dat, cac phan tu noi dung, va model id cua doi tuong duoc gan mark.")]
        public static string ViewMarks(
            [Description("Ten view hoac '#index'.")] string view)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                TSD.View v = FindView(drawing, view);
                var marks = new List<object>();

                TSD.DrawingObjectEnumerator objs = v.GetAllObjects(typeof(TSD.Mark));
                while (objs.MoveNext())
                {
                    var m = objs.Current as TSD.Mark;
                    if (m == null) continue;

                    var elements = new List<string>();
                    try
                    {
                        foreach (object el in m.Attributes.Content)
                            elements.Add(DescribeElement(el));
                    }
                    catch (Exception ex) { elements.Add("(khong doc duoc noi dung: " + ex.Message + ")"); }

                    long relatedModelId = 0;
                    string relatedType = null;
                    try
                    {
                        TSD.DrawingObjectEnumerator rel = m.GetRelatedObjects();
                        while (rel.MoveNext())
                        {
                            var mo = rel.Current as TSD.ModelObject;
                            if (mo == null) continue;
                            relatedModelId = mo.ModelIdentifier.ID;
                            relatedType = mo.GetType().Name;
                            break;
                        }
                    }
                    catch { }

                    TSG.Point ip = m.InsertionPoint;
                    marks.Add(new
                    {
                        mark_id = m.GetIdentifier().ID,
                        related_model_id = relatedModelId,
                        related_type = relatedType,
                        insertion_point = ip == null ? null : (object)new { x = Math.Round(ip.X, 1), y = Math.Round(ip.Y, 1) },
                        elements = elements
                    });
                }
                return new { view = v.Name, count = marks.Count, marks = marks };
            });
        }

        // =================================================================== GHI

        [McpServerTool(Name = "add_rebar_mark", Destructive = false)]
        [Description(
            "Tao rebar mark (tag) trong mot view cho rebar co REBAR_SEQ_NO cho truoc, dung file property Reinforcement Mark co san (vd 'TAG CC'). " +
            "MAC DINH dryRun=true: chi bao truoc se tao gi (diem dat, rebar nao). Dat dryRun=false de tao that. " +
            "Thay doi qua API khong Ctrl+Z duoc; xoa bang delete_drawing_mark hoac thu cong.")]
        public static string AddRebarMark(
            [Description("Ten view hoac '#index'.")] string view,
            [Description("REBAR_SEQ_NO cua rebar can tag.")] int rebarSeqNo,
            [Description("Ten file property Reinforcement Mark, vd 'TAG CC'.")] string propertyFile = "TAG CC",
            [Description("So mark toi da tao (mac dinh 1: tag mot nhom dai dien).")] int maxMarks = 1,
            [Description("Chi tao cho rebar chua co mark.")] bool onlyUnmarked = true,
            [Description("Do lech diem dat chu so voi diem tren thanh, theo X, don vi mm tren giay.")] double offsetX = 15,
            [Description("Do lech theo Y, don vi mm tren giay.")] double offsetY = 10,
            [Description("true = chi xem truoc, khong ghi vao drawing.")] bool dryRun = true)
        {
            return Run(delegate
            {
                if (maxMarks < 1) throw new ArgumentException("maxMarks phai >= 1.");

                TSD.Drawing drawing = ActiveDrawing();
                TSD.View v = FindView(drawing, view);
                var model = new TSM.Model();
                double scale = v.Attributes.Scale;
                if (scale <= 0) scale = 1;

                var targets = new List<KeyValuePair<TSD.ReinforcementBase, RebarInfo>>();
                foreach (TSD.ReinforcementBase rb in RebarsInView(v))
                {
                    RebarInfo info = DescribeRebar(model, rb);
                    if (info.SeqNo != rebarSeqNo) continue;
                    if (onlyUnmarked && info.MarkCount > 0) continue;
                    targets.Add(new KeyValuePair<TSD.ReinforcementBase, RebarInfo>(rb, info));
                }

                if (targets.Count == 0)
                {
                    return new
                    {
                        view = v.Name,
                        dry_run = dryRun,
                        message = "Khong co rebar phu hop (REBAR_SEQ_NO=" + rebarSeqNo +
                                  (onlyUnmarked ? ", chua co mark" : "") + ") trong view nay.",
                        created = new object[0]
                    };
                }

                var plan = new List<object>();
                var created = new List<object>();
                foreach (KeyValuePair<TSD.ReinforcementBase, RebarInfo> t in targets.Take(maxMarks))
                {
                    TSD.ReinforcementBase rb = t.Key;
                    RebarInfo info = t.Value;

                    TSG.Point start = PointOnRebarInView(model, rb, v);
                    var text = new TSG.Point(start.X + offsetX * scale, start.Y + offsetY * scale, 0);

                    plan.Add(new
                    {
                        model_id = info.ModelId,
                        seq_no = info.SeqNo,
                        name = info.Name,
                        size = info.Size,
                        number = info.Number,
                        property_file = propertyFile,
                        leader_start = new { x = Math.Round(start.X, 1), y = Math.Round(start.Y, 1) },
                        text_point = new { x = Math.Round(text.X, 1), y = Math.Round(text.Y, 1) }
                    });

                    if (dryRun) continue;

                    var mark = new TSD.Mark(rb);
                    if (!string.IsNullOrWhiteSpace(propertyFile))
                    {
                        mark.Attributes = new TSD.Mark.MarkAttributes(rb, propertyFile);
                    }
                    mark.Placing = new TSD.LeaderLinePlacing(start);
                    mark.InsertionPoint = text;

                    if (!mark.Insert())
                        throw new InvalidOperationException("Mark.Insert() that bai cho rebar " + info.ModelId +
                                                            ". Kiem tra ten property file '" + propertyFile + "'.");
                    created.Add(new { mark_id = mark.GetIdentifier().ID, model_id = info.ModelId });
                }

                if (!dryRun) drawing.CommitChanges("Claude: add_rebar_mark " + rebarSeqNo);

                return new
                {
                    view = v.Name,
                    view_scale = scale,
                    dry_run = dryRun,
                    matching_rebars = targets.Count,
                    planned = plan,
                    created = created
                };
            });
        }

        [McpServerTool(Name = "delete_drawing_mark", Destructive = true)]
        [Description("Xoa mot mark trong view theo mark_id (lay tu view_marks hoac add_rebar_mark). Can confirm=true moi xoa.")]
        public static string DeleteDrawingMark(
            [Description("Ten view hoac '#index'.")] string view,
            [Description("mark_id can xoa.")] int markId,
            [Description("Phai dat true de xoa that.")] bool confirm = false)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                TSD.View v = FindView(drawing, view);

                TSD.DrawingObjectEnumerator objs = v.GetAllObjects(typeof(TSD.Mark));
                while (objs.MoveNext())
                {
                    var m = objs.Current as TSD.Mark;
                    if (m == null || m.GetIdentifier().ID != markId) continue;

                    if (!confirm)
                        return new { view = v.Name, mark_id = markId, found = true, deleted = false, message = "Dat confirm=true de xoa." };

                    bool ok = m.Delete();
                    if (ok) drawing.CommitChanges("Claude: delete mark " + markId);
                    return new { view = v.Name, mark_id = markId, found = true, deleted = ok };
                }
                return new { view = v.Name, mark_id = markId, found = false, deleted = false };
            });
        }

        // =================================================================== HELPERS

        private static string Run(Func<object> body)
        {
            try
            {
                return JsonConvert.SerializeObject(body(), Formatting.Indented);
            }
            catch (Exception ex)
            {
                return JsonConvert.SerializeObject(new { error = ex.Message, type = ex.GetType().Name });
            }
        }

        private static TSD.Drawing ActiveDrawing()
        {
            var dh = new TSD.DrawingHandler();
            if (!dh.GetConnectionStatus())
                throw new InvalidOperationException("Khong ket noi duoc Tekla. Hay mo Tekla 2020 va mot model.");
            TSD.Drawing d = dh.GetActiveDrawing();
            if (d == null)
                throw new InvalidOperationException("Chua co drawing nao dang mo trong Tekla.");
            return d;
        }

        private static List<TSD.View> AllViews(TSD.Drawing drawing)
        {
            var list = new List<TSD.View>();
            TSD.DrawingObjectEnumerator en = drawing.GetSheet().GetAllViews();
            while (en.MoveNext())
            {
                var v = en.Current as TSD.View;
                if (v != null) list.Add(v);
            }
            return list;
        }

        private static TSD.View FindView(TSD.Drawing drawing, string selector)
        {
            if (string.IsNullOrWhiteSpace(selector))
                throw new ArgumentException("Can ten view hoac '#index'.");

            List<TSD.View> views = AllViews(drawing);

            if (selector.StartsWith("#"))
            {
                int idx;
                if (!int.TryParse(selector.Substring(1), out idx) || idx < 0 || idx >= views.Count)
                    throw new ArgumentException("Index view khong hop le. Dung drawing_views de xem danh sach.");
                return views[idx];
            }

            List<TSD.View> exact = views.Where(x => string.Equals(x.Name, selector, StringComparison.OrdinalIgnoreCase)).ToList();
            if (exact.Count == 1) return exact[0];

            List<TSD.View> partial = views.Where(x => x.Name != null &&
                                                      x.Name.IndexOf(selector, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
            if (partial.Count == 1) return partial[0];
            if (partial.Count == 0)
                throw new ArgumentException("Khong tim thay view '" + selector + "'. Dung drawing_views de xem danh sach.");
            throw new ArgumentException("Co " + partial.Count + " view khop '" + selector + "': " +
                                        string.Join(" | ", partial.Select(x => x.Name).ToArray()) + ". Dung '#index'.");
        }

        private static List<TSD.ReinforcementBase> RebarsInView(TSD.View view)
        {
            var list = new List<TSD.ReinforcementBase>();
            TSD.DrawingObjectEnumerator objs = view.GetAllObjects();
            while (objs.MoveNext())
            {
                var rb = objs.Current as TSD.ReinforcementBase;
                if (rb != null) list.Add(rb);
            }
            return list;
        }

        private sealed class RebarInfo
        {
            public long ModelId;
            public int SeqNo;
            public string Name;
            public string Size;
            public string Grade;
            public int Number;
            public double Length;
            public int MarkCount;

            public object ToJson()
            {
                return new
                {
                    model_id = ModelId,
                    seq_no = SeqNo,
                    name = Name,
                    size = Size,
                    grade = Grade,
                    number = Number,
                    length_mm = Math.Round(Length, 0),
                    mark_count = MarkCount
                };
            }
        }

        private static RebarInfo DescribeRebar(TSM.Model model, TSD.ReinforcementBase rb)
        {
            var info = new RebarInfo();
            info.ModelId = rb.ModelIdentifier.ID;

            TSM.ModelObject mo = model.SelectModelObject(rb.ModelIdentifier);
            if (mo != null)
            {
                var reinf = mo as TSM.Reinforcement;
                if (reinf != null) info.Name = reinf.Name;

                int seq = 0;
                string seqText = null;
                if (mo.GetReportProperty("REBAR_SEQ_NO", ref seq)) info.SeqNo = seq;
                else if (mo.GetUserProperty("REBAR_SEQ_NO", ref seqText) && int.TryParse(seqText, out seq)) info.SeqNo = seq;
                else if (mo.GetUserProperty("REBAR_SEQ_NO", ref seq)) info.SeqNo = seq;

                string size = null, grade = null;
                if (mo.GetReportProperty("SIZE", ref size)) info.Size = size;
                if (mo.GetReportProperty("GRADE", ref grade)) info.Grade = grade;

                int number = 0;
                if (mo.GetReportProperty("NUMBER", ref number)) info.Number = number;

                double length = 0;
                if (mo.GetReportProperty("LENGTH", ref length)) info.Length = length;
            }

            try
            {
                TSD.DrawingObjectEnumerator related = rb.GetRelatedObjects(new Type[] { typeof(TSD.Mark) });
                while (related.MoveNext())
                {
                    if (related.Current is TSD.Mark) info.MarkCount++;
                }
            }
            catch { }

            return info;
        }

        /// <summary>
        /// Diem giua doan dai nhat cua thanh dau tien trong nhom, doi sang toa do view.
        /// Hinh hoc rebar (mat phang lam viec hien tai) -> toan cuc -> DisplayCoordinateSystem cua view.
        /// </summary>
        private static TSG.Point PointOnRebarInView(TSM.Model model, TSD.ReinforcementBase rb, TSD.View view)
        {
            var reinf = model.SelectModelObject(rb.ModelIdentifier) as TSM.Reinforcement;
            if (reinf == null)
                throw new InvalidOperationException("Khong doc duoc rebar " + rb.ModelIdentifier.ID + " trong model.");

            ArrayList geometries = reinf.GetRebarGeometries(false);
            if (geometries == null || geometries.Count == 0)
                throw new InvalidOperationException("Rebar " + rb.ModelIdentifier.ID + " khong co hinh hoc.");

            var first = geometries[0] as TSM.RebarGeometry;
            ArrayList pts = first.Shape.Points;

            TSG.Point a = (TSG.Point)pts[0], b = (TSG.Point)pts[pts.Count > 1 ? 1 : 0];
            double best = -1;
            for (int i = 0; i + 1 < pts.Count; i++)
            {
                var p = (TSG.Point)pts[i];
                var q = (TSG.Point)pts[i + 1];
                double d = TSG.Distance.PointToPoint(p, q);
                if (d > best) { best = d; a = p; b = q; }
            }
            var mid = new TSG.Point((a.X + b.X) / 2.0, (a.Y + b.Y) / 2.0, (a.Z + b.Z) / 2.0);

            TSG.Matrix toGlobal = model.GetWorkPlaneHandler().GetCurrentTransformationPlane().TransformationMatrixToGlobal;
            TSG.Point global = toGlobal.Transform(mid);

            TSG.Matrix toView = TSG.MatrixFactory.ToCoordinateSystem(view.DisplayCoordinateSystem);
            TSG.Point local = toView.Transform(global);
            return new TSG.Point(local.X, local.Y, 0);
        }

        private static string DescribeElement(object el)
        {
            var pe = el as TSD.PropertyElement;
            if (pe != null) return "Property: " + pe.Name;
            var te = el as TSD.TextElement;
            if (te != null) return "Text: " + te.Value;
            return el == null ? "null" : el.GetType().Name;
        }
    }
}
