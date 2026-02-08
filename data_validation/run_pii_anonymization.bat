@echo off
echo ============================================
echo    PII ANONYMIZATION - Better Signals
echo ============================================
echo.

cd /d "%~dp0"

echo Choose an option:
echo   1. Check PII exposure (audit only)
echo   2. Create anonymized views
echo   3. Full audit and anonymization
echo   4. Exit
echo.

set /p choice="Enter choice (1-4): "

if "%choice%"=="1" (
    python anonymize_pii.py --check
) else if "%choice%"=="2" (
    python anonymize_pii.py --anonymize
) else if "%choice%"=="3" (
    python anonymize_pii.py --all
) else if "%choice%"=="4" (
    exit /b 0
) else (
    echo Invalid choice
)

echo.
pause
