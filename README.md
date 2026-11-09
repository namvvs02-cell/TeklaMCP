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

Thay đổi qua Tekla Open API không Ctrl+Z được.

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
