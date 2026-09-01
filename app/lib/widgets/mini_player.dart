import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../screens/now_playing_screen.dart';
import '../theme/app_theme.dart';

class MiniPlayerBar extends ConsumerStatefulWidget {
  final VoidCallback onExpand;

  const MiniPlayerBar({super.key, required this.onExpand});

  @override
  ConsumerState<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends ConsumerState<MiniPlayerBar> {
  double _dragOffset = 0;
  bool _showPrevHint = false;
  bool _showNextHint = false;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-72.0, 72.0);
      _showNextHint = _dragOffset < -24;
      _showPrevHint = _dragOffset > 24;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0;
    final notifier = ref.read(playerProvider.notifier);

    if (_dragOffset < -40 || vx < -400) {
      notifier.next();
      HapticFeedback.mediumImpact();
    } else if (_dragOffset > 40 || vx > 400) {
      notifier.previous();
      HapticFeedback.mediumImpact();
    }

    setState(() {
      _dragOffset = 0;
      _showPrevHint = false;
      _showNextHint = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    if (!player.hasTrack) return const SizedBox.shrink();

    final track = player.currentTrack!;
    final progress = player.duration.inMilliseconds > 0
        ? player.position.inMilliseconds / player.duration.inMilliseconds
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(top: BorderSide(color: AppColors.divider.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: AppColors.accent,
              ),
            ),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onExpand,
                      onHorizontalDragUpdate: _onHorizontalDragUpdate,
                      onHorizontalDragEnd: _onHorizontalDragEnd,
                      behavior: HitTestBehavior.opaque,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_showPrevHint)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Icon(
                                Icons.skip_previous_rounded,
                                color: AppColors.accent.withValues(alpha: 0.55),
                                size: 22,
                              ),
                            ),
                          if (_showNextHint)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Icon(
                                Icons.skip_next_rounded,
                                color: AppColors.accent.withValues(alpha: 0.55),
                                size: 22,
                              ),
                            ),
                          Transform.translate(
                            offset: Offset(_dragOffset, 0),
                            child: Row(
                              children: [
                                Hero(
                                  tag: 'now-playing-art',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: track.albumArt != null
                                        ? CachedNetworkImage(
                                            imageUrl: track.albumArt!,
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 40,
                                            height: 40,
                                            color: AppColors.surfaceHighlight,
                                            child: const Icon(
                                              Icons.music_note,
                                              color: AppColors.textMuted,
                                              size: 20,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        track.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      tooltip: player.shuffle ? 'Shuffle on' : 'Shuffle off',
                      iconSize: 22,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Icon(
                        Icons.shuffle_rounded,
                        color: player.shuffle ? AppColors.accent : AppColors.textMuted,
                      ),
                      onPressed: () => ref.read(playerProvider.notifier).toggleShuffle(),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      tooltip: 'Previous',
                      iconSize: 24,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.skip_previous_rounded, color: AppColors.textPrimary),
                      onPressed: () => ref.read(playerProvider.notifier).previous(),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      tooltip: player.isPlaying ? 'Pause' : 'Play',
                      iconSize: 30,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      icon: Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () => ref.read(playerProvider.notifier).togglePlay(),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      tooltip: 'Next',
                      iconSize: 24,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: const Icon(Icons.skip_next_rounded, color: AppColors.textPrimary),
                      onPressed: () => ref.read(playerProvider.notifier).next(),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => NowPlayingScreen(
        onDismiss: () => Navigator.of(context).pop(),
      ),
    ),
  );
}
