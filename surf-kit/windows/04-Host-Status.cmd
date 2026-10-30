@echo off
setlocal
chcp 65001 >nul
set "SURF_HOME=%LOCALAPPDATA%\DouyinLiteSurfHost"
set "SURF_EXE="
for /R "%~dp0Surf-Windows" %%F in (surf.exe) do if exist "%%F" (set "SURF_EXE=%%F" & goto found)
:found
if not defined SURF_EXE (echo Surf not found & pause & exit /b 1)
"%SURF_EXE%" status
pause
endlocal
