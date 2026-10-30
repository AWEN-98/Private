@echo off
setlocal
chcp 65001 >nul
set "SURF_HOME=%LOCALAPPDATA%\DouyinLiteSurfHost"
set "SURF_EXE="
for /R "%~dp0Surf-Windows" %%F in (surf.exe) do if exist "%%F" (set "SURF_EXE=%%F" & goto found)
:found
if not defined SURF_EXE (echo Surf not found & pause & exit /b 1)
echo Launch Surf on your iPhone. Pair through host tray/dashboard.
echo Alternatively, this CLI command generates a one-device invitation:
"%SURF_EXE%" pair
echo If the CLI did not display the code, use tray: Paired Devices - Pair device.
pause
endlocal
