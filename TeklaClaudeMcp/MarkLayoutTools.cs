using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using ModelContextProtocol.Server;
using Tekla.Structures.DrawingInternal;
using TSD = Tekla.Structures.Drawing;
using TSG = Tekla.Structures.Geometry3d;
using TSM = Tekla.Structures.Model;

namespace TeklaClaudeMcp
{
    /// <summary>
    /// Doc mark dang chon tren drawing va sap xep mark (tag) thanh mot cot thang hang,
    /// giu nguyen diem dau leader tren thanh thep (kieu bo tri tag trong mat cat tuong PPVC).
    /// Toa do tra ve/nhan vao la toa do view (mm model); khoang cach "Mm" la mm tren giay (nhan scale).
    /// </summary>
    public static partial class DrawingTools
    {
        // =================================================================== DOC LUA CHON

        [McpServerTool(Name = "get_selected_drawing_marks", ReadOnly = true)]
        [Description(
            "Liet ke cac mark (tag) dang chon tren drawing dang mo: view, mark_id, diem dat chu, diem dau leader, " +
            "khung bao (bounding box), kieu placing, noi dung va rebar/part duoc gan (kem REBAR_SEQ_NO neu la rebar).")]
        public static string GetSelectedDrawingMarks(
            [Description("So mark toi da tra ve.")] int maxCount = 300)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                var model = new TSM.Model();
                List<TSD.Mark> marks = SelectedMarks();
                var views = AllViews(drawing);

                var list = new List<object>();
                foreach (TSD.Mark m in marks.Take(Math.Max(1, maxCount)))
                    list.Add(DescribeMarkForLayout(model, m, views));

                return new
                {
                    drawing = drawing.Name,
                    selected_marks = marks.Count,
                    marks = list
                };
            });
        }

        // =================================================================== GHI

        [McpServerTool(Name = "move_drawing_mark", Destructive = false)]
        [Description(
            "Doi diem dat chu cua mot mark sang (x, y) trong toa do view (mm model), giu diem dau leader. " +
            "MAC DINH dryRun=true. Thay doi qua API khong Ctrl+Z duoc.")]
        public static string MoveDrawingMark(
            [Description("Ten view hoac '#index'.")] string view,
            [Description("mark_id (tu view_marks hoac get_selected_drawing_marks).")] int markId,
            [Description("X moi cua diem dat chu, toa do view.")] double x,
            [Description("Y moi cua diem dat chu, toa do view.")] double y,
            [Description("true = chi xem truoc.")] bool dryRun = true)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                TSD.View v = FindView(drawing, view);
                TSD.Mark m = FindMark(v, markId);
                if (m == null) return new { view = v.Name, mark_id = markId, found = false };

                TSG.Point old = m.InsertionPoint;
                bool ok = true;
                if (!dryRun)
                {
                    m.InsertionPoint = new TSG.Point(x, y, 0);
                    ok = m.Modify();
                    if (ok) drawing.CommitChanges("Claude: move mark " + markId);
                }
                return new
                {
                    view = v.Name,
                    mark_id = markId,
                    found = true,
                    dry_run = dryRun,
                    modified = !dryRun && ok,
                    from = Pt(old),
                    to = new { x = Math.Round(x, 1), y = Math.Round(y, 1) }
                };
            });
        }

        [McpServerTool(Name = "arrange_marks_column", Destructive = false)]
        [Description(
            "Xep cac mark (tag) thanh MOT COT thang hang ben phai (hoac trai) tiet dien, giu diem dau leader tren thanh: " +
            "tag sap theo cao do cua thanh duoc tag, chu canh thang mot duong doc, tag sat nhau thi gian deu (khong chong len nhau). " +
            "Mac dinh lay cac mark DANG CHON tren drawing (co the nhieu view, xu ly rieng tung view); hoac truyen view + markIds. " +
            "MAC DINH dryRun=true: chi tra ve vi tri moi. Dat dryRun=false de ghi. Thay doi qua API khong Ctrl+Z duoc.")]
        public static string ArrangeMarksColumn(
            [Description("'right' (mac dinh), 'left' hoac 'auto' (phia co nhieu dau leader hon so voi tam).")] string side = "right",
            [Description("Khoang cach tu dau leader xa nhat (ve phia 'side') toi mep chu cua cot tag, mm tren giay.")] double offsetMm = 15,
            [Description("Khe ho toi thieu giua hai tag theo phuong dung, mm tren giay.")] double gapMm = 1.5,
            [Description("Tuy chon: X cua mep chu cot tag trong toa do view (mm model). Neu co thi bo qua offsetMm.")] double? columnX = null,
            [Description("Tuy chon: chi xep cac mark nay (can kem view). Bo trong = dung mark dang chon.")] int[] markIds = null,
            [Description("Ten view hoac '#index' khi dung markIds.")] string view = null,
            [Description("true = doi dau mui ten toi DAU THANH thep (diem mut cua thanh ve phia 'side'), thay vi giu diem cu.")] bool leaderAtBarEnd = false,
            [Description("true = leader nam ngang tuyet doi: tam tag dat dung cao do dau mui ten, KHONG gian tag ra; tag sat nhau se duoc bao trong 'overlaps'.")] bool straight = false,
            [Description("true = chi xem truoc, khong ghi vao drawing.")] bool dryRun = true)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                var model = new TSM.Model();
                List<TSD.View> views = AllViews(drawing);

                // --- 1. Gom mark can xep theo view
                var groups = new List<KeyValuePair<TSD.View, List<TSD.Mark>>>();
                if (markIds != null && markIds.Length > 0)
                {
                    if (string.IsNullOrWhiteSpace(view))
                        throw new ArgumentException("Can tham so view khi truyen markIds.");
                    TSD.View v = FindView(drawing, view);
                    var wanted = new HashSet<int>(markIds);
                    var ms = new List<TSD.Mark>();
                    TSD.DrawingObjectEnumerator en = v.GetAllObjects(typeof(TSD.Mark));
                    while (en.MoveNext())
                    {
                        var m = en.Current as TSD.Mark;
                        if (m != null && wanted.Contains(m.GetIdentifier().ID)) ms.Add(m);
                    }
                    groups.Add(new KeyValuePair<TSD.View, List<TSD.Mark>>(v, ms));
                }
                else
                {
                    List<TSD.Mark> selected = SelectedMarks();
                    if (selected.Count == 0)
                        throw new InvalidOperationException("Chua chon mark nao tren drawing. Chon cac tag trong Tekla roi goi lai, hoac truyen view + markIds.");
                    foreach (var g in selected.GroupBy(m => ViewIndexOf(views, m)))
                    {
                        if (g.Key < 0) continue;
                        groups.Add(new KeyValuePair<TSD.View, List<TSD.Mark>>(views[g.Key], g.ToList()));
                    }
                }

                // --- 2. Tinh vi tri moi tung view
                var results = new List<object>();
                int modified = 0, failed = 0;
                foreach (var grp in groups)
                {
                    TSD.View v = grp.Key;
                    double scale = v.Attributes.Scale > 0 ? v.Attributes.Scale : 1;
                    var items = new List<LayoutItem>();
                    var skipped = new List<object>();

                    foreach (TSD.Mark m in grp.Value)
                    {
                        var it = new LayoutItem { Mark = m, Id = m.GetIdentifier().ID, Insertion = m.InsertionPoint };
                        it.Anchor = LeaderStart(m);
                        if (it.Anchor == null)
                        {
                            // Mark khong co leader: neo vao diem tren thanh (neu la rebar) de van xep duoc.
                            it.Anchor = AnchorFromRelated(model, m, v);
                            it.ConvertToLeader = it.Anchor != null;
                        }
                        if (it.Anchor == null)
                        {
                            skipped.Add(new { mark_id = it.Id, reason = "Khong xac dinh duoc diem dau leader / doi tuong duoc gan." });
                            continue;
                        }

                        TSD.RectangleBoundingBox box = SafeBox(m);
                        if (box != null)
                        {
                            it.Left = box.LowerLeft.X; it.Right = box.UpperRight.X;
                            it.Bottom = box.LowerLeft.Y; it.Top = box.UpperRight.Y;
                        }
                        else
                        {
                            // Uoc luong: tag ~ 20 x 6 mm giay, diem dat o giua.
                            it.Left = it.Insertion.X - 10 * scale; it.Right = it.Insertion.X + 10 * scale;
                            it.Bottom = it.Insertion.Y - 3 * scale; it.Top = it.Insertion.Y + 3 * scale;
                        }
                        items.Add(it);
                    }

                    if (items.Count == 0)
                    {
                        results.Add(new { view = v.Name, arranged = 0, skipped = skipped });
                        continue;
                    }

                    // Phia dat cot
                    string s = (side ?? "right").Trim().ToLowerInvariant();
                    if (s == "auto")
                    {
                        double meanAnchor = items.Average(i => i.Anchor.X);
                        double meanText = items.Average(i => (i.Left + i.Right) / 2.0);
                        s = meanText >= meanAnchor ? "right" : "left";
                    }
                    if (s != "right" && s != "left")
                        throw new ArgumentException("side phai la 'right', 'left' hoac 'auto'.");
                    bool right = s == "right";

                    // Dau mui ten -> dau thanh thep ve phia cot tag
                    if (leaderAtBarEnd)
                    {
                        foreach (LayoutItem it in items)
                        {
                            TSG.Point end = BarEndNear(model, it.Mark, v, it.Anchor, right);
                            if (end == null) continue;
                            if (Math.Abs(end.X - it.Anchor.X) > 0.05 || Math.Abs(end.Y - it.Anchor.Y) > 0.05)
                            {
                                it.Anchor = end;
                                it.MoveLeader = true;
                            }
                        }
                    }

                    double edgeX = columnX ?? (right
                        ? items.Max(i => i.Anchor.X) + offsetMm * scale
                        : items.Min(i => i.Anchor.X) - offsetMm * scale);

                    // Phuong dung: moi tag muon co tam o cao do dau leader; gian ra neu chong len nhau.
                    double gap = gapMm * scale;
                    var ordered = items.OrderByDescending(i => i.Anchor.Y).ThenBy(i => i.Id).ToList();
                    double[] centers = straight
                        ? ordered.Select(i => i.Anchor.Y).ToArray()
                        : SpreadVertically(
                            ordered.Select(i => i.Anchor.Y).ToArray(),
                            ordered.Select(i => (i.Top - i.Bottom) + gap).ToArray());

                    var overlaps = new List<object>();
                    for (int k = 0; k + 1 < ordered.Count; k++)
                    {
                        double need = ((ordered[k].Top - ordered[k].Bottom) + (ordered[k + 1].Top - ordered[k + 1].Bottom)) / 2.0;
                        double have = centers[k] - centers[k + 1];
                        if (have < need - 0.05)
                            overlaps.Add(new
                            {
                                upper = ordered[k].Id,
                                lower = ordered[k + 1].Id,
                                spacing = Math.Round(have, 1),
                                box_height_needed = Math.Round(need, 1),
                                overlap_paper_mm = Math.Round((need - have) / scale, 2)
                            });
                    }

                    var planned = new List<object>();
                    for (int k = 0; k < ordered.Count; k++)
                    {
                        LayoutItem it = ordered[k];
                        double dxLeft = it.Insertion.X - it.Left;   // insertion so voi mep trai chu
                        double dxRight = it.Right - it.Insertion.X; // mep phai so voi insertion
                        double dyCenter = it.Insertion.Y - (it.Top + it.Bottom) / 2.0;

                        double newX = right ? edgeX + dxLeft : edgeX - dxRight;
                        double newY = centers[k] + dyCenter;
                        var target = new TSG.Point(newX, newY, 0);

                        bool ok = true;
                        string err = null;
                        if (!dryRun)
                        {
                            try
                            {
                                if (it.ConvertToLeader || it.MoveLeader) it.Mark.Placing = new TSD.LeaderLinePlacing(it.Anchor);
                                it.Mark.InsertionPoint = target;
                                ok = it.Mark.Modify();
                                if (!ok) err = "Modify() tra ve false";
                            }
                            catch (Exception ex) { ok = false; err = ex.Message; }
                            if (ok) modified++; else failed++;
                        }

                        planned.Add(new
                        {
                            order = k + 1,
                            mark_id = it.Id,
                            anchor = Pt(it.Anchor),
                            leader_moved = it.MoveLeader,
                            from = Pt(it.Insertion),
                            to = Pt(target),
                            converted_to_leader = it.ConvertToLeader,
                            ok = dryRun ? (bool?)null : ok,
                            error = err
                        });
                    }

                    results.Add(new
                    {
                        view = v.Name,
                        view_index = views.FindIndex(x => x.GetIdentifier().ID == v.GetIdentifier().ID),
                        scale = scale,
                        side = s,
                        column_edge_x = Math.Round(edgeX, 1),
                        arranged = ordered.Count,
                        straight = straight,
                        overlaps = overlaps,
                        marks = planned,
                        skipped = skipped
                    });
                }

                if (!dryRun && modified > 0) drawing.CommitChanges("Claude: arrange_marks_column");

                return new
                {
                    drawing = drawing.Name,
                    dry_run = dryRun,
                    modified = modified,
                    failed = failed,
                    views = results
                };
            });
        }

        [McpServerTool(Name = "arrange_marks_row", Destructive = false)]
        [Description(
            "Xoay cac mark (tag) dang chon (mac dinh 90 do: chu doc tu duoi len) va xep thanh MOT HANG NGANG phia duoi (hoac tren) hang thanh thep, " +
            "mui ten thang dung: tam tag dat dung X cua dau mui ten. Mep xa cua cac tag (day neu 'below') thang hang, giong kieu tag doc trong mat cat. " +
            "Mac dinh lay mark DANG CHON; hoac truyen view + markIds. MAC DINH dryRun=true. Thay doi qua API khong Ctrl+Z duoc.")]
        public static string ArrangeMarksRow(
            [Description("'below' (mac dinh) hoac 'above'.")] string side = "below",
            [Description("Goc xoay tag (do). 90 = chu doc doc tu duoi len. Dat RotationAngle cua mark. null = giu goc hien tai.")] double? angle = 90,
            [Description("Khoang cach tu dau mui ten gan nhat toi mep gan cua hang tag, mm tren giay.")] double offsetMm = 11,
            [Description("Tuy chon: Y cua mep xa cua hang tag (day hang neu 'below', dinh hang neu 'above'), toa do view. Neu co thi bo qua offsetMm.")] double? farEdgeY = null,
            [Description("true (mac dinh) = mui ten thang dung, tam tag dung X dau mui ten (tag sat nhau bao trong 'overlaps'). false = gian tag theo phuong ngang neu chong.")] bool straight = true,
            [Description("Khe ho toi thieu giua hai tag theo phuong ngang khi straight=false, mm tren giay.")] double gapMm = 1.5,
            [Description("Tuy chon: chi xep cac mark nay (can kem view).")] int[] markIds = null,
            [Description("Ten view hoac '#index' khi dung markIds.")] string view = null,
            [Description("true = chi xem truoc.")] bool dryRun = true)
        {
            return Run(delegate
            {
                TSD.Drawing drawing = ActiveDrawing();
                var model = new TSM.Model();
                List<TSD.View> views = AllViews(drawing);
                string s = (side ?? "below").Trim().ToLowerInvariant();
                if (s != "below" && s != "above") throw new ArgumentException("side phai la 'below' hoac 'above'.");
                bool below = s == "below";

                var groups = CollectMarkGroups(drawing, views, markIds, view);
                var results = new List<object>();
                int modified = 0, failed = 0;

                foreach (var grp in groups)
                {
                    TSD.View v = grp.Key;
                    double scale = v.Attributes.Scale > 0 ? v.Attributes.Scale : 1;
                    var items = new List<LayoutItem>();
                    var skipped = new List<object>();

                    foreach (TSD.Mark m in grp.Value)
                    {
                        var it = new LayoutItem { Mark = m, Id = m.GetIdentifier().ID, Insertion = m.InsertionPoint };
                        it.Anchor = LeaderStart(m);
                        if (it.Anchor == null)
                        {
                            it.Anchor = AnchorFromRelated(model, m, v);
                            it.ConvertToLeader = it.Anchor != null;
                        }
                        if (it.Anchor == null)
                        {
                            skipped.Add(new { mark_id = it.Id, reason = "Khong xac dinh duoc diem dau mui ten." });
                            continue;
                        }

                        // Kich thuoc tag sau khi xoay: tu khung bao hien tai, doi cho W/H neu goc doi 90/270.
                        TSD.RectangleBoundingBox box = SafeBox(m);
                        double w = box != null ? box.Width : 20 * scale;
                        double h = box != null ? box.Height : 6 * scale;
                        double cur = m.Attributes.Angle;
                        double target = angle ?? cur;
                        if (QuarterTurnsOdd(cur, target)) { double t = w; w = h; h = t; }
                        it.Left = -w / 2; it.Right = w / 2; it.Bottom = -h / 2; it.Top = h / 2; // so voi tam
                        items.Add(it);
                    }

                    if (items.Count == 0) { results.Add(new { view = v.Name, arranged = 0, skipped = skipped }); continue; }

                    double maxH = items.Max(i => i.Top - i.Bottom);
                    double far = farEdgeY ?? (below
                        ? items.Min(i => i.Anchor.Y) - offsetMm * scale - maxH
                        : items.Max(i => i.Anchor.Y) + offsetMm * scale + maxH);

                    var ordered = items.OrderBy(i => i.Anchor.X).ThenBy(i => i.Id).ToList();
                    double gap = gapMm * scale;
                    double[] centersX;
                    if (straight) centersX = ordered.Select(i => i.Anchor.X).ToArray();
                    else
                    {
                        // Dung lai thuat toan xep doc: X tang dan <=> -X giam dan
                        double[] neg = SpreadVertically(
                            ordered.Select(i => -i.Anchor.X).ToArray(),
                            ordered.Select(i => (i.Right - i.Left) + gap).ToArray());
                        centersX = neg.Select(x => -x).ToArray();
                    }

                    var overlaps = new List<object>();
                    for (int k = 0; k + 1 < ordered.Count; k++)
                    {
                        double need = ((ordered[k].Right - ordered[k].Left) + (ordered[k + 1].Right - ordered[k + 1].Left)) / 2.0;
                        double have = centersX[k + 1] - centersX[k];
                        if (have < need - 0.05)
                            overlaps.Add(new { left = ordered[k].Id, right = ordered[k + 1].Id, spacing = Math.Round(have, 1),
                                               width_needed = Math.Round(need, 1), overlap_paper_mm = Math.Round((need - have) / scale, 2) });
                    }

                    var planned = new List<object>();
                    for (int k = 0; k < ordered.Count; k++)
                    {
                        LayoutItem it = ordered[k];
                        double hk = it.Top - it.Bottom;
                        // Tam tag; diem dat cua mark la tam khung bao.
                        double cy = below ? far + hk / 2 : far - hk / 2;
                        var targetPt = new TSG.Point(centersX[k], cy, 0);

                        bool ok = true; string err = null;
                        if (!dryRun)
                        {
                            try
                            {
                                // Angle chi doc (Tekla tu tinh); RotationAngle la goc xoay nguoi dung dat.
                                if (angle.HasValue) it.Mark.Attributes.RotationAngle = angle.Value;
                                if (it.ConvertToLeader) it.Mark.Placing = new TSD.LeaderLinePlacing(it.Anchor);
                                it.Mark.InsertionPoint = targetPt;
                                ok = it.Mark.Modify();
                                if (!ok) err = "Modify() tra ve false";

                                // Tekla co the dat lai diem dat sau khi xoay: can lai theo khung bao thuc te.
                                if (ok)
                                {
                                    TSD.RectangleBoundingBox nb = SafeBox(it.Mark);
                                    if (nb != null)
                                    {
                                        double dx = centersX[k] - (nb.LowerLeft.X + nb.UpperRight.X) / 2.0;
                                        double dy = below ? far - nb.LowerLeft.Y : far - nb.UpperRight.Y;
                                        if (Math.Abs(dx) > 0.5 || Math.Abs(dy) > 0.5)
                                        {
                                            TSG.Point ip = it.Mark.InsertionPoint;
                                            it.Mark.InsertionPoint = new TSG.Point(ip.X + dx, ip.Y + dy, 0);
                                            ok = it.Mark.Modify();
                                            if (!ok) err = "Modify() lan 2 tra ve false";
                                        }
                                    }
                                }
                            }
                            catch (Exception ex) { ok = false; err = ex.Message; }
                            if (ok) modified++; else failed++;
                        }

                        planned.Add(new
                        {
                            order = k + 1,
                            mark_id = it.Id,
                            anchor = Pt(it.Anchor),
                            from = Pt(it.Insertion),
                            to = Pt(targetPt),
                            size_after = new { w = Math.Round(it.Right - it.Left, 1), h = Math.Round(hk, 1) },
                            ok = dryRun ? (bool?)null : ok,
                            error = err
                        });
                    }

                    results.Add(new
                    {
                        view = v.Name,
                        scale = scale,
                        side = s,
                        angle = angle,
                        far_edge_y = Math.Round(far, 1),
                        arranged = ordered.Count,
                        overlaps = overlaps,
                        marks = planned,
                        skipped = skipped
                    });
                }

                if (!dryRun && modified > 0) drawing.CommitChanges("Claude: arrange_marks_row");
                return new { drawing = drawing.Name, dry_run = dryRun, modified = modified, failed = failed, views = results };
            });
        }

        // =================================================================== HELPERS

        private static bool QuarterTurnsOdd(double fromDeg, double toDeg)
        {
            double d = ((toDeg - fromDeg) % 180 + 180) % 180;
            return Math.Abs(d - 90) < 1;
        }

        private static List<KeyValuePair<TSD.View, List<TSD.Mark>>> CollectMarkGroups(
            TSD.Drawing drawing, List<TSD.View> views, int[] markIds, string view)
        {
            var groups = new List<KeyValuePair<TSD.View, List<TSD.Mark>>>();
            if (markIds != null && markIds.Length > 0)
            {
                if (string.IsNullOrWhiteSpace(view)) throw new ArgumentException("Can tham so view khi truyen markIds.");
                TSD.View v = FindView(drawing, view);
                var wanted = new HashSet<int>(markIds);
                var ms = new List<TSD.Mark>();
                TSD.DrawingObjectEnumerator en = v.GetAllObjects(typeof(TSD.Mark));
                while (en.MoveNext())
                {
                    var m = en.Current as TSD.Mark;
                    if (m != null && wanted.Contains(m.GetIdentifier().ID)) ms.Add(m);
                }
                groups.Add(new KeyValuePair<TSD.View, List<TSD.Mark>>(v, ms));
                return groups;
            }
            List<TSD.Mark> selected = SelectedMarks();
            if (selected.Count == 0)
                throw new InvalidOperationException("Chua chon mark nao tren drawing. Chon cac tag trong Tekla roi goi lai, hoac truyen view + markIds.");
            foreach (var g in selected.GroupBy(m => ViewIndexOf(views, m)))
            {
                if (g.Key < 0) continue;
                groups.Add(new KeyValuePair<TSD.View, List<TSD.Mark>>(views[g.Key], g.ToList()));
            }
            return groups;
        }

        private sealed class LayoutItem
        {
            public TSD.Mark Mark;
            public int Id;
            public TSG.Point Insertion;
            public TSG.Point Anchor;
            public bool ConvertToLeader;
            public bool MoveLeader;
            public double Left, Right, Bottom, Top;
        }

        /// <summary>
        /// Xep cac nhan theo truc dung (da sap giam dan theo vi tri mong muon) sao cho khoang cach tam
        /// giua hai nhan lien tiep >= (h[i] + h[i+1]) / 2. Gop cac cum chong nhau, moi cum dat tam
        /// tai trung binh vi tri mong muon -> nhan lech it nhat so voi thanh cua no.
        /// </summary>
        private static double[] SpreadVertically(double[] desired, double[] heights)
        {
            int n = desired.Length;
            var clusters = new List<List<int>>();
            var top = new List<double>(); // y tam cua nhan dau tien (tren cung) trong cum

            for (int i = 0; i < n; i++)
            {
                clusters.Add(new List<int> { i });
                top.Add(desired[i]);

                // Gop nguoc khi cum moi chong len cum truoc
                while (clusters.Count > 1)
                {
                    int c = clusters.Count - 1;
                    List<int> prev = clusters[c - 1];
                    int prevLast = prev[prev.Count - 1];
                    double prevLastY = top[c - 1] - Span(prev, heights, prev.Count - 1);
                    double need = (heights[prevLast] + heights[clusters[c][0]]) / 2.0;
                    if (prevLastY - top[c] >= need - 1e-9) break;

                    prev.AddRange(clusters[c]);
                    clusters.RemoveAt(c);
                    top.RemoveAt(c);

                    // Dat cum gop sao cho trung binh do lech = 0
                    double sumOffset = 0;
                    for (int k = 0; k < prev.Count; k++)
                        sumOffset += desired[prev[k]] + Span(prev, heights, k);
                    top[c - 1] = sumOffset / prev.Count;
                }
            }

            var result = new double[n];
            for (int c = 0; c < clusters.Count; c++)
                for (int k = 0; k < clusters[c].Count; k++)
                    result[clusters[c][k]] = top[c] - Span(clusters[c], heights, k);
            return result;
        }

        /// <summary>Khoang cach tam tu nhan dau cum toi nhan thu k trong cum.</summary>
        private static double Span(List<int> cluster, double[] heights, int k)
        {
            double d = 0;
            for (int j = 0; j < k; j++)
                d += (heights[cluster[j]] + heights[cluster[j + 1]]) / 2.0;
            return d;
        }

        private static List<TSD.Mark> SelectedMarks()
        {
            var dh = new TSD.DrawingHandler();
            var list = new List<TSD.Mark>();
            TSD.DrawingObjectEnumerator en = dh.GetDrawingObjectSelector().GetSelected();
            while (en.MoveNext())
            {
                var m = en.Current as TSD.Mark;
                if (m != null) list.Add(m);
            }
            return list;
        }

        private static TSD.Mark FindMark(TSD.View v, int markId)
        {
            TSD.DrawingObjectEnumerator en = v.GetAllObjects(typeof(TSD.Mark));
            while (en.MoveNext())
            {
                var m = en.Current as TSD.Mark;
                if (m != null && m.GetIdentifier().ID == markId) return m;
            }
            return null;
        }

        private static int ViewIndexOf(List<TSD.View> views, TSD.DrawingObject obj)
        {
            TSD.ViewBase vb = obj.GetView();
            if (vb == null) return -1;
            int id = vb.GetIdentifier().ID;
            return views.FindIndex(x => x.GetIdentifier().ID == id);
        }

        private static TSG.Point LeaderStart(TSD.Mark m)
        {
            var lp = m.Placing as TSD.LeaderLinePlacing;
            return lp == null || lp.StartPoint == null ? null : new TSG.Point(lp.StartPoint.X, lp.StartPoint.Y, 0);
        }

        private static TSG.Point AnchorFromRelated(TSM.Model model, TSD.Mark m, TSD.View v)
        {
            try
            {
                TSD.DrawingObjectEnumerator rel = m.GetRelatedObjects();
                while (rel.MoveNext())
                {
                    var rb = rel.Current as TSD.ReinforcementBase;
                    if (rb != null) return PointOnRebarInView(model, rb, v);
                }
            }
            catch { }
            return null;
        }

        /// <summary>
        /// Tim thanh (trong rebar duoc gan mark) gan diem dau leader hien tai nhat, tra ve diem mut
        /// cua thanh do ve phia cot tag (X lon nhat neu right, nho nhat neu left), toa do view.
        /// </summary>
        private static TSG.Point BarEndNear(TSM.Model model, TSD.Mark m, TSD.View v, TSG.Point anchor, bool right)
        {
            try
            {
                TSD.DrawingObjectEnumerator rel = m.GetRelatedObjects();
                while (rel.MoveNext())
                {
                    var rb = rel.Current as TSD.ReinforcementBase;
                    if (rb == null) continue;
                    var reinf = model.SelectModelObject(rb.ModelIdentifier) as TSM.Reinforcement;
                    if (reinf == null) return null;

                    TSG.Matrix toGlobal = model.GetWorkPlaneHandler().GetCurrentTransformationPlane().TransformationMatrixToGlobal;
                    TSG.Matrix toView = TSG.MatrixFactory.ToCoordinateSystem(v.DisplayCoordinateSystem);

                    TSG.Point best = null;
                    double bestDist = double.MaxValue;
                    foreach (object g in reinf.GetRebarGeometries(false))
                    {
                        var geo = g as TSM.RebarGeometry;
                        if (geo == null || geo.Shape == null || geo.Shape.Points == null || geo.Shape.Points.Count == 0) continue;

                        var pts = new List<TSG.Point>();
                        foreach (object o in geo.Shape.Points)
                        {
                            TSG.Point q = toView.Transform(toGlobal.Transform((TSG.Point)o));
                            pts.Add(new TSG.Point(q.X, q.Y, 0));
                        }

                        double d = double.MaxValue;
                        if (pts.Count == 1) d = Dist2D(anchor, pts[0]);
                        for (int i = 0; i + 1 < pts.Count; i++)
                            d = Math.Min(d, DistToSegment2D(anchor, pts[i], pts[i + 1]));

                        if (d < bestDist)
                        {
                            bestDist = d;
                            best = right ? pts.OrderByDescending(p => p.X).First() : pts.OrderBy(p => p.X).First();
                        }
                    }
                    return best;
                }
            }
            catch { }
            return null;
        }

        private static double Dist2D(TSG.Point a, TSG.Point b)
        {
            double dx = a.X - b.X, dy = a.Y - b.Y;
            return Math.Sqrt(dx * dx + dy * dy);
        }

        private static double DistToSegment2D(TSG.Point p, TSG.Point a, TSG.Point b)
        {
            double vx = b.X - a.X, vy = b.Y - a.Y;
            double len2 = vx * vx + vy * vy;
            if (len2 < 1e-9) return Dist2D(p, a);
            double t = Math.Max(0, Math.Min(1, ((p.X - a.X) * vx + (p.Y - a.Y) * vy) / len2));
            return Dist2D(p, new TSG.Point(a.X + t * vx, a.Y + t * vy, 0));
        }

        private static TSD.RectangleBoundingBox SafeBox(TSD.Mark m)
        {
            try
            {
                TSD.RectangleBoundingBox b = m.GetAxisAlignedBoundingBox();
                if (b != null && b.Width > 0 && b.Height > 0) return b;
            }
            catch { }
            return null;
        }

        private static object Pt(TSG.Point p)
        {
            return p == null ? null : (object)new { x = Math.Round(p.X, 1), y = Math.Round(p.Y, 1) };
        }

        private static object DescribeMarkForLayout(TSM.Model model, TSD.Mark m, List<TSD.View> views)
        {
            int vi = ViewIndexOf(views, m);
            var elements = new List<string>();
            try
            {
                foreach (object el in m.Attributes.Content) elements.Add(DescribeElement(el));
            }
            catch { }

            long relatedId = 0;
            string relatedType = null;
            int seqNo = 0;
            try
            {
                TSD.DrawingObjectEnumerator rel = m.GetRelatedObjects();
                while (rel.MoveNext())
                {
                    var mo = rel.Current as TSD.ModelObject;
                    if (mo == null) continue;
                    relatedId = mo.ModelIdentifier.ID;
                    relatedType = mo.GetType().Name;
                    var rb = mo as TSD.ReinforcementBase;
                    if (rb != null) seqNo = DescribeRebar(model, rb).SeqNo;
                    break;
                }
            }
            catch { }

            TSD.RectangleBoundingBox box = SafeBox(m);
            return new
            {
                mark_id = m.GetIdentifier().ID,
                view_index = vi,
                view = vi >= 0 ? views[vi].Name : null,
                placing = m.Placing == null ? null : m.Placing.GetType().Name,
                insertion_point = Pt(m.InsertionPoint),
                leader_start = Pt(LeaderStart(m)),
                bbox = box == null ? null : (object)new
                {
                    min = Pt(box.LowerLeft),
                    max = Pt(box.UpperRight),
                    width = Math.Round(box.Width, 1),
                    height = Math.Round(box.Height, 1)
                },
                related_model_id = relatedId,
                related_type = relatedType,
                rebar_seq_no = seqNo,
                elements = elements
            };
        }
    }
}
