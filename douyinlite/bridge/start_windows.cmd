@echo off
setlocal EnableExtensions
chcp 65001 >nul
title DouyinLite PC Login
set "APP_DIR=%~dp0"

rem Support both the recommended flat ZIP and the old nested repository ZIP.
if not exist "%APP_DIR%requirements.txt" (
    if exist "%APP_DIR%douyinlite\bridge\requirements.txt" (
        set "APP_DIR=%APP_DIR%douyinlite\bridge\"
    )
)
if not exist "%APP_DIR%requirements.txt" goto missing_files
if not exist "%APP_DIR%windows_launcher.py" goto missing_files
if not exist "%APP_DIR%app.py" goto missing_files
if not exist "%APP_DIR%streamer.py" goto missing_files
if not exist "%APP_DIR%media.py" goto missing_files
if not exist "%APP_DIR%share.py" goto missing_files
cd /d "%APP_DIR%"
if errorlevel 1 goto failure

where py >nul 2>nul
if not errorlevel 1 (
    set "PYTHON_CMD=py -3"
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        echo ERROR: Python 3.10+ is required. Install it from https://www.python.org/downloads/windows/
        goto failure
    )
    set "PYTHON_CMD=python"
)
set "PYTHON_EXE=%APP_DIR%.venv\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
    echo Creating isolated Python environment...
    %PYTHON_CMD% -m venv "%APP_DIR%.venv"
    if errorlevel 1 goto failure
)
echo Installing Python requirements from "%APP_DIR%requirements.txt"...
"%PYTHON_EXE%" -m pip install --disable-pip-version-check -r "%APP_DIR%requirements.txt"
if errorlevel 1 goto failure
echo Installing Chromium...
"%PYTHON_EXE%" -m playwright install chromium
if errorlevel 1 goto failure
echo Starting DouyinLite companion...
"%PYTHON_EXE%" "%APP_DIR%windows_launcher.py"
if errorlevel 1 goto failure
goto end

:missing_files
echo.
echo ERROR: DouyinLite companion files are missing.
echo The folder must contain start_windows.cmd, requirements.txt, app.py,
echo windows_launcher.py, media.py, streamer.py, and share.py.
echo.
echo Please RIGHT CLICK the Windows ZIP, select Extract All,
echo then double-click start_windows.cmd INSIDE the extracted folder.
echo Do not run the BAT directly from inside a ZIP preview.
goto failure

:failure
echo.
echo Companion could not start. The error is shown above.
pause
exit /b 1

:end
endlocal
