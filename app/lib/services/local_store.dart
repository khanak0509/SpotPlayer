import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'api.dart';

final localStoreProvider = Provider((ref) => LocalStore());

class LocalStore {
  static const _playlistsBox = 'playlists';
  static const _tracksBox = 'track_paths';

  Box<String>? _playlists;
  Box<String>? _tracks;

  Future<void> init() async {
    await Hive.initFlutter();
    _playlists = await Hive.openBox<String>(_playlistsBox);
    _tracks = await Hive.openBox<String>(_tracksBox);
  }

  List<PlaylistSummary> getAllPlaylists() {
    final entries = <MapEntry<String, String>>[];
    for (final key in _playlists!.keys) {
      final val = _playlists!.get(key);
      if (val != null) entries.add(MapEntry(key, val));
    }
    entries.sort((a, b) {
      final aAt = (jsonDecode(a.value) as Map)['imported_at'] as String? ?? '';
      final bAt = (jsonDecode(b.value) as Map)['imported_at'] as String? ?? '';
      return bAt.compareTo(aAt);
    });
    return entries.map((e) => _summaryFromMap(jsonDecode(e.value) as Map<String, dynamic>)).toList();
  }

  PlaylistDetail? getPlaylist(String id) {
    final raw = _playlists!.get(id);
    if (raw == null) return null;
    return PlaylistDetail.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePlaylist(PlaylistDetail detail) {
    final map = detail.toJson();
    final existing = _playlists!.get(detail.id);
    if (existing != null) {
      final old = jsonDecode(existing) as Map<String, dynamic>;
      map['imported_at'] = old['imported_at'] ?? DateTime.now().toIso8601String();
    } else {
      map['imported_at'] = DateTime.now().toIso8601String();
    }
    return _playlists!.put(detail.id, jsonEncode(map));
  }

  Future<void> deletePlaylist(String id) => _playlists!.delete(id);

  bool hasTrack(String trackId) {
    final path = _tracks!.get(trackId);
    return path != null && File(path).existsSync();
  }

  String? getTrackPath(String trackId) {
    final path = _tracks!.get(trackId);
    if (path != null && File(path).existsSync()) return path;
    return null;
  }

  Future<void> saveTrackPath(String trackId, String path) {
    return _tracks!.put(trackId, path);
  }

  Future<void> deleteTrackPath(String trackId) async {
    final path = _tracks!.get(trackId);
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await _tracks!.delete(trackId);
  }

  Future<void> clearAllTracks() async {
    for (final path in _tracks!.values) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await _tracks!.clear();
  }

  Future<int> trackStorageBytes() async {
    var total = 0;
    for (final path in _tracks!.values) {
      final f = File(path);
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  int get cachedTrackCount => _tracks!.length;

  Future<String> trackFilePath(String trackId) async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/tracks');
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    return '${audioDir.path}/$trackId.mp3';
  }

  PlaylistSummary _summaryFromMap(Map<String, dynamic> map) {
    final tracks = (map['tracks'] as List?) ?? [];
    var ready = 0;
    for (final t in tracks) {
      if (hasTrack((t as Map)['id'] as String)) ready++;
    }
    final syncing = ready < tracks.length;
    return PlaylistSummary(
      id: map['id'] as String,
      name: map['name'] as String,
      coverUrl: map['cover_url'] as String?,
      trackCount: tracks.length,
      readyCount: ready,
      syncing: syncing,
      spotifyUrl: map['spotify_url'] as String? ?? '',
    );
  }

  PlaylistDetail mergeStatuses(PlaylistDetail detail, Map<String, TrackStatus> serverStatuses) {
    final tracks = detail.tracks.map((t) {
      if (hasTrack(t.id)) return t.copyWith(status: TrackStatus.ready);
      final server = serverStatuses[t.id];
      if (server != null) return t.copyWith(status: server);
      return t;
    }).toList();

    final ready = tracks.where((t) => t.status == TrackStatus.ready).length;
    final syncing = tracks.any((t) =>
        t.status == TrackStatus.queued ||
        t.status == TrackStatus.downloading ||
        t.status == TrackStatus.resolving);

    return PlaylistDetail(
      id: detail.id,
      name: detail.name,
      coverUrl: detail.coverUrl,
      spotifyUrl: detail.spotifyUrl,
      tracks: tracks,
      readyCount: ready,
      syncing: syncing,
    );
  }

  List<PlaylistSummary> summariesFromDetails() => getAllPlaylists();
}

final trackSyncProvider = Provider((ref) => TrackSyncService(ref));

class TrackSyncService {
  TrackSyncService(this.ref);

  final Ref ref;

  Future<void> queueTracks(List<Track> tracks) async {
    final store = ref.read(localStoreProvider);
    final missing = tracks.where((t) => !store.hasTrack(t.id)).toList();
    if (missing.isEmpty) return;

    final api = ref.read(apiProvider);
    await api.queueTracks(missing);
  }

  Future<Map<String, TrackStatus>> fetchStatuses(List<Track> tracks) async {
    final store = ref.read(localStoreProvider);
    final needServer = tracks.where((t) => !store.hasTrack(t.id)).map((t) => t.id).toList();
    if (needServer.isEmpty) return {};

    final api = ref.read(apiProvider);
    return api.batchTrackStatus(needServer);
  }

  Future<PlaylistDetail> refreshPlaylist(PlaylistDetail detail) async {
    final store = ref.read(localStoreProvider);
    final needQueue = detail.tracks.where((t) {
      if (store.hasTrack(t.id)) return false;
      return t.status == TrackStatus.queued || t.status == TrackStatus.resolving;
    }).toList();
    if (needQueue.isNotEmpty) {
      await queueTracks(needQueue);
    }

    final statuses = await fetchStatuses(detail.tracks);
    var merged = store.mergeStatuses(detail, statuses);

    final toDownload = merged.tracks
        .where((t) => !store.hasTrack(t.id) && t.status == TrackStatus.ready)
        .take(3)
        .toList();

    await Future.wait(toDownload.map(downloadTrack));

    final updatedStatuses = await fetchStatuses(detail.tracks);
    merged = store.mergeStatuses(detail, updatedStatuses);

    for (final track in merged.tracks) {
      if (store.hasTrack(track.id)) {
        merged = _markReady(merged, track.id);
      }
    }

    await store.savePlaylist(merged);
    return merged;
  }

  PlaylistDetail _markReady(PlaylistDetail detail, String trackId) {
    final tracks = detail.tracks.map((t) {
      if (t.id == trackId) return t.copyWith(status: TrackStatus.ready);
      return t;
    }).toList();
    final ready = tracks.where((t) => t.status == TrackStatus.ready).length;
    return PlaylistDetail(
      id: detail.id,
      name: detail.name,
      coverUrl: detail.coverUrl,
      spotifyUrl: detail.spotifyUrl,
      tracks: tracks,
      readyCount: ready,
      syncing: ready < tracks.length,
    );
  }

  Future<String?> downloadTrack(Track track) async {
    final store = ref.read(localStoreProvider);
    final existing = store.getTrackPath(track.id);
    if (existing != null) return existing;

    final api = ref.read(apiProvider);
    final dest = await store.trackFilePath(track.id);
    final tmp = '$dest.part';

    await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    )).download(api.streamUrl(track.id), tmp);
    await File(tmp).rename(dest);
    await store.saveTrackPath(track.id, dest);
    return dest;
  }
}
