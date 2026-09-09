#!/bin/sh
set -e

echo ""
echo "=============================================="
if [ -n "$HOST_IP" ]; then
  echo "  Paste in app → Settings → Server:"
  echo ""
  echo "  http://${HOST_IP}:8000/api"
else
  echo "  Backend running on port 8000"
  echo "  Use: http://YOUR_WIFI_IP:8000/api"
fi
echo ""
echo "  Phone + computer on same Wi-Fi"
echo "=============================================="
echo ""

exec uvicorn main:app --host 0.0.0.0 --port "${PORT:-8000}"
