import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/player_provider.dart';
import '../services/local_store.dart';
import '../services/user_prefs_store.dart';
import '../theme/app_theme.dart';
import 'equalizer_bars.dart';

class SwipeableTrackRow extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final bool showFavorite;

  const SwipeableTrackRow({
    super.key,
    required this.track,
    required this.index,
    this.onTap,
    this.onRetry,
    this.onRemove,
    this.showFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final canRetry = track.status == TrackStatus.failed;
    final removeBg = _swipeBg(
      alignment: Alignment.centerRight,
      icon: Icons.delete_outline_rounded,
      label: 'Remove',
      color: AppColors.error,
    );

    return Dismissible(
      key: key ?? ValueKey('swipe-${track.id}'),
      direction: canRetry ? DismissDirection.horizontal : DismissDirection.endToStart,
      background: canRetry
          ? _swipeBg(
              alignment: Alignment.centerLeft,
              icon: Icons.refresh_rounded,
              label: 'Retry',
              color: AppColors.accent,
            )
          : removeBg,
      secondaryBackground: canRetry ? removeBg : null,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (canRetry) {
            HapticFeedback.mediumImpact();
            onRetry?.call();
          }
          return false;
        }
        HapticFeedback.lightImpact();
        return true;
      },
      onDismissed: (_) => onRemove?.call(),
      child: TrackRow(
        track: track,
        index: index,
        showFavorite: showFavorite,
        onTap: onTap,
        onRetry: onRetry,
      ),
    );
  }

  Widget _swipeBg({
    required Alignment alignment,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      color: color.withValues(alpha: 0.18),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ],
          Icon(icon, color: color),
          if (alignment == Alignment.centerLeft) ...[
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class TrackRow extends ConsumerWidget {
  final Track track;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final bool showFavorite;

  const TrackRow({
    super.key,
    required this.track,
    required this.index,
    this.onTap,
    this.onRetry,
    this.showFavorite = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isCurrent = current?.id == track.id;
    final isFavorite = ref.watch(userPrefsProvider.select((p) => p.isFavorite(track.id)));
    final hasLocal = ref.watch(localStoreProvider).hasTrack(track.id);
    final canPlay = hasLocal || track.status == TrackStatus.ready;

    return Material(
      color: isCurrent ? AppColors.surfaceHighlight.withValues(alpha: 0.6) : Colors.transparent,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  if (canPlay) {
                    onTap?.call();
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        track.status == TrackStatus.failed
                            ? 'Download failed — swipe to retry'
                            : 'Not downloaded yet',
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: isCurrent && isPlaying
                            ? const EqualizerBars()
                            : Text(
                                '${index + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isCurrent ? AppColors.accent : AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: track.albumArt != null
                            ? CachedNetworkImage(
                                imageUrl: track.albumArt!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => _artPlaceholder(),
                              )
                            : _artPlaceholder(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
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
            if (showFavorite) FavoriteHeartButton(trackId: track.id, isFavorite: isFavorite),
            if (!hasLocal && track.status != TrackStatus.ready) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _StatusIndicator(status: track.status, onRetry: onRetry),
              ),
            ] else if (hasLocal && track.status != TrackStatus.ready)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 12),
              child: Text(
                track.durationFormatted,
                style: TextStyle(
                  color: isCurrent
                      ? AppColors.textPrimary.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      color: AppColors.surfaceHighlight,
      child: const Icon(Icons.music_note, size: 20, color: AppColors.textMuted),
    );
  }
}

/// Isolated heart so taps never hit the row above/below or start a reorder drag.
class FavoriteHeartButton extends ConsumerWidget {
  final String trackId;
  final bool isFavorite;

  const FavoriteHeartButton({
    super.key,
    required this.trackId,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 40,
      height: 64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(userPrefsProvider.notifier).toggleFavorite(trackId);
          },
          customBorder: const CircleBorder(),
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 22,
            color: isFavorite ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final TrackStatus status;
  final VoidCallback? onRetry;

  const _StatusIndicator({required this.status, this.onRetry});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TrackStatus.ready:
        return const SizedBox.shrink();
      case TrackStatus.downloading:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        );
      case TrackStatus.failed:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.mediumImpact();
            onRetry?.call();
          },
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.error),
          ),
        );
      default:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
        );
    }
  }
}
