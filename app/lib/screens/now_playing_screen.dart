import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/art_background.dart';
import '../widgets/scale_button.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const NowPlayingScreen({super.key, required this.onDismiss});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _enterController;
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  IconData _repeatIcon(PlayerRepeatMode mode) {
    return switch (mode) {
      PlayerRepeatMode.one => Icons.repeat_one_rounded,
      PlayerRepeatMode.all => Icons.repeat_rounded,
      PlayerRepeatMode.off => Icons.repeat_rounded,
    };
  }

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) {
          return Consumer(
            builder: (_, ref, __) {
              final state = ref.watch(playerProvider);
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Up Next',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollController: scrollController,
                      itemCount: state.queue.length,
                      onReorder: (old, newIdx) {
                        ref.read(playerProvider.notifier).reorderQueue(old, newIdx);
                      },
                      itemBuilder: (_, i) {
                        final track = state.queue[i];
                        final isCurrent = state.currentTrack?.id == track.id;
                        return ListTile(
                          key: ValueKey(track.id),
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle, color: AppColors.textMuted),
                          ),
                          title: Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                              color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            track.artist,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.equalizer, color: AppColors.accent, size: 20)
                              : null,
                          onTap: isCurrent
                              ? null
                              : () {
                                  ref.read(playerProvider.notifier).playTrack(track);
                                  Navigator.pop(ctx);
                                },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final progress = player.duration.inMilliseconds > 0
        ? player.position.inMilliseconds / player.duration.inMilliseconds
        : 0.0;

    return AnimatedBuilder(
      animation: _enterController,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_enterController.value);
        return Transform.translate(
          offset: Offset(0, (1 - t) * 40 + _dragY),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        );
      },
      child: GestureDetector(
        onVerticalDragUpdate: (d) {
          if (d.delta.dy > 0 || _dragY > 0) {
            setState(() => _dragY += d.delta.dy);
          }
        },
        onVerticalDragEnd: (d) {
          if (_dragY > 100 || d.velocity.pixelsPerSecond.dy > 500) {
            widget.onDismiss();
          } else {
            setState(() => _dragY = 0);
          }
        },
        child: Material(
          color: Colors.transparent,
          child: ArtBackground(
            imageUrl: track.albumArt,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                          onPressed: widget.onDismiss,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                player.playlistName ?? 'Now Playing',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Text(
                                'Playing from playlist',
                                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.queue_music_rounded),
                          onPressed: _showQueue,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onHorizontalDragEnd: (d) {
                        if (d.primaryVelocity != null) {
                          if (d.primaryVelocity! < -200) {
                            ref.read(playerProvider.notifier).next();
                          } else if (d.primaryVelocity! > 200) {
                            ref.read(playerProvider.notifier).previous();
                          }
                        }
                      },
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Hero(
                            tag: 'now-playing-art',
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: track.albumArt != null
                                    ? CachedNetworkImage(
                                        imageUrl: track.albumArt!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                      )
                                    : Container(
                                        color: AppColors.surfaceHighlight,
                                        child: const Icon(Icons.music_note, size: 80),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                    child: Column(
                      children: [
                        Text(
                          track.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          track.artist,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            activeTrackColor: AppColors.accent,
                            inactiveTrackColor: AppColors.surfaceHighlight,
                            thumbColor: AppColors.textPrimary,
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0),
                            onChangeStart: (_) {},
                            onChanged: (v) {
                              final pos = Duration(
                                milliseconds: (v * player.duration.inMilliseconds).round(),
                              );
                              ref.read(playerProvider.notifier).seek(pos);
                            },
                            onChangeEnd: (_) {},
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(player.position),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _formatDuration(player.duration),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).toggleShuffle(),
                          child: Icon(
                            Icons.shuffle_rounded,
                            color: player.shuffle ? AppColors.accent : AppColors.textMuted,
                            size: 24,
                          ),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).previous(),
                          child: const Icon(Icons.skip_previous_rounded, size: 36),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).togglePlay(),
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AppColors.accent, AppColors.accentMuted],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(
                              player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 36,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).next(),
                          child: const Icon(Icons.skip_next_rounded, size: 36),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).cycleRepeat(),
                          child: Icon(
                            _repeatIcon(player.repeat),
                            color: player.repeat != PlayerRepeatMode.off
                                ? AppColors.accent
                                : AppColors.textMuted,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
