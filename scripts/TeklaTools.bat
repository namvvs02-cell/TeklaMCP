@echo off
rem Tekla Tools: giao dien chay tay cac tool Claude da build (can Tekla 2020 dang mo model / drawing).
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0TeklaMcp\Scripts\TeklaTools.ps1"
