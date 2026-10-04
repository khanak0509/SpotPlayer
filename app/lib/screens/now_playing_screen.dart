import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/player_provider.dart';
import '../services/user_prefs_store.dart';
import '../theme/app_theme.dart';
import '../widgets/art_background.dart';
import '../widgets/scale_button.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDismiss;

  const NowPlayingScreen({super.key, required this.onDismiss});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${m.padLeft(2, '0')}:$s';
  }
  return '$m:$s';
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  double _dragY = 0;

  IconData _repeatIcon(PlayerRepeatMode mode) {
    return switch (mode) {
      PlayerRepeatMode.one => Icons.repeat_one_rounded,
      PlayerRepeatMode.all => Icons.repeat_rounded,
      PlayerRepeatMode.off => Icons.repeat_rounded,
    };
  }

  void _showSleepTimer() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sleep timer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final mins in [15, 30, 60])
              ListTile(
                title: Text('$mins minutes'),
                onTap: () {
                  ref.read(playerProvider.notifier).setSleepTimer(Duration(minutes: mins));
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              title: const Text('End of this track'),
              onTap: () {
                ref.read(playerProvider.notifier).setSleepTimer(
                      Duration.zero,
                      afterCurrentTrack: true,
                    );
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('Off', style: TextStyle(color: AppColors.error)),
              onTap: () {
                ref.read(playerProvider.notifier).setSleepTimer(Duration.zero);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
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
              final queue = ref.watch(playerProvider.select((s) => s.queue));
              final currentId = ref.watch(playerProvider.select((s) => s.currentTrack?.id));
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
                      itemCount: queue.length,
                      onReorderItem: (old, newIdx) {
                        ref.read(playerProvider.notifier).reorderQueue(old, newIdx);
                      },
                      itemBuilder: (_, i) {
                        final track = queue[i];
                        final isCurrent = currentId == track.id;
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
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.equalizer, color: AppColors.accent, size: 20)
                              : null,
                          onTap: isCurrent
                              ? null
                              : () {
                                  ref.read(playerProvider.notifier).skipToIndex(i);
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
    final track = ref.watch(playerProvider.select((s) => s.currentTrack));
    if (track == null) return const SizedBox.shrink();
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffle));
    final repeat = ref.watch(playerProvider.select((s) => s.repeat));
    final playbackSpeed = ref.watch(playerProvider.select((s) => s.playbackSpeed));
    final playlistName = ref.watch(playerProvider.select((s) => s.playlistName));

    return Transform.translate(
      offset: Offset(0, _dragY),
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
                                playlistName ?? 'Now Playing',
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
                  const _SleepLabel(),
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
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 28,
                              splashRadius: 24,
                              icon: Icon(
                                ref.watch(userPrefsProvider.select((p) => p.isFavorite(track.id)))
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: AppColors.accent,
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ref.read(userPrefsProvider.notifier).toggleFavorite(track.id);
                              },
                            ),
                            TextButton(
                              onPressed: () =>
                                  ref.read(playerProvider.notifier).cyclePlaybackSpeed(),
                              child: Text(
                                '${playbackSpeed}x',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.bedtime_outlined, color: AppColors.textSecondary),
                              onPressed: _showSleepTimer,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: _SeekBar(),
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
                            color: shuffle ? AppColors.accent : AppColors.textMuted,
                            size: 24,
                          ),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).previous(),
                          child: const Icon(Icons.skip_previous_rounded, size: 36),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).togglePlay(),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 44,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).next(),
                          child: const Icon(Icons.skip_next_rounded, size: 36),
                        ),
                        ScaleButton(
                          onPressed: () => ref.read(playerProvider.notifier).cycleRepeat(),
                          child: Icon(
                            _repeatIcon(repeat),
                            color: repeat != PlayerRepeatMode.off
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

class _SleepLabel extends ConsumerWidget {
  const _SleepLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleepEndsAt = ref.watch(playerProvider.select((s) => s.sleepEndsAt));
    if (sleepEndsAt == null) return const SizedBox.shrink();
    ref.watch(playerProvider.select((s) => s.position.inSeconds));
    final left = sleepEndsAt.difference(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        'Sleep in ${_formatDuration(left.isNegative ? Duration.zero : left)}',
        style: const TextStyle(color: AppColors.accent, fontSize: 12),
      ),
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar();

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  static const _timeStyle = TextStyle(
    color: AppColors.textMuted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playerProvider.select((s) => s.position));
    final duration = ref.watch(playerProvider.select((s) => s.duration));
    final totalMs = duration.inMilliseconds;
    final live = totalMs > 0 ? position.inMilliseconds / totalMs : 0.0;
    final value = (_dragValue ?? live).clamp(0.0, 1.0);
    final shown = _dragValue != null ? Duration(milliseconds: (value * totalMs).round()) : position;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: _dragValue != null ? 8 : 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.surfaceHighlight,
            thumbColor: AppColors.textPrimary,
          ),
          child: Slider(
            value: value,
            onChangeStart: totalMs > 0 ? (v) => setState(() => _dragValue = v) : null,
            onChanged: totalMs > 0 ? (v) => setState(() => _dragValue = v) : null,
            onChangeEnd: totalMs > 0
                ? (v) async {
                    HapticFeedback.selectionClick();
                    await ref
                        .read(playerProvider.notifier)
                        .seek(Duration(milliseconds: (v * totalMs).round()));
                    if (mounted) setState(() => _dragValue = null);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(shown), style: _timeStyle),
              Text(_formatDuration(duration), style: _timeStyle),
            ],
          ),
        ),
      ],
    );
  }
}
