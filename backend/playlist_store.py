import asyncio

_lock = asyncio.Lock()
_playlists: dict[str, dict] = {}


async def save_playlist(data: dict):
    async with _lock:
        _playlists[data["id"]] = data


async def load_playlist(playlist_id: str) -> dict | None:
    return _playlists.get(playlist_id)


async def delete_playlist(playlist_id: str):
    async with _lock:
        _playlists.pop(playlist_id, None)


async def list_playlists() -> list[dict]:
    return list(_playlists.values())
