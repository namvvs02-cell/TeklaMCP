using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using ModelContextProtocol.Server;
using TS = Tekla.Structures;
using TSM = Tekla.Structures.Model;

namespace TeklaClaudeMcp
{
    // =========================================================================================
    //  Du lieu thuan (khong phu thuoc Tekla) - de kiem tra thuat toan doc lap.
    // =========================================================================================

    public sealed class RebarRecord
    {
        public int Id;
        public string Ppvc;          // ten assembly cap cao nhat; "(no assembly)" neu khong co
        public int PpvcId;           // id assembly cap cao nhat; 0 neu khong co
        public string Name;
        public string Size;
        public string Grade;
        public string Shape;
        public double Length;
        public double LengthMin;
        public double LengthMax;
        public string Dimensions;    // "A=650 B=2890"
        public string UserField4;    // "" neu trong
        public string Host;
        public int? Seq;             // REBAR_SEQ_NO hien tai
        public bool InScope;

        public string TypeKey
        {
            get
            {
                return string.Join("|", new[]
                {
                    Size ?? "", Grade ?? "", Shape ?? "",
                    Length.ToString("0.#", CultureInfo.InvariantCulture),
                    Dimensions ?? "", UserField4 ?? ""
                });
            }
        }

        public string Describe()
        {
            return Grade + Size + " " + Shape + " L=" + Length.ToString("0.#", CultureInfo.InvariantCulture) +
                   " (" + Name + ", id " + Id + ")";
        }
    }

    public sealed class NumberingOptions
    {
        public bool ReassignAll;
        public int StartingNumber = 1;
        public List<string> UserField4Order = new List<string> { "", "550MPA", "OTHER" };
    }

    public sealed class BarTypeResult
    {
        public string Ppvc;
        public string Number;        // so moi (hoac danh sach neu giu nhieu so)
        public string OldNumber;
        public string Status;        // kept | joined | new | renumbered (conflict)
        public RebarRecord Sample;
        public string Host;
        public int RebarCount;
        public int RebarsChanged;
        public List<int> RebarIds = new List<int>();
    }

    public sealed class NumberingPlan
    {
        public string PlanId;
        public int Rebars;
        public int BarTypes;
        public Dictionary<int, int> Changes = new Dictionary<int, int>();     // rebar id -> so moi
        public List<object> Conflicts = new List<object>();
        public List<string> Warnings = new List<string>();
        public List<BarTypeResult> Types = new List<BarTypeResult>();
    }

    /// <summary>
    /// Quy tac (giu theo server cu):
    ///  - Mot so thuoc ve mot loai thanh trong moi PPVC (assembly cap cao nhat): SIZE, GRADE, SHAPE, LENGTH,
    ///    kich thuoc uon va USER_FIELD_4, so sanh chinh xac.
    ///  - So dang co duoc giu; chi sua so dung chung cho nhieu loai thanh: loai co rebar cu nhat (ID nho nhat) giu so.
    ///  - Rebar chua co so: nhap vao so cua loai thanh cua no, hoac nhan so moi sau so lon nhat cua PPVC.
    ///  - So moi duoc cap theo thu tu USER_FIELD_4 ('', 550MPA, OTHER), roi size, shape, length.
    /// </summary>
    public static class NumberingEngine
    {
        public static NumberingPlan Plan(List<RebarRecord> all, NumberingOptions opt)
        {
            var plan = new NumberingPlan();
            plan.Rebars = all.Count(r => r.InScope);

            foreach (var ppvcGroup in all.GroupBy(r => r.PpvcId == 0 ? "0:" + r.Id : r.PpvcId.ToString(CultureInfo.InvariantCulture)))
            {
                PlanPpvc(ppvcGroup.ToList(), opt, plan);
            }

            int loose = all.Count(r => r.InScope && r.PpvcId == 0);
            if (loose > 0) plan.Warnings.Add(loose + " rebar(s) without a host assembly are numbered on their own.");

            plan.BarTypes = plan.Types.Count;
            return plan;
        }

        private static void PlanPpvc(List<RebarRecord> recs, NumberingOptions opt, NumberingPlan plan)
        {
            if (!recs.Any(r => r.InScope)) return;
            string ppvc = recs[0].Ppvc;

            // So hien tai co hieu luc: rebar ngoai pham vi luon giu; rebar trong pham vi giu tru khi reassignAll.
            Func<RebarRecord, int?> current = r => (r.InScope && opt.ReassignAll) ? null : r.Seq;

            // Loai thanh -> rebar
            var types = recs.GroupBy(r => r.TypeKey).ToDictionary(g => g.Key, g => g.OrderBy(r => r.Id).ToList());

            // So -> cac loai thanh dang dung
            var numberUsers = new Dictionary<int, HashSet<string>>();
            foreach (var r in recs)
            {
                int? n = current(r);
                if (!n.HasValue) continue;
                HashSet<string> set;
                if (!numberUsers.TryGetValue(n.Value, out set)) numberUsers[n.Value] = set = new HashSet<string>();
                set.Add(r.TypeKey);
            }

            // Chu so huu cua moi so: loai thanh co rebar ID nho nhat dang mang so do.
            var owner = new Dictionary<int, string>();
            foreach (var kv in numberUsers)
            {
                int n = kv.Key;
                string best = null; int bestId = int.MaxValue;
                foreach (var key in kv.Value)
                {
                    int minId = types[key].Where(r => current(r) == n).Min(r => r.Id);
                    if (minId < bestId) { bestId = minId; best = key; }
                }
                owner[n] = best;

                if (kv.Value.Count > 1)
                {
                    var moved = kv.Value.Where(k => k != best).ToList();
                    var keptSample = types[best].First(r => current(r) == n);
                    var movable = moved.Where(k => types[k].Any(r => r.InScope && current(r) == n)).ToList();
                    var stuck = moved.Where(k => !types[k].Any(r => r.InScope && current(r) == n)).ToList();

                    if (movable.Count > 0)
                    {
                        plan.Conflicts.Add(new
                        {
                            assembly = ppvc,
                            number = n,
                            kept_by = Short(keptSample),
                            moved = movable.Select(k => Short(types[k].First(r => current(r) == n))).ToList()
                        });
                    }
                    foreach (var k in stuck)
                    {
                        plan.Warnings.Add(ppvc + ": number " + n + " stays shared by " +
                                          Short(types[k].First(r => current(r) == n)) +
                                          " on rebars outside the numbering scope.");
                    }
                }
            }

            int next = recs.Select(current).Where(n => n.HasValue).Select(n => n.Value).DefaultIfEmpty(opt.StartingNumber - 1).Max() + 1;
            if (next < opt.StartingNumber) next = opt.StartingNumber;

            // Thu tu xu ly loai thanh: USER_FIELD_4, size, shape, length.
            Func<string, int> uf4Rank = s =>
            {
                string v = (s ?? "").Trim().ToUpperInvariant();
                int idx = opt.UserField4Order.FindIndex(o => string.Equals((o ?? "").Trim(), v, StringComparison.OrdinalIgnoreCase));
                if (idx >= 0) return idx;
                int other = opt.UserField4Order.FindIndex(o => string.Equals(o, "OTHER", StringComparison.OrdinalIgnoreCase));
                return other >= 0 ? other : opt.UserField4Order.Count;
            };

            var orderedTypes = types
                .Where(kv => kv.Value.Any(r => r.InScope))
                .OrderBy(kv => uf4Rank(kv.Value[0].UserField4))
                .ThenBy(kv => SizeValue(kv.Value[0].Size))
                .ThenBy(kv => kv.Value[0].Shape, StringComparer.Ordinal)
                .ThenBy(kv => kv.Value[0].Length)
                .ToList();

            foreach (var kv in orderedTypes)
            {
                string key = kv.Key;
                List<RebarRecord> rebars = kv.Value;
                List<RebarRecord> inScope = rebars.Where(r => r.InScope).ToList();
                RebarRecord sample = inScope[0];

                // So hop le cua loai thanh: nhung so ma no la chu.
                List<int> owned = rebars.Select(current).Where(n => n.HasValue && owner[n.Value] == key)
                                        .Select(n => n.Value).Distinct().OrderBy(n => n).ToList();
                var oldNumbers = inScope.Where(r => r.Seq.HasValue).Select(r => r.Seq.Value).Distinct().OrderBy(n => n).ToList();

                int target;
                string status;
                bool hadConflict = inScope.Any(r => current(r).HasValue && owner[current(r).Value] != key);

                if (owned.Count > 0)
                {
                    target = owned[0];
                    bool anyUnnumbered = inScope.Any(r => !current(r).HasValue);
                    status = hadConflict ? "renumbered (conflict)" : (anyUnnumbered ? "joined" : "kept");
                }
                else
                {
                    target = next++;
                    status = hadConflict ? "renumbered (conflict)" : "new";
                }

                var result = new BarTypeResult
                {
                    Ppvc = ppvc,
                    Sample = sample,
                    Host = string.Join(" / ", inScope.Select(r => r.Host).Where(h => !string.IsNullOrEmpty(h)).Distinct().Take(3).ToArray()),
                    RebarCount = inScope.Count,
                    OldNumber = oldNumbers.Count == 0 ? "" : string.Join(", ", oldNumbers.Select(n => n.ToString(CultureInfo.InvariantCulture)).ToArray())
                };

                foreach (var r in inScope)
                {
                    int? cur = current(r);
                    bool keep = cur.HasValue && owner[cur.Value] == key;   // so hop le dang co -> giu nguyen
                    int final = keep ? cur.Value : target;
                    if (!r.Seq.HasValue || r.Seq.Value != final)
                    {
                        plan.Changes[r.Id] = final;
                        result.RebarsChanged++;
                    }
                    result.RebarIds.Add(r.Id);
                }

                var finalNumbers = inScope.Select(r => plan.Changes.ContainsKey(r.Id) ? plan.Changes[r.Id] : r.Seq.Value)
                                          .Distinct().OrderBy(n => n).ToList();
                result.Number = string.Join(", ", finalNumbers.Select(n => n.ToString(CultureInfo.InvariantCulture)).ToArray());
                result.Status = status;
                plan.Types.Add(result);

                if (finalNumbers.Count > 1)
                {
                    plan.Warnings.Add(ppvc + ": " + Short(sample) + " keeps several numbers (" + result.Number + ").");
                }

                foreach (var r in inScope.Where(x => x.LengthMax - x.LengthMin > 0.5))
                {
                    plan.Warnings.Add(ppvc + ": rebar " + r.Id + " (" + r.Name + ") has bars of different lengths (" +
                                      r.LengthMin.ToString("0", CultureInfo.InvariantCulture) + "-" +
                                      r.LengthMax.ToString("0", CultureInfo.InvariantCulture) + " mm) under one number.");
                }
            }
        }

        private static double SizeValue(string size)
        {
            double d;
            return double.TryParse(size, NumberStyles.Float, CultureInfo.InvariantCulture, out d) ? d : 9999;
        }

        public static string Short(RebarRecord r)
        {
            return r.Grade + r.Size + " " + r.Shape + " L=" + r.Length.ToString("0.#", CultureInfo.InvariantCulture) +
                   " (" + r.Name + ", id " + r.Id + ")";
        }
    }

    // =========================================================================================
    //  Tool MCP
    // =========================================================================================

    [McpServerToolType]
    public static class RebarNumberingTools
    {
        private static readonly ConcurrentDictionary<string, NumberingPlan> Plans = new ConcurrentDictionary<string, NumberingPlan>();

        [McpServerTool(Name = "rebar_numbering_preview", ReadOnly = true)]
        [Description("Xem truoc danh so Rebar Manager (REBAR_SEQ_NO), KHONG ghi vao Tekla. Mot so thuoc ve mot loai thanh trong moi PPVC (assembly cap cao nhat): " +
                     "SIZE, GRADE, SHAPE, LENGTH, kich thuoc uon va USER_FIELD_4, so sanh chinh xac. So dang co duoc giu; chi sua so dung chung cho nhieu loai thanh " +
                     "(loai co rebar cu nhat giu so). Rebar chua co so nhap vao so cua loai thanh cua no hoac nhan so moi sau so lon nhat cua PPVC. " +
                     "Tra ve conflicts, changes, warnings va plan_id de dua vao rebar_numbering_apply.")]
        public static string Preview(
            [Description("Pham vi: 'selection' (rebar dang chon + rebar cua part/assembly dang chon), 'part' (partId), 'assembly' (assemblyId) hoac 'model'.")] string scope = "selection",
            [Description("Assembly ID khi scope='assembly'.")] int? assemblyId = null,
            [Description("Part ID khi scope='part'.")] int? partId = null,
            [Description("true = bo qua so hien co cua rebar trong pham vi (rebar khac cua PPVC giu so).")] bool reassignAll = false,
            [Description("So nho nhat cho PPVC chua co so nao.")] int startingNumber = 1,
            [Description("Thu tu USER_FIELD_4 khi cap so moi; chuoi rong = trong. Mac dinh: '', 550MPA, OTHER.")] string[] userField4Order = null,
            [Description("So loai thanh toi da liet ke trong ket qua (van danh so tat ca).")] int maxGroups = 200)
        {
            return Util.Run(delegate
            {
                var model = Util.RequireModel();

                List<TSM.Reinforcement> scoped;
                switch ((scope ?? "selection").Trim().ToLowerInvariant())
                {
                    case "selection": scoped = Util.RebarsOfSelection(); break;
                    case "assembly":
                        if (!assemblyId.HasValue) throw new ArgumentException("assemblyId is required when scope is 'assembly'.");
                        scoped = Util.RebarsOfAssembly(Util.Require<TSM.Assembly>(model, assemblyId.Value, "assembly"));
                        break;
                    case "part":
                        if (!partId.HasValue) throw new ArgumentException("partId is required when scope is 'part'.");
                        scoped = Util.RebarsOfPart(Util.Require<TSM.Part>(model, partId.Value, "part"));
                        break;
                    case "model": scoped = Util.RebarsOfModel(model); break;
                    default: throw new ArgumentException("Unknown scope '" + scope + "'. Use selection, part, assembly or model.");
                }
                if (scoped.Count == 0)
                    throw new ArgumentException("No rebars found for scope '" + scope + "'. Select rebars or parts in Tekla, or pass another scope.");

                // Thu thap: rebar trong pham vi + moi rebar khac cua cung PPVC (de biet so dang dung).
                var records = new Dictionary<int, RebarRecord>();
                var ppvcDone = new HashSet<int>();
                foreach (TSM.Reinforcement r in scoped)
                {
                    TSM.Assembly top = Util.TopAssembly(r);
                    records[r.Identifier.ID] = Read(r, top, true);
                    if (top != null && ppvcDone.Add(top.Identifier.ID))
                    {
                        foreach (TSM.Reinforcement other in Util.RebarsOfAssembly(top))
                        {
                            if (!records.ContainsKey(other.Identifier.ID))
                                records[other.Identifier.ID] = Read(other, top, false);
                        }
                    }
                }
                // Rebar da them nhu "ngoai pham vi" nhung thuc ra trong pham vi
                var scopedIds = new HashSet<int>(scoped.Select(r => r.Identifier.ID));
                foreach (var rec in records.Values) rec.InScope = scopedIds.Contains(rec.Id);

                var opt = new NumberingOptions { ReassignAll = reassignAll, StartingNumber = Math.Max(1, startingNumber) };
                if (userField4Order != null && userField4Order.Length > 0) opt.UserField4Order = userField4Order.ToList();

                NumberingPlan plan = NumberingEngine.Plan(records.Values.ToList(), opt);
                plan.PlanId = Guid.NewGuid().ToString("N").Substring(0, 8);
                Plans[plan.PlanId] = plan;

                return new
                {
                    plan_id = plan.PlanId,
                    rebars = plan.Rebars,
                    bar_types = plan.BarTypes,
                    rebars_to_write = plan.Changes.Count,
                    conflicts = plan.Conflicts,
                    warnings = plan.Warnings,
                    bar_types_listed = plan.Types.Take(maxGroups).Select(t => new
                    {
                        assembly = t.Ppvc,
                        number = t.Number,
                        old_number = t.OldNumber,
                        status = t.Status,
                        size = t.Sample.Size,
                        grade = t.Sample.Grade,
                        shape = t.Sample.Shape,
                        length_mm = t.Sample.Length,
                        dimensions = t.Sample.Dimensions,
                        user_field_4 = t.Sample.UserField4,
                        name = t.Sample.Name,
                        host = t.Host,
                        rebar_count = t.RebarCount,
                        rebars_changed = t.RebarsChanged,
                        rebar_ids = t.RebarIds.Select(i => i.ToString(CultureInfo.InvariantCulture)).ToList()
                    }).ToList()
                };
            });
        }

        [McpServerTool(Name = "rebar_numbering_apply", Destructive = true)]
        [Description("Ghi so REBAR_SEQ_NO cua mot plan tu rebar_numbering_preview vao Tekla va commit. Chi goi sau khi nguoi dung da duyet preview.")]
        public static string Apply(
            [Description("plan_id tra ve tu rebar_numbering_preview.")] string planId)
        {
            return Util.Run(delegate
            {
                NumberingPlan plan;
                if (string.IsNullOrEmpty(planId) || !Plans.TryGetValue(planId, out plan))
                    throw new ArgumentException("Unknown plan_id '" + planId + "'. Run rebar_numbering_preview again.");

                var model = Util.RequireModel();
                int written = 0;
                var errors = new List<string>();
                foreach (var kv in plan.Changes)
                {
                    TSM.ModelObject mo = model.SelectModelObject(new TS.Identifier(kv.Key));
                    if (mo == null) { errors.Add("rebar " + kv.Key + ": not found"); continue; }

                    bool ok = mo.SetUserProperty("REBAR_SEQ_NO", kv.Value);
                    if (!ok) ok = mo.SetUserProperty("REBAR_SEQ_NO", kv.Value.ToString(CultureInfo.InvariantCulture));
                    if (!ok) { errors.Add("rebar " + kv.Key + ": SetUserProperty failed"); continue; }

                    int? check = Util.SeqNo(mo);
                    if (check != kv.Value) { errors.Add("rebar " + kv.Key + ": doc lai duoc " + (check.HasValue ? check.Value.ToString() : "rong") + " thay vi " + kv.Value); continue; }
                    written++;
                }
                if (written > 0) model.CommitChanges("Claude: rebar_numbering_apply " + planId);
                NumberingPlan removed;
                Plans.TryRemove(planId, out removed);
                return new { plan_id = planId, rebars_written = written, errors = errors };
            });
        }

        private static RebarRecord Read(TSM.Reinforcement r, TSM.Assembly top, bool inScope)
        {
            var host = r.Father as TSM.Part;
            string uf4 = null;
            r.GetUserProperty("USER_FIELD_4", ref uf4);

            double length = Util.Dbl(r, "LENGTH") ?? 0;
            return new RebarRecord
            {
                Id = r.Identifier.ID,
                Ppvc = top != null ? top.Name : "(no assembly)",
                PpvcId = top != null ? top.Identifier.ID : 0,
                Name = r.Name,
                Size = Util.Str(r, "SIZE"),
                Grade = r.Grade,
                Shape = Util.Str(r, "SHAPE"),
                Length = Math.Round(length, 1),
                LengthMin = Util.Dbl(r, "LENGTH_MIN") ?? length,
                LengthMax = Util.Dbl(r, "LENGTH_MAX") ?? length,
                Dimensions = Dims(r),
                UserField4 = (uf4 ?? "").Trim(),
                Host = host != null ? host.Name : null,
                Seq = Util.SeqNo(r),
                InScope = inScope
            };
        }

        private static string Dims(TSM.ModelObject r)
        {
            var parts = new List<string>();
            foreach (string d in new[] { "A", "B", "C", "D", "E", "F", "G", "R" })
            {
                double? v = Util.Dbl(r, "DIM_" + d);
                if (v.HasValue && Math.Abs(v.Value) > 0.01)
                    parts.Add(d + "=" + Math.Round(v.Value, 0).ToString("0", CultureInfo.InvariantCulture));
            }
            return string.Join(" ", parts.ToArray());
        }
    }
}
