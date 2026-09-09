#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

IP="$(python3 host_ip.py 2>/dev/null || true)"

echo ""
echo "=============================================="
if [ -n "$IP" ]; then
  export HOST_IP="$IP"
  echo "  Paste in app → Settings → Server:"
  echo ""
  echo "  http://${IP}:8000/api"
else
  echo "  Could not detect Wi-Fi IP."
  echo "  Use: http://YOUR_IP:8000/api"
fi
echo ""
echo "  Phone + computer on same Wi-Fi"
echo "=============================================="
echo ""

exec docker compose up --build "$@"
