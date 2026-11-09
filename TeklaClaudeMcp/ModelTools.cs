using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using ModelContextProtocol.Server;
using Newtonsoft.Json;
using Tekla.Structures.DrawingInternal;
using TS = Tekla.Structures;
using TSD = Tekla.Structures.Drawing;
using TSG = Tekla.Structures.Geometry3d;
using TSM = Tekla.Structures.Model;
using TSMUI = Tekla.Structures.Model.UI;

namespace TeklaClaudeMcp
{
    /// <summary>
    /// Tool lam viec voi model (doc, chon, tao cot) va danh sach drawing - giu dung ten tool cua server cu.
    /// </summary>
    [McpServerToolType]
    public static class ModelTools
    {
        // ------------------------------------------------------------------ ket noi

        [McpServerTool(Name = "get_model_info", ReadOnly = true)]
        [Description("Trang thai ket noi Tekla, phien ban, ten/duong dan model dang mo va drawing dang mo (neu co).")]
        public static string GetModelInfo()
        {
            return Util.Run(delegate
            {
                var model = new TSM.Model();
                bool ok = model.GetConnectionStatus();
                TSM.ModelInfo info = ok ? model.GetInfo() : null;

                object activeDrawing = null;
                try
                {
                    var dh = new TSD.DrawingHandler();
                    if (dh.GetConnectionStatus())
                    {
                        TSD.Drawing d = dh.GetActiveDrawing();
                        if (d != null) activeDrawing = Util.DescribeDrawing(d);
                    }
                }
                catch { }

                string version = null;
                try { version = TS.TeklaStructuresInfo.GetCurrentProgramVersion(); } catch { }

                return new
                {
                    connected = ok,
                    server = "TeklaClaudeMcp " + Util.Version + " (Tekla 2020, model + drawing)",
                    tekla_version = version,
                    install_dir = TeklaEnvironment.InstallDir,
                    session_name = Environment.GetEnvironmentVariable("SESSIONNAME"),
                    model_name = info != null ? info.ModelName : null,
                    model_path = info != null ? info.ModelPath : null,
                    active_drawing = activeDrawing
                };
            });
        }

        // ------------------------------------------------------------------ doc model

        [McpServerTool(Name = "get_selected_objects", ReadOnly = true)]
        [Description("Liet ke cac doi tuong dang chon trong model view (part, rebar, assembly...) voi thuoc tinh chinh.")]
        public static string GetSelectedObjects(
            [Description("So doi tuong toi da tra ve.")] int maxCount = 200)
        {
            return Util.Run(delegate
            {
                Util.RequireModel();
                var list = new List<object>();
                int total = 0;
                TSM.ModelObjectEnumerator en = new TSMUI.ModelObjectSelector().GetSelectedObjects();
                while (en.MoveNext())
                {
                    if (en.Current == null) continue;
                    total++;
                    if (list.Count < maxCount) list.Add(Util.DescribeObject(en.Current));
                }
                return new { total_selected = total, objects = list };
            });
        }

        [McpServerTool(Name = "get_object", ReadOnly = true)]
        [Description("Thuoc tinh chinh cua mot doi tuong model theo Tekla ID.")]
        public static string GetObject(
            [Description("Tekla object ID.")] int id)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                TSM.ModelObject mo = model.SelectModelObject(new TS.Identifier(id));
                if (mo == null) throw new ArgumentException("Khong tim thay doi tuong " + id + ".");
                return Util.DescribeObject(mo);
            });
        }

        [McpServerTool(Name = "find_objects", ReadOnly = true)]
        [Description("Tim doi tuong model theo loai (ten ModelObjectEnum, vd BEAM, CONTOURPLATE, REBARGROUP, SINGLEREBAR, ASSEMBLY), loc tuy chon theo NAME.")]
        public static string FindObjects(
            [Description("Ten ModelObjectEnum, vd BEAM hoac REBARGROUP.")] string type,
            [Description("Loc tuy chon: NAME chua chuoi nay (khong phan biet hoa thuong).")] string nameContains = null,
            [Description("So doi tuong toi da tra ve.")] int maxCount = 200)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                TSM.ModelObject.ModelObjectEnum e;
                if (!Enum.TryParse(type, true, out e))
                    throw new ArgumentException("Loai '" + type + "' khong hop le. Vi du: BEAM, POLYBEAM, CONTOURPLATE, ASSEMBLY, REBARGROUP, SINGLEREBAR.");

                var list = new List<object>();
                int total = 0;
                TSM.ModelObjectEnumerator en = model.GetModelObjectSelector().GetAllObjectsWithType(e);
                while (en.MoveNext())
                {
                    TSM.ModelObject mo = en.Current;
                    if (mo == null) continue;
                    if (!string.IsNullOrEmpty(nameContains))
                    {
                        string n = Util.NameOf(mo);
                        if (n == null || n.IndexOf(nameContains, StringComparison.OrdinalIgnoreCase) < 0) continue;
                    }
                    total++;
                    if (list.Count < maxCount) list.Add(Util.DescribeObject(mo));
                }
                return new { total = total, objects = list };
            });
        }

        [McpServerTool(Name = "list_rebars", ReadOnly = true)]
        [Description("Liet ke rebar (size, grade, shape, position, so luong, chieu dai, khoi luong, REBAR_SEQ_NO) cua mot part, mot assembly (ca sub-assembly), hoac cua lua chon hien tai.")]
        public static string ListRebars(
            [Description("Tuy chon: Tekla ID cua part chu.")] int? partId = null,
            [Description("Tuy chon: Tekla ID cua assembly; lay rebar cua moi part.")] int? assemblyId = null,
            [Description("So rebar toi da tra ve.")] int maxCount = 500)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                List<TSM.Reinforcement> rebars;
                if (assemblyId.HasValue) rebars = Util.RebarsOfAssembly(Util.Require<TSM.Assembly>(model, assemblyId.Value, "assembly"));
                else if (partId.HasValue) rebars = Util.RebarsOfPart(Util.Require<TSM.Part>(model, partId.Value, "part"));
                else rebars = Util.RebarsOfSelection();

                var list = rebars.Take(maxCount).Select(r => Util.DescribeRebar(r)).ToList();
                return new { total = rebars.Count, rebars = list };
            });
        }

        [McpServerTool(Name = "get_report_properties", ReadOnly = true)]
        [Description("Doc report property hoac UDA cua mot doi tuong, vd WEIGHT, LENGTH, ASSEMBLY_POS, PROFILE, USERDEFINED.xxx.")]
        public static string GetReportProperties(
            [Description("Tekla object ID.")] int id,
            [Description("Danh sach ten report property.")] string[] names)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                TSM.ModelObject mo = model.SelectModelObject(new TS.Identifier(id));
                if (mo == null) throw new ArgumentException("Khong tim thay doi tuong " + id + ".");
                var props = new Dictionary<string, object>();
                foreach (string n in names ?? new string[0])
                    props[n] = Util.ReadProperty(mo, n);
                return new { id = id, properties = props };
            });
        }

        // ------------------------------------------------------------------ chon / tao

        [McpServerTool(Name = "select_objects")]
        [Description("Chon (highlight) doi tuong trong model view theo ID. Chi doi lua chon, khong sua model.")]
        public static string SelectObjects(
            [Description("Danh sach Tekla object ID.")] int[] ids)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                var objs = new ArrayList();
                var missing = new List<int>();
                foreach (int id in ids ?? new int[0])
                {
                    TSM.ModelObject mo = model.SelectModelObject(new TS.Identifier(id));
                    if (mo != null) objs.Add(mo); else missing.Add(id);
                }
                bool ok = new TSMUI.ModelObjectSelector().Select(objs);
                return new { selected = objs.Count, ok = ok, not_found = missing };
            });
        }

        [McpServerTool(Name = "create_column", Destructive = false)]
        [Description("Tao mot cot thang dung trong model dang mo va commit. Toa do toan cuc, mm. Thay doi model: Ctrl+Z khong hoan tac duoc thay doi qua API, xoa part de tra lai.")]
        public static string CreateColumn(
            [Description("X cua truc cot (mm).")] double x,
            [Description("Y cua truc cot (mm).")] double y,
            [Description("Z day cot (mm).")] double bottomZ = 0,
            [Description("Z dinh cot (mm).")] double topZ = 3000,
            [Description("Profile, vd HEA300 hoac 400*400 cho be tong.")] string profile = "HEA300",
            [Description("Vat lieu, vd S235JR hoac C30/37.")] string material = "S235JR",
            [Description("Ten part.")] string name = "COLUMN",
            [Description("Tekla class (mau).")] string partClass = "2")
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                TSG.Matrix toLocal = model.GetWorkPlaneHandler().GetCurrentTransformationPlane().TransformationMatrixToLocal;

                var beam = new TSM.Beam(TSM.Beam.BeamTypeEnum.COLUMN);
                beam.StartPoint = toLocal.Transform(new TSG.Point(x, y, bottomZ));
                beam.EndPoint = toLocal.Transform(new TSG.Point(x, y, topZ));
                beam.Profile.ProfileString = profile;
                beam.Material.MaterialString = material;
                beam.Name = name;
                beam.Class = partClass;
                beam.Position.Depth = TSM.Position.DepthEnum.MIDDLE;
                beam.Position.Plane = TSM.Position.PlaneEnum.MIDDLE;

                if (!beam.Insert()) throw new InvalidOperationException("Beam.Insert() that bai. Kiem tra profile/material.");
                model.CommitChanges("Claude: create_column");
                return Util.DescribeObject(beam);
            });
        }

        // ------------------------------------------------------------------ drawing list / annotate

        [McpServerTool(Name = "list_drawings", ReadOnly = true)]
        [Description("Liet ke drawing trong model (ten, mark, loai, title, trang thai up-to-date) va drawing dang mo neu co.")]
        public static string ListDrawings(
            [Description("So drawing toi da tra ve.")] int maxCount = 300)
        {
            return Util.Run(delegate
            {
                var dh = new TSD.DrawingHandler();
                if (!dh.GetConnectionStatus()) throw new InvalidOperationException("Khong ket noi duoc Tekla.");
                TSD.Drawing active = dh.GetActiveDrawing();

                var list = new List<object>();
                int total = 0;
                TSD.DrawingEnumerator en = dh.GetDrawings();
                while (en.MoveNext())
                {
                    TSD.Drawing d = en.Current;
                    if (d == null) continue;
                    total++;
                    if (list.Count < maxCount) list.Add(Util.DescribeDrawing(d));
                }
                return new { active_drawing = active == null ? null : Util.DescribeDrawing(active), total = total, drawings = list };
            });
        }

        [McpServerTool(Name = "annotate_active_drawing", Destructive = false)]
        [Description("Them mot dim tong ngang + dung va mot part mark cho moi part trong moi view cua drawing dang mo, roi commit. " +
                     "Mac dinh confirm=false: chi dem se them bao nhieu. Dat confirm=true de ghi.")]
        public static string AnnotateActiveDrawing(
            [Description("Them dim tong.")] bool addDimensions = true,
            [Description("Them part mark.")] bool addMarks = true,
            [Description("Khoang cach tu part toi duong dim, mm tren giay.")] double paperOffsetMm = 10,
            [Description("true = ghi that vao drawing.")] bool confirm = false)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();
                TSD.Drawing drawing = Util.ActiveDrawing();
                var dimHandler = new TSD.StraightDimensionSetHandler();
                int parts = 0, dims = 0, marks = 0, failed = 0;

                foreach (TSD.View view in Util.AllViews(drawing))
                {
                    double scale = view.Attributes.Scale > 0 ? view.Attributes.Scale : 1;
                    TSD.DrawingObjectEnumerator objs = view.GetAllObjects(typeof(TSD.Part));
                    while (objs.MoveNext())
                    {
                        var dp = objs.Current as TSD.Part;
                        if (dp == null) continue;
                        parts++;
                        if (!confirm) continue;
                        try
                        {
                            if (addMarks)
                            {
                                var mark = new TSD.Mark(dp);
                                if (mark.Insert()) marks++; else failed++;
                            }
                            if (addDimensions)
                            {
                                double[] box = Util.PartBoxInView(model, dp.ModelIdentifier, view);
                                if (box == null) { failed++; continue; }
                                double minX = box[0], minY = box[1], maxX = box[2], maxY = box[3];

                                var h = new TSD.PointList();
                                h.Add(new TSG.Point(minX, maxY, 0));
                                h.Add(new TSG.Point(maxX, maxY, 0));
                                if (dimHandler.CreateDimensionSet(view, h, new TSG.Vector(0, 1, 0), paperOffsetMm * scale) != null) dims++; else failed++;

                                var v = new TSD.PointList();
                                v.Add(new TSG.Point(maxX, minY, 0));
                                v.Add(new TSG.Point(maxX, maxY, 0));
                                if (dimHandler.CreateDimensionSet(view, v, new TSG.Vector(1, 0, 0), paperOffsetMm * scale) != null) dims++; else failed++;
                            }
                        }
                        catch { failed++; }
                    }
                }

                if (confirm) drawing.CommitChanges("Claude: annotate_active_drawing");
                return new
                {
                    drawing = drawing.Name,
                    confirm = confirm,
                    parts_found = parts,
                    marks_added = marks,
                    dimensions_added = dims,
                    failed = failed,
                    message = confirm ? null : "Chua ghi gi. Dat confirm=true de them mark/dim."
                };
            });
        }
    }

    /// <summary>Ham dung chung cho cac tool.</summary>
    internal static class Util
    {
        public const string Version = "2.0";

        public static string Run(Func<object> body)
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

        public static TSM.Model RequireModel()
        {
            var model = new TSM.Model();
            if (!model.GetConnectionStatus())
                throw new InvalidOperationException("Tekla Structures model chua mo hoac khong ket noi duoc. Hay mo mot model trong Tekla 2020.");
            return model;
        }

        public static T Require<T>(TSM.Model model, int id, string what) where T : TSM.ModelObject
        {
            TSM.ModelObject mo = model.SelectModelObject(new TS.Identifier(id));
            var t = mo as T;
            if (t == null) throw new ArgumentException("Doi tuong " + id + " khong phai " + what + ".");
            return t;
        }

        public static TSD.Drawing ActiveDrawing()
        {
            var dh = new TSD.DrawingHandler();
            if (!dh.GetConnectionStatus())
                throw new InvalidOperationException("Khong ket noi duoc Tekla. Hay mo Tekla 2020 va mot model.");
            TSD.Drawing d = dh.GetActiveDrawing();
            if (d == null) throw new InvalidOperationException("Chua co drawing nao dang mo trong Tekla.");
            return d;
        }

        public static List<TSD.View> AllViews(TSD.Drawing drawing)
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

        public static object DescribeDrawing(TSD.Drawing d)
        {
            return new
            {
                type = d.GetType().Name,
                name = d.Name,
                mark = d.Mark,
                title1 = d.Title1,
                title2 = d.Title2,
                title3 = d.Title3,
                up_to_date_status = d.UpToDateStatus.ToString()
            };
        }

        public static string NameOf(TSM.ModelObject mo)
        {
            var p = mo as TSM.Part; if (p != null) return p.Name;
            var a = mo as TSM.Assembly; if (a != null) return a.Name;
            var r = mo as TSM.Reinforcement; if (r != null) return r.Name;
            string n = null;
            mo.GetReportProperty("NAME", ref n);
            return n;
        }

        public static string Str(TSM.ModelObject mo, string prop)
        {
            string s = null;
            return mo.GetReportProperty(prop, ref s) ? s : null;
        }

        public static double? Dbl(TSM.ModelObject mo, string prop)
        {
            double d = 0;
            return mo.GetReportProperty(prop, ref d) ? (double?)d : null;
        }

        public static int? Int(TSM.ModelObject mo, string prop)
        {
            int i = 0;
            return mo.GetReportProperty(prop, ref i) ? (int?)i : null;
        }

        public static object ReadProperty(TSM.ModelObject mo, string name)
        {
            string s = null; double d = 0; int i = 0;
            if (mo.GetReportProperty(name, ref s)) return s;
            if (mo.GetReportProperty(name, ref d)) return d;
            if (mo.GetReportProperty(name, ref i)) return i;
            if (name.StartsWith("USERDEFINED.", StringComparison.OrdinalIgnoreCase))
            {
                string uda = name.Substring("USERDEFINED.".Length);
                if (mo.GetUserProperty(uda, ref s) && !string.IsNullOrEmpty(s)) return s;
                if (mo.GetUserProperty(uda, ref i) && i != 0) return i;
                if (mo.GetUserProperty(uda, ref d) && d != 0) return d;
            }
            return null;
        }

        public static object DescribeObject(TSM.ModelObject mo)
        {
            var reinf = mo as TSM.Reinforcement;
            if (reinf != null) return DescribeRebar(reinf);

            var part = mo as TSM.Part;
            if (part != null)
            {
                TSM.Assembly asm = null;
                try { asm = part.GetAssembly(); } catch { }
                return new
                {
                    id = mo.Identifier.ID,
                    guid = mo.Identifier.GUID.ToString(),
                    type = mo.GetType().Name,
                    name = part.Name,
                    profile = part.Profile != null ? part.Profile.ProfileString : null,
                    material = part.Material != null ? part.Material.MaterialString : null,
                    @class = part.Class,
                    finish = part.Finish,
                    part_pos = Str(mo, "PART_POS"),
                    assembly_pos = Str(mo, "ASSEMBLY_POS"),
                    assembly_id = asm != null ? (int?)asm.Identifier.ID : null,
                    length_mm = Round(Dbl(mo, "LENGTH")),
                    weight_kg = Round(Dbl(mo, "WEIGHT"), 3)
                };
            }

            var assembly = mo as TSM.Assembly;
            if (assembly != null)
            {
                TSM.ModelObject main = null;
                try { main = assembly.GetMainPart(); } catch { }
                return new
                {
                    id = mo.Identifier.ID,
                    guid = mo.Identifier.GUID.ToString(),
                    type = "Assembly",
                    name = assembly.Name,
                    assembly_pos = Str(mo, "ASSEMBLY_POS"),
                    main_part_id = main != null ? (int?)main.Identifier.ID : null,
                    weight_kg = Round(Dbl(mo, "WEIGHT"), 3)
                };
            }

            return new
            {
                id = mo.Identifier.ID,
                guid = mo.Identifier.GUID.ToString(),
                type = mo.GetType().Name,
                name = NameOf(mo)
            };
        }

        public static object DescribeRebar(TSM.Reinforcement r)
        {
            var host = r.Father as TSM.Part;
            return new
            {
                id = r.Identifier.ID,
                guid = r.Identifier.GUID.ToString(),
                type = r.GetType().Name,
                name = r.Name,
                @class = r.Class,
                size = Str(r, "SIZE"),
                grade = r.Grade,
                shape = Str(r, "SHAPE"),
                rebar_pos = Str(r, "REBAR_POS"),
                number = Int(r, "NUMBER"),
                length_mm = Round(Dbl(r, "LENGTH")),
                weight_kg = Round(Dbl(r, "WEIGHT"), 3),
                host_name = host != null ? host.Name : null,
                host_id = host != null ? (int?)host.Identifier.ID : null,
                rebar_seq_no = SeqText(r)
            };
        }

        public static double? Round(double? v, int digits = 0)
        {
            return v.HasValue ? (double?)Math.Round(v.Value, digits) : null;
        }

        /// <summary>REBAR_SEQ_NO doc tu UDA (so nguyen hoac chuoi), du phong report property.</summary>
        public static int? SeqNo(TSM.ModelObject mo)
        {
            int i = 0; string s = null;
            if (mo.GetUserProperty("REBAR_SEQ_NO", ref i) && i > 0) return i;
            if (mo.GetUserProperty("REBAR_SEQ_NO", ref s) && !string.IsNullOrWhiteSpace(s))
            {
                int parsed;
                if (int.TryParse(s.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed) && parsed > 0) return parsed;
            }
            if (mo.GetReportProperty("REBAR_SEQ_NO", ref i) && i > 0) return i;
            return null;
        }

        public static string SeqText(TSM.ModelObject mo)
        {
            int? n = SeqNo(mo);
            return n.HasValue ? n.Value.ToString(CultureInfo.InvariantCulture) : null;
        }

        // ------------------------------------------------------------------ thu thap rebar

        public static List<TSM.Reinforcement> RebarsOfPart(TSM.Part part)
        {
            var list = new List<TSM.Reinforcement>();
            TSM.ModelObjectEnumerator en = part.GetReinforcements();
            while (en.MoveNext())
            {
                var r = en.Current as TSM.Reinforcement;
                if (r != null) list.Add(r);
            }
            return list;
        }

        public static List<TSM.Reinforcement> RebarsOfAssembly(TSM.Assembly assembly)
        {
            var result = new List<TSM.Reinforcement>();
            var seen = new HashSet<int>();
            CollectAssembly(assembly, result, seen, new HashSet<int>());
            return result;
        }

        private static void CollectAssembly(TSM.Assembly a, List<TSM.Reinforcement> result, HashSet<int> seen, HashSet<int> visited)
        {
            if (a == null || !visited.Add(a.Identifier.ID)) return;

            var members = new List<object>();
            try { members.Add(a.GetMainPart()); } catch { }
            try { foreach (object o in a.GetSecondaries()) members.Add(o); } catch { }

            foreach (object o in members)
            {
                var part = o as TSM.Part;
                if (part != null)
                {
                    foreach (TSM.Reinforcement r in RebarsOfPart(part))
                        if (seen.Add(r.Identifier.ID)) result.Add(r);
                    continue;
                }
                var r2 = o as TSM.Reinforcement;
                if (r2 != null && seen.Add(r2.Identifier.ID)) result.Add(r2);
            }

            try
            {
                foreach (object o in a.GetSubAssemblies())
                    CollectAssembly(o as TSM.Assembly, result, seen, visited);
            }
            catch { }
        }

        public static List<TSM.Reinforcement> RebarsOfSelection()
        {
            var result = new List<TSM.Reinforcement>();
            var seen = new HashSet<int>();
            TSM.ModelObjectEnumerator en = new TSMUI.ModelObjectSelector().GetSelectedObjects();
            while (en.MoveNext())
            {
                TSM.ModelObject mo = en.Current;
                var r = mo as TSM.Reinforcement;
                if (r != null) { if (seen.Add(r.Identifier.ID)) result.Add(r); continue; }
                var p = mo as TSM.Part;
                if (p != null) { foreach (TSM.Reinforcement x in RebarsOfPart(p)) if (seen.Add(x.Identifier.ID)) result.Add(x); continue; }
                var a = mo as TSM.Assembly;
                if (a != null) { foreach (TSM.Reinforcement x in RebarsOfAssembly(a)) if (seen.Add(x.Identifier.ID)) result.Add(x); }
            }
            return result;
        }

        public static List<TSM.Reinforcement> RebarsOfModel(TSM.Model model)
        {
            var result = new List<TSM.Reinforcement>();
            var seen = new HashSet<int>();
            var kinds = new[]
            {
                TSM.ModelObject.ModelObjectEnum.SINGLEREBAR,
                TSM.ModelObject.ModelObjectEnum.REBARGROUP,
                TSM.ModelObject.ModelObjectEnum.CURVED_REBARGROUP,
                TSM.ModelObject.ModelObjectEnum.CIRCLE_REBARGROUP,
                TSM.ModelObject.ModelObjectEnum.REBARMESH
            };
            foreach (var k in kinds)
            {
                TSM.ModelObjectEnumerator en = model.GetModelObjectSelector().GetAllObjectsWithType(k);
                while (en.MoveNext())
                {
                    var r = en.Current as TSM.Reinforcement;
                    if (r != null && seen.Add(r.Identifier.ID)) result.Add(r);
                }
            }
            return result;
        }

        /// <summary>Assembly cap cao nhat (PPVC) chua rebar; null neu rebar khong thuoc assembly nao.</summary>
        public static TSM.Assembly TopAssembly(TSM.Reinforcement r)
        {
            var host = r.Father as TSM.Part;
            if (host == null) return null;
            TSM.Assembly a = null;
            try { a = host.GetAssembly(); } catch { }
            int guard = 0;
            while (a != null && guard++ < 50)
            {
                TSM.Assembly father = null;
                try { father = a.GetAssembly(); } catch { }
                if (father == null || father.Identifier.ID == a.Identifier.ID) break;
                a = father;
            }
            return a;
        }

        // ------------------------------------------------------------------ hinh hoc -> view

        /// <summary>Hop bao [minX, minY, maxX, maxY] cua part trong toa do view, hoac null.</summary>
        public static double[] PartBoxInView(TSM.Model model, TS.Identifier id, TSD.View view)
        {
            var part = model.SelectModelObject(id) as TSM.Part;
            if (part == null) return null;
            TSM.Solid solid = part.GetSolid();
            if (solid == null) return null;

            TSG.Point a = solid.MinimumPoint, b = solid.MaximumPoint;
            TSG.Matrix toGlobal = model.GetWorkPlaneHandler().GetCurrentTransformationPlane().TransformationMatrixToGlobal;
            TSG.Matrix toView = TSG.MatrixFactory.ToCoordinateSystem(view.DisplayCoordinateSystem);

            double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
            foreach (double x in new[] { a.X, b.X })
                foreach (double y in new[] { a.Y, b.Y })
                    foreach (double z in new[] { a.Z, b.Z })
                    {
                        TSG.Point p = toView.Transform(toGlobal.Transform(new TSG.Point(x, y, z)));
                        minX = Math.Min(minX, p.X); maxX = Math.Max(maxX, p.X);
                        minY = Math.Min(minY, p.Y); maxY = Math.Max(maxY, p.Y);
                    }
            return new[] { minX, minY, maxX, maxY };
        }
    }
}
