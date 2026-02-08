@echo off
echo ================================================
echo   AIRBYTE STATUS CHECK - Run in separate window
echo ================================================
echo.
echo Step 1: Starting IAP tunnel (keep this window open)
echo Step 2: Open a NEW terminal and run: ssh -p 2222 jarvis@localhost
echo.
echo Or run these commands via gcloud console:
echo.

REM Start tunnel
"C:\Users\Jarvis\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd" compute ssh instance-20260129-133637 --zone=us-central1-a --tunnel-through-iap -- "docker ps && echo '---' && pm2 status && echo '---' && docker logs airbyte-worker 2>&1 | tail -50"

pause
