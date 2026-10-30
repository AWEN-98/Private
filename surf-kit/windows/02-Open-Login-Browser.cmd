@echo off
setlocal
chcp 65001 >nul
set "SURF_HOME=%LOCALAPPDATA%\DouyinLiteSurfHost"
set "SURF_EXE="
for /R "%~dp0Surf-Windows" %%F in (surf.exe) do if exist "%%F" (set "SURF_EXE=%%F" & goto found)
:found
if not defined SURF_EXE (echo Surf not found & pause & exit /b 1)
echo Opening the Surf browser on this PC for regular Douyin sign-in ...
"%SURF_EXE%" browser
echo When done, close all browser setup windows to resume the phone stream.
pause
endlocal
