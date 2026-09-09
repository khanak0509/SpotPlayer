@echo off
cd /d "%~dp0"

for /f "delims=" %%i in ('python host_ip.py 2^>nul') do set HOST_IP=%%i

echo.
echo ==============================================
if defined HOST_IP (
  echo   Paste in app - Settings - Server:
  echo.
  echo   http://%HOST_IP%:8000/api
) else (
  echo   Could not detect Wi-Fi IP.
  echo   Use: http://YOUR_IP:8000/api
)
echo.
echo   Phone + computer on same Wi-Fi
echo ==============================================
echo.

docker compose up --build
