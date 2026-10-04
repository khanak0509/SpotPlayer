import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/local_store.dart';
import '../services/notification_service.dart';
import '../services/server_connectivity.dart';
import '../services/settings_store.dart';
import '../services/user_prefs_store.dart';
import 'player_provider.dart';

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier(ref);
});

class LibraryState {
  final List<PlaylistSummary> playlists;
  final bool loading;
  final String? error;

  const LibraryState({
    this.playlists = const [],
    this.loading = true,
    this.error,
  });

  bool get isEmpty => playlists.isEmpty && !loading;

  LibraryState copyWith({
    List<PlaylistSummary>? playlists,
    bool? loading,
    String? error,
  }) {
    return LibraryState(
      playlists: playlists ?? this.playlists,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier(this.ref) : super(const LibraryState());

  final Ref ref;
  Timer? _pollTimer;
  bool _wasSyncing = false;

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final store = ref.read(localStoreProvider);
      final playlists = store.getAllPlaylists();
      state = state.copyWith(playlists: playlists, loading: false);
      _wasSyncing = playlists.any((p) => p.syncing);
      _startPolling();
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> autoSyncAllIfEnabled() async {
    if (!ref.read(userPrefsProvider).autoSync) return;
    if (!ref.read(settingsStoreProvider).hasServerUrl) return;
    if (!ref.read(serverReachableProvider)) return;
    for (final playlist in state.playlists) {
      try {
        await syncPlaylist(playlist.id);
      } catch (_) {}
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshSyncing());
  }

  Future<void> _refreshSyncing() async {
    if (!ref.read(serverReachableProvider)) return;
    if (!state.playlists.any((p) => p.syncing)) return;

    final store = ref.read(localStoreProvider);
    final sync = ref.read(trackSyncProvider);
    var anySyncing = false;

    for (final summary in state.playlists) {
      if (!summary.syncing) continue;
      final detail = store.getPlaylist(summary.id);
      if (detail == null) continue;
      try {
        await sync.refreshPlaylist(detail);
      } catch (_) {}
    }

    final updated = store.getAllPlaylists();
    anySyncing = updated.any((p) => p.syncing);

    if (_wasSyncing && !anySyncing) {
      HapticFeedback.mediumImpact();
      for (final summary in updated) {
        final detail = store.getPlaylist(summary.id);
        if (detail == null) continue;
        final saved = store.localSavedCount(detail.tracks);
        if (saved > 0) {
          unawaited(
            ref.read(notificationServiceProvider).notifyDownloadBatchFinished(
                  summary.name,
                  saved,
                ),
          );
          break;
        }
      }
    }
    _wasSyncing = anySyncing;
    state = state.copyWith(playlists: updated);

    if (!anySyncing) _pollTimer?.cancel();
  }

  Future<PlaylistSummary?> importPlaylist(String url) async {
    if (!await ref.read(serverReachableProvider.notifier).refresh()) {
      state = state.copyWith(error: 'Start backend with start.sh first');
      return null;
    }
    try {
      final api = ref.read(apiProvider);
      final store = ref.read(localStoreProvider);
      final sync = ref.read(trackSyncProvider);

      final result = await api.importPlaylist(url);
      var detail = result.playlist;

      for (final track in detail.tracks) {
        if (store.hasTrack(track.id)) {
          detail = _markLocalReady(detail, track.id);
        }
      }

      await store.savePlaylist(detail);
      try {
        await sync.queueTracks(detail.tracks);
      } catch (_) {}

      await load();
      return store.getAllPlaylists().firstWhere((p) => p.id == detail.id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  PlaylistDetail _markLocalReady(PlaylistDetail detail, String trackId) {
    final tracks = detail.tracks.map((t) {
      if (t.id == trackId) return t.copyWith(status: TrackStatus.ready);
      return t;
    }).toList();
    final store = ref.read(localStoreProvider);
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

  Future<void> retryFailedTracks(String playlistId) async {
    if (!ref.read(serverReachableProvider)) {
      state = state.copyWith(error: 'Start backend with start.sh first');
      return;
    }
    try {
      final store = ref.read(localStoreProvider);
      final detail = store.getPlaylist(playlistId);
      if (detail == null) return;

      final api = ref.read(apiProvider);
      final failed = detail.tracks
          .where((t) => !store.hasTrack(t.id) && t.status == TrackStatus.failed)
          .toList();
      if (failed.isEmpty) return;

      for (final track in failed) {
        try {
          await api.retryTrack(track.id, detail.tracks);
        } catch (_) {}
      }

      final tracks = detail.tracks.map((t) {
        if (!store.hasTrack(t.id) && t.status == TrackStatus.failed) {
          return t.copyWith(status: TrackStatus.queued);
        }
        return t;
      }).toList();
      final ready = tracks.where((t) => store.hasTrack(t.id)).length;
      await store.savePlaylist(detail.copyWith(
        tracks: tracks,
        readyCount: ready,
        syncing: true,
      ));
      await load();
      _startPolling();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> syncPlaylist(String id) async {
    if (!ref.read(serverReachableProvider)) return;
    try {
      final store = ref.read(localStoreProvider);
      final detail = store.getPlaylist(id);
      if (detail == null) return;

      final api = ref.read(apiProvider);
      final result = await api.syncPlaylist(detail.spotifyUrl);

      var merged = result.playlist;
      for (final track in merged.tracks) {
        if (store.hasTrack(track.id)) {
          merged = _markLocalReady(merged, track.id);
        }
      }

      await store.savePlaylist(merged);
      await ref.read(trackSyncProvider).queueTracks(merged.tracks);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> removePlaylist(String id) async {
    await ref.read(localStoreProvider).deletePlaylist(id);
    state = state.copyWith(
      playlists: state.playlists.where((p) => p.id != id).toList(),
    );
  }

  Future<void> reorderPlaylistTracks(String playlistId, int oldIndex, int newIndex) async {
    final store = ref.read(localStoreProvider);
    final detail = store.getPlaylist(playlistId);
    if (detail == null) return;

    final tracks = List<Track>.from(detail.tracks);
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, moved);
    final reordered = [
      for (var i = 0; i < tracks.length; i++) tracks[i].copyWith(position: i),
    ];

    await store.savePlaylist(detail.copyWith(tracks: reordered));
    ref.invalidate(playlistDetailProvider(playlistId));
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final store = ref.read(localStoreProvider);
    final detail = store.getPlaylist(playlistId);
    if (detail == null) return;

    final tracks = detail.tracks.where((t) => t.id != trackId).toList();
    for (var i = 0; i < tracks.length; i++) {
      tracks[i] = tracks[i].copyWith(position: i);
    }

    final ready = tracks.where((t) => store.hasTrack(t.id)).length;
    final syncing = tracks.any((t) {
      if (store.hasTrack(t.id)) return false;
      return t.status != TrackStatus.failed;
    });
    await store.savePlaylist(detail.copyWith(
      tracks: tracks,
      readyCount: ready,
      syncing: syncing,
    ));
    await store.reclaimOrphanTracks();

    ref.read(playerProvider.notifier).removeTrackFromQueue(trackId);
    ref.invalidate(playlistDetailProvider(playlistId));
    await load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final playlistDetailProvider = Provider.family<PlaylistDetail?, String>((ref, id) {
  ref.watch(libraryProvider);
  ref.watch(libraryTickProvider);
  return ref.read(localStoreProvider).getPlaylist(id);
});
