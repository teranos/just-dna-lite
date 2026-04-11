@echo off
setlocal enabledelayedexpansion

title Just DNA Lite

set "APP_DIR=%~dp0app"
set "UV=%~dp0uv.exe"

echo.
echo  ============================================
echo    Just DNA Lite - Genome Analysis Tool
echo  ============================================
echo.

cd /d "%APP_DIR%"
if errorlevel 1 (
    echo ERROR: Application directory not found: %APP_DIR%
    echo Please reinstall Just DNA Lite.
    pause
    exit /b 1
)

if not exist ".venv" (
    echo  First launch detected - setting up environment...
    echo  This downloads Python and dependencies (~1-2 GB).
    echo  Please wait, this only happens once.
    echo.
    "%UV%" sync
    if errorlevel 1 (
        echo.
        echo ERROR: Environment setup failed.
        echo Please check your internet connection and try again.
        pause
        exit /b 1
    )
    echo.
    echo  Environment setup complete.
    echo.
) else (
    echo  Environment found. Starting...
    echo.
)

echo  Starting Just DNA Lite...
echo  The browser will open automatically when ready.
echo  Press Ctrl+C to stop the server.
echo.

start "" cmd /c "timeout /t 25 /nobreak >nul && start http://localhost:3000"

"%UV%" run start
