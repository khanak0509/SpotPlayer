#!/bin/sh
set -e

GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "${YTDLP_AUTO_UPDATE:-1}" = "1" ]; then
  pip install --no-cache-dir --quiet --disable-pip-version-check -U "yt-dlp[default]" || true
fi

printf "\n"
printf "${CYAN}======================================================${NC}\n"
printf "${GREEN}  🚀 SPOTPLAYER BACKEND IS READY!${NC}\n"
printf "\n"
if [ -n "$HOST_IP" ]; then
  printf "  Paste this exact URL in your app (Settings → Server):\n"
  printf "\n"
  printf "  👉  ${YELLOW}http://${HOST_IP}:8000/api${NC}  👈\n"
  printf "\n"
  printf "  Or scan this from the app (or open http://localhost:8000/connect):\n"
  python -c "import qrcode, sys; q = qrcode.QRCode(border=2); q.add_data(sys.argv[1]); q.print_ascii(invert=True)" "http://${HOST_IP}:8000/api" \
    || true
else
  printf "  Backend running on port 8000\n"
  printf "  👉  ${YELLOW}http://YOUR_WIFI_IP:8000/api${NC}  👈\n"
fi
printf "\n"
printf "${CYAN}  ⚠️  Make sure Phone + Computer are on the SAME Wi-Fi${NC}\n"
printf "${CYAN}======================================================${NC}\n"
printf "\n"

exec uvicorn main:app --host 0.0.0.0 --port "${PORT:-8000}"
