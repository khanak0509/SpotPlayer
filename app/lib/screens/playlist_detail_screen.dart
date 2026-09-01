import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/art_background.dart';
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

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(playlistDetailProvider(widget.playlistId));
      ref.read(libraryProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
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
      data: (detail) => _buildContent(context, detail),
    );
  }

  Widget _buildContent(BuildContext context, PlaylistDetail detail) {
    final readyTracks = detail.tracks.where((t) => t.status == TrackStatus.ready).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_rounded),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Hero(
                        tag: 'playlist-cover-${detail.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: detail.coverUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: detail.coverUrl!,
                                  width: 180,
                                  height: 180,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 180,
                                  height: 180,
                                  color: AppColors.surfaceHighlight,
                                  child: const Icon(Icons.queue_music, size: 64),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          detail.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${detail.tracks.length} tracks · ${detail.readyCount} ready',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: ScaleButton(
                                onPressed: readyTracks.isEmpty
                                    ? null
                                    : () {
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
                                    gradient: readyTracks.isEmpty
                                        ? null
                                        : const LinearGradient(
                                            colors: [AppColors.accent, AppColors.accentMuted],
                                          ),
                                    color: readyTracks.isEmpty ? AppColors.surfaceHighlight : null,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.play_arrow_rounded,
                                        color: readyTracks.isEmpty
                                            ? AppColors.textMuted
                                            : Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Play',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: readyTracks.isEmpty
                                              ? AppColors.textMuted
                                              : Colors.white,
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
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final track = detail.tracks[i];
                return TrackRow(
                  track: track,
                  index: i,
                  onTap: () {
                    ref.read(playerProvider.notifier).playTracks(
                          tracks: detail.tracks,
                          startIndex: i,
                          playlistId: detail.id,
                          playlistName: detail.name,
                          playlistCover: detail.coverUrl,
                        );
                  },
                  onRetry: () async {
                    await ref.read(apiProvider).retryTrack(track.id, detail.tracks);
                    ref.invalidate(playlistDetailProvider(widget.playlistId));
                  },
                );
              },
              childCount: detail.tracks.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }
}
