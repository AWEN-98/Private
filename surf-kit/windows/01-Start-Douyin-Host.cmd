@echo off
setlocal
chcp 65001 >nul
set "SURF_HOME=%LOCALAPPDATA%\DouyinLiteSurfHost"
set "SURF_SERVER_NAME=DouyinLite Surf"
set "START_URL=https://www.douyin.com/"
set "STREAM_BITRATE=1800"
set "SURF_ADAPTIVE_VIDEO=1"
set "VW=320"
set "VH=480"
set "PORT=18080"
set "SURF_EXE="
for /R "%~dp0Surf-Windows" %%F in (surf.exe) do if exist "%%F" (set "SURF_EXE=%%F" & goto found)
:found
if not defined SURF_EXE (
  echo Surf host not found. Please unzip the complete ReadyKit first.
  pause
  exit /b 1
)
echo Starting Surf with Douyin homepage on port 18080 ...
echo You can pair your iPhone from Surf's tray icon: Paired Devices, Pair device.
start "" "%SURF_EXE%" serve
echo If Windows Firewall prompts, allow Private networks.
echo Keep this computer running while browsing on iPhone 4S.
pause
endlocal
