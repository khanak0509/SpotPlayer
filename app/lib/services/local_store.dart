import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'api.dart';
import 'server_connectivity.dart';
import 'user_prefs_store.dart';

final localStoreProvider = Provider((ref) => LocalStore());

class LocalStore {
  static const _playlistsBox = 'playlists';
  static const _tracksBox = 'track_paths';

  Box<String>? _playlists;
  Box<String>? _tracks;
  final _present = <String>{};

  Future<void> init() async {
    await Hive.initFlutter();
    _playlists = await Hive.openBox<String>(_playlistsBox);
    _tracks = await Hive.openBox<String>(_tracksBox);
    _present.clear();
    for (final key in _tracks!.keys) {
      final path = _tracks!.get(key);
      if (path != null && File(path).existsSync()) _present.add(key as String);
    }
  }

  List<PlaylistSummary> getAllPlaylists() {
    final maps = <Map<String, dynamic>>[];
    for (final key in _playlists!.keys) {
      final val = _playlists!.get(key);
      if (val != null) maps.add(jsonDecode(val) as Map<String, dynamic>);
    }
    maps.sort((a, b) => (b['imported_at'] as String? ?? '').compareTo(a['imported_at'] as String? ?? ''));
    return maps.map(_summaryFromMap).toList();
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

  Future<void> deletePlaylist(String id) async {
    await _playlists!.delete(id);
    await reclaimOrphanTracks();
  }

  Future<int> reclaimOrphanTracks({Set<String> keepIds = const {}}) async {
    final referenced = <String>{...keepIds};
    for (final key in _playlists!.keys) {
      final detail = getPlaylist(key as String);
      if (detail == null) continue;
      for (final track in detail.tracks) {
        referenced.add(track.id);
      }
    }

    var removed = 0;
    for (final key in _tracks!.keys.toList()) {
      final trackId = key as String;
      if (referenced.contains(trackId)) continue;
      await deleteTrackPath(trackId);
      removed++;
    }
    return removed;
  }

  bool hasTrack(String trackId) => _present.contains(trackId);

  String? getTrackPath(String trackId) {
    final path = _tracks!.get(trackId);
    if (path != null && File(path).existsSync()) return path;
    _present.remove(trackId);
    return null;
  }

  Future<void> saveTrackPath(String trackId, String path) {
    _present.add(trackId);
    return _tracks!.put(trackId, path);
  }

  Future<void> deleteTrackPath(String trackId) async {
    final path = _tracks!.get(trackId);
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    _present.remove(trackId);
    await _tracks!.delete(trackId);
  }

  Future<void> clearAllTracks() async {
    for (final path in _tracks!.values) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    _present.clear();
    await _tracks!.clear();

    for (final key in _playlists!.keys.toList()) {
      final detail = getPlaylist(key as String);
      if (detail == null) continue;
      final tracks = detail.tracks
          .map((t) => t.copyWith(status: TrackStatus.queued))
          .toList();
      await savePlaylist(detail.copyWith(
        tracks: tracks,
        readyCount: 0,
        syncing: tracks.isNotEmpty,
      ));
    }
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

  Future<String> trackFilePath(String trackId, {String ext = 'mp3'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/tracks');
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    return '${audioDir.path}/$trackId.$ext';
  }

  PlaylistSummary _summaryFromMap(Map<String, dynamic> map) {
    final tracks = (map['tracks'] as List?) ?? [];
    var ready = 0;
    var inFlight = 0;
    for (final t in tracks) {
      final m = t as Map;
      final id = m['id'] as String;
      if (hasTrack(id)) {
        ready++;
        continue;
      }
      final status = m['status'] as String? ?? 'queued';
      if (status == 'failed') {
        continue;
      }
      inFlight++;
    }
    return PlaylistSummary(
      id: map['id'] as String,
      name: map['name'] as String,
      coverUrl: map['cover_url'] as String?,
      trackCount: tracks.length,
      readyCount: ready,
      syncing: inFlight > 0,
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

    final ready = tracks.where((t) => hasTrack(t.id)).length;
    final syncing = tracks.any((t) {
      if (hasTrack(t.id)) return false;
      return t.status != TrackStatus.failed;
    });

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

  List<TrackWithPlaylist> getAllTrackEntries({bool uniqueByTrackId = false}) {
    final entries = <TrackWithPlaylist>[];
    final seen = <String>{};
    for (final summary in getAllPlaylists()) {
      final detail = getPlaylist(summary.id);
      if (detail == null) continue;
      for (final track in detail.tracks) {
        if (uniqueByTrackId && !seen.add(track.id)) continue;
        entries.add(TrackWithPlaylist(
          track: hasTrack(track.id) ? track.copyWith(status: TrackStatus.ready) : track,
          playlistId: detail.id,
          playlistName: detail.name,
        ));
      }
    }
    return entries;
  }

  List<Track> getLikedTracks(Set<String> favoriteIds) {
    final byId = <String, Track>{};
    for (final entry in getAllTrackEntries()) {
      if (!favoriteIds.contains(entry.track.id)) continue;
      byId.putIfAbsent(
        entry.track.id,
        () => hasTrack(entry.track.id)
            ? entry.track.copyWith(status: TrackStatus.ready)
            : entry.track,
      );
    }
    return byId.values.toList();
  }

  int localSavedCount(List<Track> tracks) =>
      tracks.where((t) => hasTrack(t.id)).length;

  int failedCount(List<Track> tracks) =>
      tracks.where((t) => !hasTrack(t.id) && t.status == TrackStatus.failed).length;
}

final trackSyncProvider = Provider((ref) => TrackSyncService(ref));

final libraryTickProvider = StateProvider<int>((ref) => 0);

class TrackSyncService {
  TrackSyncService(this.ref);

  final Ref ref;
  final _activeDownloads = <String, Future<String?>>{};

  int get activeDownloadCount => _activeDownloads.length;

  void _tick() {
    ref.read(libraryTickProvider.notifier).state++;
  }
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
    if (!ref.read(serverReachableProvider)) return detail;

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
        .toList();

    const batchSize = 4;
    for (var i = 0; i < toDownload.length; i += batchSize) {
      final chunk = toDownload.skip(i).take(batchSize);
      await Future.wait(chunk.map((track) async {
        try {
          await downloadTrack(track);
        } catch (_) {}
      }));
    }

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
    final store = ref.read(localStoreProvider);
    final tracks = detail.tracks.map((t) {
      if (t.id == trackId) return t.copyWith(status: TrackStatus.ready);
      return t;
    }).toList();
    final ready = tracks.where((t) => store.hasTrack(t.id)).length;
    final syncing = tracks.any((t) {
      if (store.hasTrack(t.id)) return false;
      return t.status != TrackStatus.failed;
    });
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

  Future<String?> downloadTrack(Track track) async {
    final store = ref.read(localStoreProvider);
    final existing = store.getTrackPath(track.id);
    if (existing != null) return existing;

    final inFlight = _activeDownloads[track.id];
    if (inFlight != null) return inFlight;

    final future = _downloadTrackOnce(track);
    _activeDownloads[track.id] = future;
    _tick();
    try {
      final path = await future;
      _tick();
      return path;
    } finally {
      _activeDownloads.remove(track.id);
      _tick();
    }
  }

  Future<String?> _downloadTrackOnce(Track track) async {
    final store = ref.read(localStoreProvider);
    final existing = store.getTrackPath(track.id);
    if (existing != null) return existing;

    final api = ref.read(apiProvider);
    final tmp = await store.trackFilePath(track.id, ext: 'part');

    try {
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      )).download(api.streamUrl(track.id), tmp);
      final type = res.headers.value(Headers.contentTypeHeader) ?? '';
      final dest = await store.trackFilePath(track.id, ext: type.contains('mp4') ? 'm4a' : 'mp3');
      await File(tmp).rename(dest);
      await store.saveTrackPath(track.id, dest);
      return dest;
    } on DioException catch (e) {
      try {
        await File(tmp).delete();
      } catch (_) {}
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}
