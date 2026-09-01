from enum import Enum
from typing import Optional

from pydantic import BaseModel


class TrackStatus(str, Enum):
    queued = "queued"
    downloading = "downloading"
    ready = "ready"
    failed = "failed"
    resolving = "resolving"


class TrackInfo(BaseModel):
    id: str
    name: str
    artist: str
    duration_ms: int
    album_art: Optional[str] = None
    status: TrackStatus = TrackStatus.queued
    position: int = 0


class PlaylistSummary(BaseModel):
    id: str
    name: str
    cover_url: Optional[str] = None
    track_count: int
    ready_count: int
    syncing: bool
    spotify_url: str


class PlaylistDetail(BaseModel):
    id: str
    name: str
    cover_url: Optional[str] = None
    spotify_url: str
    tracks: list[TrackInfo]
    ready_count: int
    syncing: bool


class ImportRequest(BaseModel):
    url: str


class SyncRequest(BaseModel):
    url: str


class ImportResponse(BaseModel):
    playlist_id: str
    name: str
    track_count: int
    playlist: PlaylistDetail


class TrackQueueItem(BaseModel):
    id: str
    name: str
    artist: str
    duration_ms: int


class QueueTracksRequest(BaseModel):
    tracks: list[TrackQueueItem]


class BatchStatusRequest(BaseModel):
    track_ids: list[str]


class BatchStatusResponse(BaseModel):
    statuses: dict[str, TrackStatus]


class SearchResult(BaseModel):
    tracks: list[TrackInfo]
