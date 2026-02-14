@echo off
echo ============================================
echo    REAL DATA RECONCILIATION
echo    Source APIs vs BigQuery
echo ============================================
echo.

cd /d "%~dp0"

echo This script compares data from:
echo   - Shopify API
echo   - Facebook Marketing API
echo   - TikTok Marketing API
echo.
echo Against BigQuery tables.
echo.

set /p days="Enter number of days to check (default 30): "
if "%days%"=="" set days=30

python real_reconciliation.py

echo.
pause
