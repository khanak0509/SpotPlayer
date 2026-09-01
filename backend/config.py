import os
import tempfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
TEMP_DIR = Path(os.getenv("TEMP_DIR", tempfile.gettempdir())) / "spotplayer"
DOWNLOAD_WORKERS = int(os.getenv("DOWNLOAD_WORKERS", "4"))
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))

TEMP_DIR.mkdir(parents=True, exist_ok=True)
