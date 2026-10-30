import logging
import os
from contextlib import asynccontextmanager

import qrcode
import qrcode.image.svg
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from download_service import start_workers
from playlist_store import init_store as init_playlist_store
from routes import router
from track_store import init_store as init_track_store

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _phone_api_url() -> str | None:
    host_ip = os.environ.get("HOST_IP", "").strip()
    if host_ip:
        return f"http://{host_ip}:8000/api"
    return None


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_playlist_store()
    await init_track_store()
    await start_workers()
    url = _phone_api_url()
    if url:
        logger.info("Backend ready — phone URL: %s", url)
    else:
        logger.info("Backend ready on port 8000")
    yield


app = FastAPI(title="SpotPlayer Backend", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Range", "Accept-Ranges", "Content-Length"],
)

app.include_router(router, prefix="/api")


@app.get("/api")
async def api_root():
    return {"ok": True, "message": "SpotPlayer backend running", "api_url": _phone_api_url()}


@app.get("/health")
async def health():
    return {"ok": True, "api_url": _phone_api_url()}


@app.get("/connect", response_class=HTMLResponse)
async def connect_page():
    url = _phone_api_url()
    if not url:
        body = "<p>Start the backend with start.sh or start.bat to get a QR code.</p>"
    else:
        svg = qrcode.make(url, image_factory=qrcode.image.svg.SvgPathImage, border=2).to_string(encoding="unicode")
        body = f'<div class="qr">{svg}</div><p>Open SpotPlayer → Settings → Server and tap the scan icon</p><code>{url}</code>'
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Connect SpotPlayer</title>
<style>
body {{ margin: 0; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center;
  background: #0a0a0c; color: #f2f2f5; font-family: -apple-system, "Segoe UI", sans-serif; text-align: center; padding: 24px; }}
.qr {{ background: #fff; padding: 16px; border-radius: 16px; }}
.qr svg {{ width: min(70vw, 320px); height: auto; display: block; }}
p {{ color: #9a9aa6; margin: 20px 0 8px; }}
code {{ color: #1ed760; font-size: 15px; }}
</style></head>
<body><h1>Connect SpotPlayer</h1>{body}</body></html>"""
