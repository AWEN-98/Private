@echo off
setlocal
chcp 65001 >nul
set "SURF_HOME=%LOCALAPPDATA%\DouyinLiteSurfHost"
set "SURF_EXE="
for /R "%~dp0Surf-Windows" %%F in (surf.exe) do if exist "%%F" (set "SURF_EXE=%%F" & goto found)
:found
echo ================================================
echo        DouyinLite / Surf Connection Check
echo ================================================
if not defined SURF_EXE (
  echo [FAIL] No surf.exe found. Extract the entire ZIP to a folder.
  pause
  exit /b 1
)
echo [OK] Surf executable: %SURF_EXE%
echo [INFO] Server profile: %SURF_HOME%
echo.
echo [1] Surf host status:
"%SURF_EXE%" status
echo.
echo [2] TCP port 18080 on this computer:
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-NetTCPConnection -State Listen -LocalPort 18080 -ErrorAction SilentlyContinue) {Write-Host '[OK] Port 18080 is listening'} else {Write-Host '[FAIL] Port not listening: start 01-Start-Douyin-Host.cmd'}"
echo.
echo [3] Available LAN IPv4 addresses:
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '192.168.*' -or $_.IPAddress -like '10.*' -or $_.IPAddress -like '172.*' } | ForEach-Object { Write-Host $_.IPAddress - $_.InterfaceAlias }"
echo.
echo [4] Firewall check (Private network):
echo Allow Surf inbound TCP 18080 in Windows Firewall if the iPhone cannot connect.
echo.
echo [5] Browser test:
echo Use 02-Open-Login-Browser.cmd and test https://example.com first.
echo Then open https://www.douyin.com/ from the same Surf browser profile.
echo If example.com works but Douyin fails, investigate site login, IP or challenge.
echo If Surf connects but video is blank, check Surf Settings and host logs.
echo.
echo Important: Do not share server private keys or full login session folders.
pause
endlocal
