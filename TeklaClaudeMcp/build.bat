@echo off
rem ============================================================
rem  Build TeklaClaudeMcp cho Tekla Structures 2020 SP14 (net48)
rem  Ket qua: D:\TeklaClaude\TeklaMcp\TeklaClaude2020\TeklaClaudeMcp.exe
rem ============================================================
setlocal

set "PROJ=%~dp0TeklaClaudeMcp.csproj"
set "OUT=%~dp0bin\Release\net48"
set "DEPLOY=D:\TeklaClaude\TeklaMcp\TeklaClaude2020"
set "TEKLALIBS=D:\TeklaClaude\TeklaMcp\Tekla2020"
set "MSB="

if not exist "%TEKLALIBS%\Tekla.Structures.Drawing.dll" (
  echo [LOI] Khong thay Tekla.Structures.Drawing.dll trong %TEKLALIBS%
  goto :fail
)

rem --- 1. Tim MSBuild cua Visual Studio (2019/2022) ---
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
  for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe`) do set "MSB=%%i"
)

if defined MSB goto :build_msbuild
where dotnet >nul 2>nul
if %errorlevel%==0 goto :build_dotnet
echo [LOI] Khong tim thay MSBuild (Visual Studio 2019/2022) va khong co dotnet SDK.
echo       Cai Visual Studio Build Tools voi ".NET desktop build tools" + ".NET Framework 4.8 targeting pack".
goto :fail

:build_msbuild
echo Dung MSBuild: %MSB%
"%MSB%" "%PROJ%" /restore /t:Rebuild /p:Configuration=Release /v:minimal /nologo
if errorlevel 1 goto :fail
goto :deploy

:build_dotnet
echo Dung dotnet build
dotnet build "%PROJ%" -c Release --nologo -v minimal
if errorlevel 1 goto :fail
goto :deploy

:deploy
if not exist "%OUT%\TeklaClaudeMcp.exe" (
  echo [LOI] Khong thay %OUT%\TeklaClaudeMcp.exe sau khi build.
  goto :fail
)
echo Chep ket qua sang %DEPLOY% ...
if not exist "%DEPLOY%" mkdir "%DEPLOY%"
xcopy "%OUT%\*" "%DEPLOY%\" /E /Y /I /Q >nul
if errorlevel 1 goto :fail

echo.
echo ==== BUILD XONG ====
echo Chay thu: "%DEPLOY%\TeklaClaudeMcp.exe"  (server dung stdio, se cho lenh MCP)
echo Dang ky vao Claude desktop voi lenh tren, ten goi y: tekla-2020
goto :end

:fail
echo.
echo ==== BUILD THAT BAI ====
echo Gui noi dung loi o tren cho Claude de sua.
endlocal & exit /b 1

:end
endlocal
pause
