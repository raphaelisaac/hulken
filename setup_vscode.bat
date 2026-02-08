@echo off
REM ============================================================
REM Better Signal - VSCode + BigQuery Setup for Analysts
REM One-click installation script
REM ============================================================
echo.
echo ============================================================
echo   Better Signal - Analyst Environment Setup
echo ============================================================
echo.

REM Check if running as admin (not required but helpful)
echo [1/6] Checking prerequisites...

REM Check Python
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found. Install from https://python.org/downloads
    echo         Make sure to check "Add Python to PATH" during install.
    pause
    exit /b 1
)
echo   Python: OK

REM Check VSCode
code --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] VSCode CLI not found. Install from https://code.visualstudio.com
    echo           Continuing with other installs...
) else (
    echo   VSCode: OK
)

REM ============================================================
REM Install Google Cloud SDK
REM ============================================================
echo.
echo [2/6] Checking Google Cloud SDK...
gcloud --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Google Cloud SDK not found.
    echo   Please install from: https://cloud.google.com/sdk/docs/install
    echo   After install, run this script again.
    echo.
    start https://cloud.google.com/sdk/docs/install
    pause
    exit /b 1
) else (
    echo   Google Cloud SDK: OK
)

REM ============================================================
REM Authenticate with Google Cloud
REM ============================================================
echo.
echo [3/6] Setting up Google Cloud authentication...
gcloud config set project hulken
echo   Project set to: hulken

REM Check if already authenticated
gcloud auth application-default print-access-token >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   Opening browser for authentication...
    gcloud auth application-default login
) else (
    echo   Already authenticated: OK
)

REM ============================================================
REM Install VSCode Extensions
REM ============================================================
echo.
echo [4/6] Installing VSCode extensions...
code --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo   Installing Google Cloud Code...
    code --install-extension GoogleCloudTools.cloudcode --force
    echo   Installing SQLTools...
    code --install-extension mtxr.sqltools --force
    echo   Installing SQLTools BigQuery Driver...
    code --install-extension Evidence.sqltools-bigquery-driver --force
    echo   Installing Python...
    code --install-extension ms-python.python --force
    echo   Extensions installed!
) else (
    echo   [SKIP] VSCode not available - install extensions manually
)

REM ============================================================
REM Install Python Dependencies
REM ============================================================
echo.
echo [5/6] Installing Python packages...
pip install google-cloud-bigquery pandas pyarrow python-dotenv db-dtypes tabulate --quiet
if %ERRORLEVEL% EQU 0 (
    echo   Python packages installed!
) else (
    echo   [WARNING] Some packages may have failed. Try: pip install -r data_validation\requirements.txt
)

REM ============================================================
REM Verify Setup
REM ============================================================
echo.
echo [6/6] Verifying setup...
python -c "from google.cloud import bigquery; c = bigquery.Client(project='hulken'); print('  BigQuery connection: OK - project hulken')" 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [WARNING] BigQuery connection test failed.
    echo   You may need to run: gcloud auth application-default login
)

echo.
echo ============================================================
echo   SETUP COMPLETE!
echo ============================================================
echo.
echo   Next steps:
echo   1. Open VSCode in the Better_signal folder
echo   2. Read docs\QUICK_START_ANALYST.md for query examples
echo   3. Try: python -c "from google.cloud import bigquery; print('Ready!')"
echo.
echo   Quick test query:
echo   python data_validation\reconciliation_check.py --checks freshness
echo.
pause
