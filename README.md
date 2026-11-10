# TeklaClaudeMcp

MCP server (stdio) cho **Tekla Structures 2020 SP14**, dùng với Claude để đọc/sửa model và drawing.
.NET Framework 4.8, x64.

## Tool

| Nhóm | Tool | Ghi vào Tekla? |
|---|---|---|
| Model | `get_model_info`, `get_selected_objects`, `get_object`, `find_objects`, `list_rebars`, `get_report_properties`, `list_drawings` | không |
| Model | `select_objects` | chỉ đổi lựa chọn |
| Model | `create_column` | có |
| Model | `rebar_numbering_preview` / `rebar_numbering_apply` | preview không / apply có |
| Drawing | `annotate_active_drawing` | có, cần `confirm=true` |
| Drawing | `drawing_views`, `view_rebars`, `view_marks`, `get_selected_drawing_marks` | không |
| Drawing | `add_rebar_mark`, `move_drawing_mark` | có, mặc định `dryRun=true` |
| Drawing | `delete_drawing_mark` | có, cần `confirm=true` |
| Drawing | `arrange_marks_column` | xếp tag thành cột; `leaderAtBarEnd`, `straight`; mặc định `dryRun=true` |
| Drawing | `arrange_marks_row` | xoay tag 90°, xếp hàng ngang, mũi tên thẳng đứng; mặc định `dryRun=true` |
| Drawing | `drawing_bbs` | không. Bảng thống kê thép (BBS) của cast unit, tính lại từ model theo công thức template `BBS_Auto_5Col`; kèm tổng theo đường kính và cảnh báo Mark trùng/chưa đánh số |

Thay đổi qua Tekla Open API không Ctrl+Z được.

## Script

| Script | Việc làm |
|---|---|
| `scripts/place_rebar_marks.ps1` | Lên reinforcement mark với file properties chọn sẵn ngay từ đầu (vd `...Group to one point with Spacing` cho group 2–3 thanh, kiểu leader "Leader lines to one point"). Đặt tag giữa group trong cột tag, mũi tên về đầu thanh, tùy chọn ghi spacing cố định. `-Angle 90` xoay tag, `-ArrowY` cho thanh thấy là chấm trong mặt cắt (mũi tên vào điểm (x thanh, ArrowY)). Chạy thử mặc định; thêm `-Apply` để ghi. |
| `scripts/add_rebar_dim_marks.ps1` | Tạo rebar dimension mark cho các rebar group, không cần click: nạp `rebar_dim_dial` (mặc định `WH_ArialNarr_2mm_Trans_Rebar Dim_no pic`), chọn thanh, gọi `acmd_create_marks_selected` / `RebarNewDimMark`. Lần đầu Tekla có thể hỏi "Pick position" một lần. |
| `scripts/set_dim_line_y.ps1` | Dời đường dim nằm ngang (tìm theo khoảng x) tới y mong muốn, lặp gán–đọc lại cho tới khi đúng. Vd `-Spec "240,1840,3400"`. |

Ví dụ:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\place_rebar_marks.ps1 -ViewName N -ViewType DetailView -RebarIds 358097497 -Kind group -TagX -966.6 -SpacingText 200 -Apply
```

Ghi chú về `place_rebar_marks.ps1`:
- API Tekla 2020 không đặt được kiểu leader của rebar group mark, và `MarkAttributes(obj, file)` không nạp được file `.rm`.
- Vì vậy script chạy một macro tạm trong `...\macros\drawings`. Macro mở `rebar_mark_dial`, nạp file (`gr_rebar_mark_get_menu` + `gr_rebar_get`) rồi Modify các mark đang chọn. Sau đó script đóng dialog và xóa macro.
- Khi duyệt `Attributes.Content` trong PowerShell phải dùng `GetEnumerator()`. Nếu dùng `foreach` thì khung oval (`ContainerElement`) bị mở ra và mất.

## Build

DLL Tekla (`Tekla.Structures*.dll`) có bản quyền Trimble nên **không có trong repo**. Cần một thư mục chứa
DLL Tekla 2020 và các DLL runtime MCP (ModelContextProtocol, Microsoft.Extensions.*, System.Text.Json, Newtonsoft.Json...);
thư mục server đã cài (`TeklaClaude2020`) có đủ.

Không cần Visual Studio:

```powershell
powershell -ExecutionPolicy Bypass -File build_roslyn.ps1 -LibDir D:\TeklaClaude\TeklaMcp\TeklaClaude2020
# build + thay exe đang chạy (exe cũ được đổi tên .old-<giờ>.exe):
powershell -ExecutionPolicy Bypass -File build_roslyn.ps1 -Deploy
```

Có Visual Studio 2019/2022: `TeklaClaudeMcp\build.bat`.

## Đăng ký với Claude

```json
"mcpServers": {
  "tekla-2020": {
    "command": "D:\\TeklaClaude\\TeklaMcp\\TeklaClaude2020\\TeklaClaudeMcp.exe",
    "env": { "SESSIONNAME": "Console" }
  }
}
```

Tekla 2020 phải đang mở một model. Sau khi thay exe, khởi động lại server (hoặc mở phiên Claude mới) để nạp tool mới.
