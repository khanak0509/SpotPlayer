import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.getenv("DATA_DIR", str(BASE_DIR / "data")))
TEMP_DIR = Path(os.getenv("TEMP_DIR", str(DATA_DIR / "audio")))
DOWNLOAD_WORKERS = int(os.getenv("DOWNLOAD_WORKERS", "4"))
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))

DATA_DIR.mkdir(parents=True, exist_ok=True)
TEMP_DIR.mkdir(parents=True, exist_ok=True)
