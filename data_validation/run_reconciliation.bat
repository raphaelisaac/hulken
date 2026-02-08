@echo off
echo ============================================
echo    DATA RECONCILIATION - Better Signals
echo ============================================
echo.

cd /d "%~dp0"

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    pause
    exit /b 1
)

REM Run the reconciliation script
python reconciliation_report.py

echo.
echo ============================================
echo    Report generated! Check the HTML file.
echo ============================================
pause
