# TeklaClaudeMcp 2.0 - Tekla Structures 2020 SP14 (may pc-whvn00026)

Mot MCP server duy nhat cho ca MODEL va DRAWING.
Package: `D:\TeklaClaude\TeklaMcp\TeklaClaude2020\TeklaClaudeMcp.exe`
(.NET Framework 4.8, x64, bien dich voi DLL Tekla 2020 lay tu `D:\TeklaClaude\TeklaMcp\Tekla2020`).

## Dang ky vao Claude desktop (thay toan bo khoi mcpServers)
```json
"mcpServers": {
  "tekla-2020": {
    "command": "D:\\TeklaClaude\\TeklaMcp\\TeklaClaude2020\\TeklaClaudeMcp.exe",
    "env": { "SESSIONNAME": "Console" }
  }
}
```
Thoat han Claude desktop (ca khay he thong) roi mo lai. Tekla 2020 nen mo san model.

## 21 tool
Model (giu ten nhu server cu):
| Tool | Ghi? |
|---|---|
| get_model_info | khong |
| get_selected_objects, get_object, find_objects | khong |
| list_rebars, get_report_properties | khong |
| select_objects | chi doi lua chon |
| create_column | CO (tao part, commit) |
| list_drawings | khong |
| annotate_active_drawing | CO, can confirm=true |
| rebar_numbering_preview | khong (tao plan_id) |
| rebar_numbering_apply | CO (ghi REBAR_SEQ_NO, commit) |

Drawing:
| Tool | Ghi? |
|---|---|
| drawing_views, view_rebars, view_marks | khong |
| add_rebar_mark | CO, mac dinh dryRun=true |
| delete_drawing_mark | CO, can confirm=true |
| get_selected_drawing_marks | khong (mark dang chon tren drawing) |
| move_drawing_mark | CO, mac dinh dryRun=true |
| arrange_marks_column | CO, mac dinh dryRun=true (xep tag thanh cot; leaderAtBarEnd, straight) |
| arrange_marks_row | CO, mac dinh dryRun=true (xoay tag 90 do, xep hang ngang, mui ten thang dung) |

## Luu y
- Thay doi qua API khong Ctrl+Z duoc trong Tekla.
- rebar_numbering_* duoc viet lai theo quy tac cua server cu (da kiem tra voi du lieu PPVC06_L21:
  xung dot so 29 -> 142, canh bao "7, 14, 120"). Lan dau dung that: so sanh preview truoc khi apply.
- Thu muc cu (Tekla2020, Tekla2020Dwg, Tekla2020Dwg_101) khong con can cho Claude; giu lai de du phong.

## Build lai tu ma nguon
`Source\TeklaClaudeMcp\build.bat` (Visual Studio 2019/2022 + .NET Framework 4.8 targeting pack), hoac nho Claude build.
