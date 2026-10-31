@echo off
setlocal
cd /d "%~dp0"
title DouyinLite PC Login
where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON=py -3"
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        echo Python 3.10+ not found. Install official Python from https://www.python.org/downloads/windows/
        pause
        exit /b 1
    )
    set "PYTHON=python"
)
if not exist ".venv\Scripts\python.exe" (
    echo Creating isolated Python environment...
    %PYTHON% -m venv .venv
    if errorlevel 1 goto failure
)
set "PYTHON_EXE=%cd%\.venv\Scripts\python.exe"
echo Installing required browser support...
"%PYTHON_EXE%" -m pip install --disable-pip-version-check -r requirements.txt
if errorlevel 1 goto failure
"%PYTHON_EXE%" -m playwright install chromium
if errorlevel 1 goto failure
echo Starting DouyinLite browser companion...
"%PYTHON_EXE%" windows_launcher.py
if errorlevel 1 goto failure
goto end
:failure
echo.
echo Login companion could not start. See the error above.
pause
exit /b 1
:end
endlocal
