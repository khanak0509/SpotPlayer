import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/art_background.dart';
import '../widgets/mini_player.dart';
import '../widgets/playlist_sync_progress.dart';
import '../widgets/scale_button.dart';
import '../widgets/track_row.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  Timer? _pollTimer;
  List<Track>? _orderedTracks;
  String? _tracksPlaylistId;
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(playlistDetailProvider(widget.playlistId));
      ref.read(libraryProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _syncTracks(PlaylistDetail detail) {
    if (_tracksPlaylistId != detail.id || _orderedTracks == null) {
      _orderedTracks = List<Track>.from(detail.tracks);
      _tracksPlaylistId = detail.id;
      return;
    }

    if (_orderedTracks!.length != detail.tracks.length) {
      _orderedTracks = List<Track>.from(detail.tracks);
      return;
    }

    final statusById = {for (final t in detail.tracks) t.id: t.status};
    _orderedTracks = _orderedTracks!
        .map((t) => t.copyWith(status: statusById[t.id] ?? t.status))
        .toList();
  }

  List<Track> _filterTracks(List<Track> tracks) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return tracks;
    return tracks.where((t) {
      return t.name.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _onReorder(PlaylistDetail detail, int oldIndex, int newIndex) async {
    setState(() {
      final tracks = List<Track>.from(_orderedTracks ?? detail.tracks);
      final moved = tracks.removeAt(oldIndex);
      tracks.insert(newIndex, moved);
      _orderedTracks = tracks;
    });

    await ref.read(libraryProvider.notifier).reorderPlaylistTracks(
          detail.id,
          oldIndex,
          newIndex,
        );
  }

  Future<void> _removeTrack(PlaylistDetail detail, Track track) async {
    await ref.read(libraryProvider.notifier).removeTrackFromPlaylist(detail.id, track.id);
    if (mounted) {
      setState(() {
        _orderedTracks?.removeWhere((t) => t.id == track.id);
      });
    }
  }

  PlaylistDetail _detailWithOrderedTracks(PlaylistDetail detail) {
    if (_orderedTracks == null) return detail;
    final ready = _orderedTracks!.where((t) => t.status == TrackStatus.ready).length;
    return detail.copyWith(
      tracks: _orderedTracks,
      readyCount: ready,
      syncing: ready < _orderedTracks!.length,
    );
  }

  void _playTrack(PlaylistDetail detail, Track track) {
    final fullIndex = detail.tracks.indexWhere((t) => t.id == track.id);
    ref.read(playerProvider.notifier).playTracks(
          tracks: detail.tracks,
          startIndex: fullIndex >= 0 ? fullIndex : 0,
          playlistId: detail.id,
          playlistName: detail.name,
          playlistCover: detail.coverUrl,
        );
  }

  Widget _trackTile(PlaylistDetail detail, Track track, int displayIndex) {
    final fullIndex = detail.tracks.indexWhere((t) => t.id == track.id);

    return SwipeableTrackRow(
      track: track,
      index: fullIndex >= 0 ? fullIndex : displayIndex,
      onTap: () => _playTrack(detail, track),
      onRetry: () async {
        await ref.read(apiProvider).retryTrack(track.id, detail.tracks);
        ref.invalidate(playlistDetailProvider(widget.playlistId));
      },
      onRemove: () => _removeTrack(detail, track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(playlistDetailProvider(widget.playlistId));

    return asyncDetail.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(),
        body: Center(child: Text('$e', style: const TextStyle(color: AppColors.error))),
      ),
      data: (detail) {
        _syncTracks(detail);
        return _buildContent(context, _detailWithOrderedTracks(detail));
      },
    );
  }

  Widget _buildContent(BuildContext context, PlaylistDetail detail) {
    final readyTracks = detail.tracks.where((t) => t.status == TrackStatus.ready).toList();
    final player = ref.watch(playerProvider);
    final isThisPlaylist = player.playlistId == detail.id;
    final showPause = isThisPlaylist && player.hasTrack && player.isPlaying;
    final searching = _searchController.text.trim().isNotEmpty;
    final filtered = _filterTracks(detail.tracks);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: MiniPlayerBar(onExpand: () => openNowPlaying(context)),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                ArtGradientHeader(imageUrl: detail.coverUrl, height: 300),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(
                                _showSearch ? Icons.close_rounded : Icons.search_rounded,
                                color: _showSearch ? AppColors.accent : AppColors.textPrimary,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showSearch = !_showSearch;
                                  if (!_showSearch) _searchController.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_showSearch)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Search songs or artists',
                              hintStyle: const TextStyle(color: AppColors.textMuted),
                              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 20),
                                      onPressed: () => _searchController.clear(),
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.surfaceHighlight.withValues(alpha: 0.85),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Hero(
                        tag: 'playlist-cover-${detail.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: detail.coverUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: detail.coverUrl!,
                                  width: 160,
                                  height: 160,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 160,
                                  height: 160,
                                  color: AppColors.surfaceHighlight,
                                  child: const Icon(Icons.queue_music, size: 64),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          detail.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PlaylistSyncProgress(tracks: detail.tracks),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: ScaleButton(
                                onPressed: readyTracks.isEmpty
                                    ? null
                                    : () {
                                        if (isThisPlaylist && player.hasTrack) {
                                          ref.read(playerProvider.notifier).togglePlay();
                                          return;
                                        }
                                        ref.read(playerProvider.notifier).playTracks(
                                              tracks: detail.tracks,
                                              playlistId: detail.id,
                                              playlistName: detail.name,
                                              playlistCover: detail.coverUrl,
                                            );
                                      },
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: readyTracks.isEmpty
                                        ? AppColors.surfaceHighlight
                                        : AppColors.textPrimary,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        showPause ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: readyTracks.isEmpty
                                            ? AppColors.textMuted
                                            : AppColors.background,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        showPause ? 'Pause' : 'Play',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: readyTracks.isEmpty
                                              ? AppColors.textMuted
                                              : AppColors.background,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ScaleButton(
                              onPressed: readyTracks.isEmpty
                                  ? null
                                  : () {
                                      ref.read(playerProvider.notifier).playTracks(
                                            tracks: detail.tracks,
                                            shuffle: true,
                                            playlistId: detail.id,
                                            playlistName: detail.name,
                                            playlistCover: detail.coverUrl,
                                          );
                                    },
                              child: Container(
                                height: 48,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHighlight,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Icon(
                                  Icons.shuffle_rounded,
                                  color: readyTracks.isEmpty
                                      ? AppColors.textMuted
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        searching
                            ? '${filtered.length} result${filtered.length == 1 ? '' : 's'} · swipe to remove'
                            : 'Hold a track to reorder · swipe to remove',
                        style: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (searching && filtered.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No matches',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                ),
              ),
            )
          else if (searching)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _trackTile(detail, filtered[i], i),
                childCount: filtered.length,
              ),
            )
          else
            SliverReorderableList(
              itemCount: detail.tracks.length,
              onReorderItem: (oldIndex, newIndex) => _onReorder(detail, oldIndex, newIndex),
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (_, child) {
                    final t = Curves.easeInOut.transform(animation.value);
                    return Material(
                      elevation: lerpDouble(0, 6, t) ?? 0,
                      color: AppColors.surfaceHighlight.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(8),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, i) {
                final track = detail.tracks[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(track.id),
                  index: i,
                  child: _trackTile(detail, track, i),
                );
              },
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
        ],
      ),
    );
  }
}
