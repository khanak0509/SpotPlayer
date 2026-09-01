import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/local_store.dart';

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

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshSyncing());
  }

  Future<void> _refreshSyncing() async {
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
    }
    _wasSyncing = anySyncing;
    state = state.copyWith(playlists: updated);

    if (!anySyncing) _pollTimer?.cancel();
  }

  Future<PlaylistSummary?> importPlaylist(String url) async {
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
      await sync.queueTracks(detail.tracks);

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

  Future<void> syncPlaylist(String id) async {
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
      ref.read(trackSyncProvider).queueTracks(merged.tracks);
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

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final playlistDetailProvider =
    FutureProvider.family<PlaylistDetail, String>((ref, id) async {
  final store = ref.read(localStoreProvider);
  final sync = ref.read(trackSyncProvider);
  var detail = store.getPlaylist(id);
  if (detail == null) throw Exception('Playlist not found');
  return sync.refreshPlaylist(detail);
});
