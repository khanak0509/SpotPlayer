import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from download_service import start_workers
from routes import router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _phone_api_url() -> str | None:
    host_ip = os.environ.get("HOST_IP", "").strip()
    if host_ip:
        return f"http://{host_ip}:8000/api"
    return None


@asynccontextmanager
async def lifespan(app: FastAPI):
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
