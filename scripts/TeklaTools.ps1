# TeklaTools: one window to run every Tekla tool Claude built, by hand, without Claude.
#  - MCP tools: talks to TeklaClaudeMcp.exe over stdio (same exe Claude uses), form built from each tool's schema.
#  - Script tools (.ps1): form built from the script's param() block, run with powershell.exe.
# Start: TeklaTools.bat in C:\TeklaClaude (or: powershell -ExecutionPolicy Bypass -STA -File TeklaTools.ps1)
# Tekla 2020 must be running with the model / drawing open.
param([string]$Root = "C:\TeklaClaude", [switch]$SelfTest, [string]$Snapshot = "")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -AssemblyName System.Web.Extensions
$json = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $json.MaxJsonLength = 100MB
$McpExe = Join-Path $Root "TeklaMcp\TeklaClaude2020\TeklaClaudeMcp.exe"
$Scripts = Join-Path $Root "TeklaMcp\Scripts"
$Skill = Join-Path $Root ".claude\skills\ppvc-rebar-numbering\scripts"

# ---------- catalogue: category -> tools (kind, name, Vietnamese label, note, writes?) ----------
$cat = [ordered]@{
 '1. Tra cứu (chỉ đọc)' = @(
  @('mcp','get_model_info','Thông tin Tekla / model / drawing đang mở','',0),
  @('mcp','list_drawings','Danh sách drawing','',0),
  @('mcp','drawing_views','Các view trong drawing đang mở','',0),
  @('mcp','view_rebars','Rebar trong một view','view: tên hoặc #index',0),
  @('mcp','view_marks','Mark (tag) trong một view','',0),
  @('mcp','get_selected_drawing_marks','Mark đang chọn trên drawing','Chọn tag trong Tekla trước',0),
  @('mcp','get_selected_objects','Đối tượng đang chọn trong model','',0),
  @('mcp','get_object','Thuộc tính một đối tượng theo ID','',0),
  @('mcp','find_objects','Tìm đối tượng model theo loại / tên','type: BEAM, REBARGROUP, ASSEMBLY...',0),
  @('mcp','get_report_properties','Đọc report property / UDA','names: cách nhau bằng dấu phẩy',0),
  @('mcp','list_rebars','Danh sách thép của part / assembly','',0),
  @('mcp','select_objects','Chọn (highlight) đối tượng theo ID','ids: cách nhau bằng dấu phẩy',0))
 '2. Tag thép (rebar mark)' = @(
  @('mcp','add_rebar_mark','Tạo tag cho rebar theo REBAR_SEQ_NO','Bỏ tick dryRun để tạo thật',1),
  @('mcp','arrange_marks_column','Xếp tag thành CỘT (leader ngang)','Không nhập markIds = các tag đang chọn',1),
  @('mcp','arrange_marks_row','Xếp tag thành HÀNG, xoay 90° (Sky terrace)','Không nhập markIds = các tag đang chọn',1),
  @('mcp','move_drawing_mark','Dời một tag tới (x, y)','',1),
  @('mcp','delete_drawing_mark','Xóa một tag','Tick confirm để xóa',1),
  @('ps1',"$Scripts\place_rebar_marks.ps1",'Đặt tag với file property chuẩn','',1))
 '3. Dim' = @(
  @('ps1',"$Scripts\add_rebar_dim_marks.ps1",'Tạo rebar dimension mark (file dim chung)','',1),
  @('ps1',"$Scripts\set_dim_line_y.ps1",'Dời đường dim ngang tới y','',1),
  @('mcp','annotate_active_drawing','Dim tổng + part mark cho mọi view','Tick confirm để chạy',1))
 '4. BBS / đối tượng 2D' = @(
  @('mcp','drawing_bbs','Bảng BBS tính từ model','',0),
  @('ps1',"$Scripts\translate_selected.ps1",'Dời / copy đối tượng đang chọn (cả cover-up)','Tick DryRun để chỉ kiểm tra. BBS: 1 dòng = 9.375, 1 bảng = 67.1',1))
 '5. Đánh số thép / 550MPa' = @(
  @('mcp','rebar_numbering_preview','Xem trước đánh số REBAR_SEQ_NO','Không ghi vào Tekla',0),
  @('mcp','rebar_numbering_apply','Ghi số theo planId của preview','Chỉ chạy sau khi đã xem preview',1),
  @('ps1',"$Skill\conn_bars.ps1",'Liệt kê CONNECTION BAR / U bar (USER_FIELD_4)','',0),
  @('ps1',"$Skill\bar_levels.ps1",'Cao độ Z từng thanh trong rebar group','',0),
  @('ps1',"$Skill\set_uf4.ps1",'Gán USER_FIELD_4 (550MPa)','',1))
 '6. Model' = @(
  ,@('mcp','create_column','Tạo cột trong model','Thay đổi model, không Ctrl+Z được',1))
}

# ---------- MCP client ----------
$script:mcp = $null; $script:mcpId = 10; $script:schemas = @{}
function Mcp-Start {
  if ($script:mcp -and -not $script:mcp.HasExited) { return }
  $psi = New-Object Diagnostics.ProcessStartInfo $McpExe
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.EnvironmentVariables["SESSIONNAME"] = "Console"
  $script:mcp = [Diagnostics.Process]::Start($psi); $script:mcp.BeginErrorReadLine()
  [void](Mcp-Req 'initialize' @{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'TeklaTools'; version = '1' } })
  $script:mcp.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
  $r = Mcp-Req 'tools/list' @{}
  foreach ($t in $r.tools) { $script:schemas[$t.name] = $t }
}
function Mcp-Req($method, $params) {
  $id = ++$script:mcpId
  $script:mcp.StandardInput.WriteLine($json.Serialize(@{ jsonrpc = '2.0'; id = $id; method = $method; params = $params }))
  while ($true) {
    $task = $script:mcp.StandardOutput.ReadLineAsync()
    while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 30 }
    $line = $task.Result; if ($null -eq $line) { throw "MCP exe stopped" }
    $m = $json.DeserializeObject($line)
    if ($m.ContainsKey('id') -and $m['id'] -eq $id) {
      if ($m.ContainsKey('error')) { throw ("MCP error: " + $m['error']['message']) }
      return [pscustomobject]$m['result'] } } }

# ---------- form helpers ----------
function TypeOf($t) { if ($t -is [array]) { ($t | ? { $_ -ne 'null' } | select -First 1) } else { $t } }
$form = New-Object Windows.Forms.Form
$form.Text = 'Tekla Tools - PPVC'; $form.Size = New-Object Drawing.Size(1100, 720); $form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$tree = New-Object Windows.Forms.TreeView; $tree.Dock = 'Left'; $tree.Width = 330; $tree.HideSelection = $false
$right = New-Object Windows.Forms.Panel; $right.Dock = 'Fill'
$title = New-Object Windows.Forms.Label; $title.Dock = 'Top'; $title.Height = 26; $title.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold); $title.Padding = '6,4,0,0'
$desc = New-Object Windows.Forms.TextBox; $desc.Dock = 'Top'; $desc.Height = 70; $desc.Multiline = $true; $desc.ReadOnly = $true; $desc.ScrollBars = 'Vertical'; $desc.BorderStyle = 'None'; $desc.BackColor = $form.BackColor
$grid = New-Object Windows.Forms.TableLayoutPanel; $grid.Dock = 'Top'; $grid.AutoSize = $true; $grid.ColumnCount = 3; $grid.Padding = '6,4,6,4'
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 150)))
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 330)))
[void]$grid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
$bar = New-Object Windows.Forms.FlowLayoutPanel; $bar.Dock = 'Top'; $bar.Height = 38; $bar.Padding = '6,4,0,0'
$run = New-Object Windows.Forms.Button; $run.Text = 'Chạy'; $run.Width = 100; $run.Height = 28; $run.Enabled = $false
$clr = New-Object Windows.Forms.Button; $clr.Text = 'Xóa kết quả'; $clr.Width = 100; $clr.Height = 28
$note = New-Object Windows.Forms.Label; $note.AutoSize = $true; $note.Padding = '10,7,0,0'; $note.ForeColor = 'DarkRed'
$bar.Controls.AddRange(@($run, $clr, $note))
$out = New-Object Windows.Forms.TextBox; $out.Dock = 'Fill'; $out.Multiline = $true; $out.ScrollBars = 'Both'; $out.WordWrap = $false; $out.ReadOnly = $true; $out.Font = New-Object Drawing.Font('Consolas', 9); $out.BackColor = 'White'
$right.Controls.AddRange(@($out, $bar, $grid, $desc, $title))
$split = New-Object Windows.Forms.Splitter; $split.Dock = 'Left'
$form.Controls.AddRange(@($right, $split, $tree))
$status = New-Object Windows.Forms.StatusStrip; $st = New-Object Windows.Forms.ToolStripStatusLabel; $st.Text = 'Chọn một tool bên trái.'; [void]$status.Items.Add($st); $form.Controls.Add($status)

foreach ($c in $cat.Keys) { $n = $tree.Nodes.Add($c + '          '); $n.NodeFont = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
  foreach ($t in $cat[$c]) { $k = $n.Nodes.Add($t[2]); $k.Tag = $t; if ($t[4]) { $k.ForeColor = 'DarkRed' } } }
$tree.ExpandAll(); $tree.Nodes[0].EnsureVisible()

$script:fields = @(); $script:cur = $null
function Add-Field($name, $type, $req, $default, $help, $enum) {
  $r = $grid.RowCount; $grid.RowCount++
  $lb = New-Object Windows.Forms.Label; $lb.Text = $name + $(if ($req) { ' *' } else { '' }); $lb.AutoSize = $true; $lb.Padding = '0,5,0,0'
  if ($type -eq 'boolean' -or $type -eq 'switch') { $ctl = New-Object Windows.Forms.CheckBox; $ctl.Checked = ($default -eq $true -or "$default" -match '^(\$true|true)$') }
  elseif ($enum) { $ctl = New-Object Windows.Forms.ComboBox; $ctl.DropDownStyle = 'DropDownList'; [void]$ctl.Items.Add(''); $enum | % { [void]$ctl.Items.Add($_) }; $ctl.SelectedIndex = 0; $ctl.Width = 320 }
  else { $ctl = New-Object Windows.Forms.TextBox; $ctl.Width = 320; if ($null -ne $default) { $ctl.Text = "$default".Trim('"', "'") } }
  $hl = New-Object Windows.Forms.Label; $hl.Text = $help; $hl.AutoSize = $true; $hl.MaximumSize = New-Object Drawing.Size(420, 0); $hl.ForeColor = 'Gray'; $hl.Padding = '0,5,0,0'
  $grid.Controls.Add($lb, 0, $r); $grid.Controls.Add($ctl, 1, $r); $grid.Controls.Add($hl, 2, $r)
  $script:fields += [pscustomobject]@{ Name = $name; Type = $type; Ctl = $ctl; Req = $req } }

$tree.add_AfterSelect({
  $t = $tree.SelectedNode.Tag; $grid.SuspendLayout(); $grid.Controls.Clear(); $grid.RowCount = 0; $script:fields = @(); $script:cur = $t
  $run.Enabled = [bool]$t; if (-not $t) { $title.Text = ''; $desc.Text = ''; $grid.ResumeLayout(); return }
  $title.Text = $t[2]; $note.Text = $(if ($t[4]) { 'Tool này SỬA bản vẽ / model: Save drawing sau khi chạy.' } else { '' })
  try {
    if ($t[0] -eq 'mcp') {
      $st.Text = 'Đang kết nối TeklaClaudeMcp.exe...'; $form.Refresh(); Mcp-Start; $st.Text = 'Đã kết nối MCP.'
      $s = $script:schemas[$t[1]]; $desc.Text = "[$($t[1])]  $($t[3])`r`n$($s.description)"
      $props = $s.inputSchema['properties']; $req = @($s.inputSchema['required'])
      if ($props) { foreach ($k in $props.Keys) { $p = $props[$k]
        Add-Field $k (TypeOf $p['type']) ($req -contains $k) $p['default'] ("" + $p['description']) $p['enum'] } }
    } else {
      $path = $t[1]; $tok = $null; $err = $null
      $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$err)
      $hdr = (Get-Content $path -TotalCount 12 | ? { $_ -match '^\s*#' }) -join "`r`n"
      $desc.Text = "[$(Split-Path $path -Leaf)]  $($t[3])`r`n$hdr"
      if ($ast.ParamBlock) { foreach ($p in $ast.ParamBlock.Parameters) {
        $nm = $p.Name.VariablePath.UserPath; $ty = $p.StaticType.Name
        $isReq = [bool]($p.Attributes | ? { $_.Extent.Text -match 'Mandatory' })
        $kind = if ($ty -eq 'SwitchParameter') { 'switch' } else { $ty }
        $def = if ($p.DefaultValue) { $p.DefaultValue.Extent.Text -replace '^@\((.*)\)$', '$1' } else { $null }
        $help = $(if ($ty -match '\[\]$') { 'nhiều giá trị: cách nhau bằng dấu phẩy' } else { $ty })
        Add-Field $nm $kind $isReq $def $help $null } }
    }
  } catch { $out.AppendText("LỖI: $($_.Exception.Message)`r`n") }
  $grid.ResumeLayout() })

function Val($f) { if ($f.Ctl -is [Windows.Forms.CheckBox]) { $f.Ctl.Checked } elseif ($f.Ctl -is [Windows.Forms.ComboBox]) { "$($f.Ctl.SelectedItem)" } else { $f.Ctl.Text.Trim() } }
$run.add_Click({
  $t = $script:cur; if (-not $t) { return }
  $dry = $script:fields | ? { $_.Name -match '^(dryRun|DryRun)$' } | select -First 1
  if ($t[4] -and -not ($dry -and (Val $dry))) {
    if ([Windows.Forms.MessageBox]::Show("'$($t[2])' sẽ SỬA bản vẽ / model và không Ctrl+Z được.`nChạy thật?", 'Xác nhận', 'YesNo', 'Warning') -ne 'Yes') { return } }
  foreach ($f in $script:fields) { if ($f.Req -and -not (Val $f)) { [void][Windows.Forms.MessageBox]::Show("Thiếu ô bắt buộc: $($f.Name)"); return } }
  $form.Cursor = 'WaitCursor'; $run.Enabled = $false; $st.Text = "Đang chạy $($t[2])..."
  $out.AppendText("===== $(Get-Date -f HH:mm:ss)  $($t[2])`r`n")
  try {
    if ($t[0] -eq 'mcp') {
      $a = @{}
      foreach ($f in $script:fields) { $v = Val $f
        if ($f.Type -eq 'boolean') { if ($v) { $a[$f.Name] = $true } elseif ($f.Name -match 'dryRun') { $a[$f.Name] = $false }; continue }
        if ("$v" -eq '') { continue }
        switch ($f.Type) {
          'integer' { $a[$f.Name] = [long]$v }
          'number'  { $a[$f.Name] = [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) }
          'array'   { $a[$f.Name] = @($v -split '[,;\s]+' | ? { $_ } | % { if ($_ -match '^-?\d+$') { [long]$_ } else { $_ } }) }
          default   { $a[$f.Name] = $v } } }
      $out.AppendText("args: $($json.Serialize($a))`r`n")
      $r = Mcp-Req 'tools/call' @{ name = $t[1]; arguments = $a }
      foreach ($c in $r.content) { if ($c['text']) { $out.AppendText(($c['text'] -replace "`r?`n", "`r`n") + "`r`n") } }
      if ($r.isError) { $out.AppendText("(tool báo lỗi)`r`n") }
    } else {
      $args2 = @()
      foreach ($f in $script:fields) { $v = Val $f
        if ($f.Type -eq 'switch') { if ($v) { $args2 += "-$($f.Name)" }; continue }
        if ("$v" -eq '') { continue }
        if ($f.Type -match '\[\]$') { $items = @($v -split '[,;]+' | % { $_.Trim().Trim('"', "'") } | ? { $_ })
          $args2 += "-$($f.Name) " + (($items | % { if ($_ -match '^-?[\d.]+$') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join ',') }
        elseif ($f.Type -match 'Int|Double|Single|Decimal') { $args2 += "-$($f.Name) $v" }
        else { $args2 += "-$($f.Name) '" + ($v -replace "'", "''") + "'" } }
      $cmd = "`$env:SESSIONNAME='Console'; & '$($t[1])' $($args2 -join ' ')"
      $out.AppendText("> $cmd`r`n")
      $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
      $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command "' + ($cmd -replace '"', '\"') + ' 2>&1"'
      $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
      $p = [Diagnostics.Process]::Start($psi); $task = $p.StandardOutput.ReadToEndAsync()
      while (-not $task.IsCompleted) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
      $out.AppendText(($task.Result -replace "`r?`n", "`r`n")); $out.AppendText("[exit $($p.ExitCode)]`r`n")
    }
    $st.Text = "Xong: $($t[2])"
  } catch { $out.AppendText("LỖI: $($_.Exception.Message)`r`n"); $st.Text = 'Lỗi' }
  $out.AppendText("`r`n"); $form.Cursor = 'Default'; $run.Enabled = $true })
$clr.add_Click({ $out.Clear() })
$form.add_FormClosing({ if ($script:mcp -and -not $script:mcp.HasExited) { $script:mcp.Kill() } })
if ($SelfTest) {  # no window: load every tool form, run the read-only get_model_info, print the output box
  foreach ($n in $tree.Nodes) { foreach ($k in $n.Nodes) { $tree.SelectedNode = $k; "{0,-45} fields: {1}" -f $k.Text, (($script:fields | % { $_.Name + ':' + $_.Type }) -join ', ') } }
  $tree.SelectedNode = $tree.Nodes[0].Nodes[0]; $run.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($run, @([EventArgs]::Empty)); $out.Text
  if ($Snapshot) { # render the window off-screen to a PNG (no screen capture)
    $form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-5000, -5000); $form.ShowInTaskbar = $false; $form.Show()
    $tree.SelectedNode = $tree.Nodes[1].Nodes[2]; [Windows.Forms.Application]::DoEvents()
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height); $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save($Snapshot); $form.Hide() }
  if ($script:mcp -and -not $script:mcp.HasExited) { $script:mcp.Kill() }; return }
[void]$form.ShowDialog()
