<#
  Build TeklaClaudeMcp without Visual Studio / MSBuild / .NET SDK.
  Downloads the Roslyn compiler (NuGet Microsoft.Net.Compilers.Toolset) into .\tools on first run,
  compiles against the DLLs in -LibDir, and optionally deploys over the running server.

  Usage (PowerShell):
    powershell -ExecutionPolicy Bypass -File build_roslyn.ps1                 # build only
    powershell -ExecutionPolicy Bypass -File build_roslyn.ps1 -Deploy         # build + replace running exe

  -LibDir must contain the Tekla 2020 DLLs (Tekla.Structures*.dll) and the MCP runtime DLLs
  (ModelContextProtocol*, Microsoft.Extensions.*, System.Text.Json, Newtonsoft.Json ...).
  The deployed server folder already has all of them.
#>
param(
    [string]$LibDir = "D:\TeklaClaude\TeklaMcp\TeklaClaude2020",
    [string]$DeployDir = "D:\TeklaClaude\TeklaMcp\TeklaClaude2020",
    [switch]$Deploy,
    [string]$RoslynVersion = "4.8.0"
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$src = Join-Path $root "TeklaClaudeMcp"
$out = Join-Path $src "bin\Release\net48"
$tools = Join-Path $root "tools\roslyn-$RoslynVersion"
$csc = Join-Path $tools "tasks\net472\csc.exe"

if (-not (Test-Path $csc)) {
    Write-Host "Downloading Roslyn $RoslynVersion ..."
    New-Item -ItemType Directory -Force $tools | Out-Null
    $zip = Join-Path $tools "pkg.zip"
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -UseBasicParsing "https://api.nuget.org/v3-flatcontainer/microsoft.net.compilers.toolset/$RoslynVersion/microsoft.net.compilers.toolset.$RoslynVersion.nupkg" -OutFile $zip
    Expand-Archive $zip $tools -Force
    $sig = Get-AuthenticodeSignature $csc
    if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Subject -notmatch "Microsoft") { throw "csc.exe signature is not a valid Microsoft signature." }
}

$libs = 'ModelContextProtocol','ModelContextProtocol.Core','Microsoft.Extensions.Hosting','Microsoft.Extensions.Hosting.Abstractions',
        'Microsoft.Extensions.DependencyInjection','Microsoft.Extensions.DependencyInjection.Abstractions','Microsoft.Extensions.Logging',
        'Microsoft.Extensions.Logging.Abstractions','Microsoft.Extensions.Logging.Console','Microsoft.Extensions.Options',
        'Microsoft.Extensions.Configuration.Abstractions','System.Text.Json','Microsoft.Extensions.AI.Abstractions',
        'Microsoft.Bcl.AsyncInterfaces','Newtonsoft.Json','Tekla.Structures','Tekla.Structures.Datatype',
        'Tekla.Structures.Model','Tekla.Structures.Drawing'
$fw = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
$refs = @()
foreach ($n in $libs) {
    $p = Join-Path $LibDir "$n.dll"
    if (-not (Test-Path $p)) { throw "Missing $p" }
    $refs += "/r:$p"
}
foreach ($n in 'mscorlib','System','System.Core','Microsoft.CSharp','System.Net.Http','netstandard','System.Runtime',
               'System.Threading.Tasks','System.Xml','System.Xml.Linq','System.Data') { $refs += "/r:$fw\$n.dll" }

New-Item -ItemType Directory -Force $out | Out-Null
$files = Get-ChildItem $src -Filter *.cs | ForEach-Object FullName
& $csc /nologo /noconfig /nostdlib+ /nowarn:1702 /target:exe /platform:x64 /langversion:latest /optimize+ `
       /out:"$out\TeklaClaudeMcp.exe" @refs @files
if ($LASTEXITCODE -ne 0) { throw "Build failed." }
Copy-Item (Join-Path $src "App.config") "$out\TeklaClaudeMcp.exe.config" -Force
Write-Host "Built: $out\TeklaClaudeMcp.exe"

if ($Deploy) {
    # A running exe cannot be overwritten but can be renamed: keep it as .old-<time>.exe and copy the new one in.
    $target = Join-Path $DeployDir "TeklaClaudeMcp.exe"
    if (Test-Path $target) { Rename-Item $target ("TeklaClaudeMcp.old-" + (Get-Date -Format yyyyMMdd-HHmmss) + ".exe") }
    Copy-Item "$out\TeklaClaudeMcp.exe" $target
    Write-Host "Deployed to $target. Restart the MCP server (or Claude) to load it."
}
