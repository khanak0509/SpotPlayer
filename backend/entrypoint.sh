#!/bin/sh
set -e

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

printf "\n"
printf "${CYAN}======================================================${NC}\n"
printf "${GREEN}  🚀 SPOTPLAYER BACKEND IS READY!${NC}\n"
printf "\n"
if [ -n "$HOST_IP" ]; then
  printf "  Paste this exact URL in your app (Settings → Server):\n"
  printf "\n"
  printf "  👉  ${YELLOW}http://${HOST_IP}:8000/api${NC}  👈\n"
else
  printf "  Backend running on port 8000\n"
  printf "  👉  ${YELLOW}http://YOUR_WIFI_IP:8000/api${NC}  👈\n"
fi
printf "\n"
printf "${CYAN}  ⚠️  Make sure Phone + Computer are on the SAME Wi-Fi${NC}\n"
printf "${CYAN}======================================================${NC}\n"
printf "\n"

exec uvicorn main:app --host 0.0.0.0 --port "${PORT:-8000}"
