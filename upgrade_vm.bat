@echo off
REM ============================================================
REM  Upgrade Airbyte VM: 6 vCPU, 16 GB RAM
REM  Instance: instance-20260129-133637
REM  Zone: us-central1-a
REM  Project: hulken
REM ============================================================
REM  IMPORTANT: Run this from your local Windows machine
REM  Prerequisite: gcloud auth login (already done)
REM ============================================================

set INSTANCE=instance-20260129-133637
set ZONE=us-central1-a
set PROJECT=hulken
set MACHINE_TYPE=e2-custom-6-16384
set GCLOUD="C:\Users\Jarvis\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"

echo.
echo ============================================================
echo  UPGRADE VM: 6 vCPU, 16 GB RAM
echo  Instance: %INSTANCE%
echo  New type:  %MACHINE_TYPE%
echo ============================================================
echo.
echo WARNING: This will stop the VM temporarily (2-3 minutes downtime)
echo.
pause

echo.
echo [1/4] Stopping VM...
%GCLOUD% compute instances stop %INSTANCE% --zone=%ZONE% --project=%PROJECT%
if %ERRORLEVEL% neq 0 (
    echo FAILED to stop VM
    pause
    exit /b 1
)
echo VM stopped.

echo.
echo [2/4] Changing machine type to %MACHINE_TYPE%...
%GCLOUD% compute instances set-machine-type %INSTANCE% --machine-type=%MACHINE_TYPE% --zone=%ZONE% --project=%PROJECT%
if %ERRORLEVEL% neq 0 (
    echo FAILED to change machine type
    echo Starting VM back with old config...
    %GCLOUD% compute instances start %INSTANCE% --zone=%ZONE% --project=%PROJECT%
    pause
    exit /b 1
)
echo Machine type changed.

echo.
echo [3/4] Starting VM...
%GCLOUD% compute instances start %INSTANCE% --zone=%ZONE% --project=%PROJECT%
if %ERRORLEVEL% neq 0 (
    echo FAILED to start VM
    pause
    exit /b 1
)
echo VM started. Waiting 30 seconds for boot...
timeout /t 30 /nobreak

echo.
echo [4/4] Verifying new specs...
%GCLOUD% compute instances describe %INSTANCE% --zone=%ZONE% --project=%PROJECT% --format="table(name, machineType.basename(), status)"

echo.
echo ============================================================
echo  VM upgraded successfully!
echo  Next steps:
echo    1. SSH into VM:  gcloud compute ssh %INSTANCE% --zone=%ZONE% --tunnel-through-iap
echo    2. Run: sudo bash /home/jarvis/setup_swap.sh
echo    3. Run: sudo bash /home/jarvis/trigger_all_syncs.sh
echo ============================================================
pause
