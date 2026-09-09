import asyncio
import json
import os
from pathlib import Path

_lock = asyncio.Lock()
_playlists: dict[str, dict] = {}
_loaded = False


def _state_path() -> Path:
    base = Path(os.getenv("DATA_DIR", Path(__file__).resolve().parent / "data"))
    base.mkdir(parents=True, exist_ok=True)
    return base / "playlists.json"


def _load_sync():
    global _playlists, _loaded
    if _loaded:
        return
    path = _state_path()
    if path.exists():
        try:
            raw = json.loads(path.read_text())
            if isinstance(raw, dict):
                _playlists = raw
        except Exception:
            _playlists = {}
    _loaded = True


def _save_sync():
    path = _state_path()
    path.write_text(json.dumps(_playlists, indent=2))


async def init_store():
    async with _lock:
        _load_sync()


async def save_playlist(data: dict):
    async with _lock:
        _load_sync()
        _playlists[data["id"]] = data
        _save_sync()


async def load_playlist(playlist_id: str) -> dict | None:
    async with _lock:
        _load_sync()
        return _playlists.get(playlist_id)


async def delete_playlist(playlist_id: str):
    async with _lock:
        _load_sync()
        _playlists.pop(playlist_id, None)
        _save_sync()


async def list_playlists() -> list[dict]:
    async with _lock:
        _load_sync()
        return list(_playlists.values())
