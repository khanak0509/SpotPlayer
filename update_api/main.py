from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="SpotPlayer Update API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Change these values when you release a new version on GitHub!
# The app will check this endpoint and compare its own version.
LATEST_VERSION = os.getenv("LATEST_VERSION", "1.0.0")
DOWNLOAD_URL = os.getenv("DOWNLOAD_URL", "https://github.com/khanak0509/SpotPlayer/blob/main/SpotPlayer.apk")
RELEASE_NOTES = os.getenv("RELEASE_NOTES", "Initial release")
IS_CRITICAL = os.getenv("IS_CRITICAL", "false").lower() == "true"

@app.get("/ping")
def check_update():
    return {
        "latest_version": LATEST_VERSION,
        "download_url": DOWNLOAD_URL,
        "release_notes": RELEASE_NOTES,
        "is_critical": IS_CRITICAL
    }

@app.get("/")
def root():
    return {"status": "SpotPlayer Update API is running"}
