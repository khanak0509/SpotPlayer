import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'equalizer_bars.dart';

class SwipeableTrackRow extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  const SwipeableTrackRow({
    super.key,
    required this.track,
    required this.index,
    this.onTap,
    this.onRetry,
    this.onRemove,
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

  const TrackRow({
    super.key,
    required this.track,
    required this.index,
    this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isCurrent = current?.id == track.id;

    return Material(
      color: isCurrent ? AppColors.surfaceHighlight.withValues(alpha: 0.6) : Colors.transparent,
      child: InkWell(
        onTap: track.status == TrackStatus.ready ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                          fontWeight: FontWeight.w500,
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
                        errorWidget: (_, __, ___) => _artPlaceholder(),
                      )
                    : _artPlaceholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
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
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (track.status != TrackStatus.ready) ...[
                _StatusIndicator(
                  status: track.status,
                  onRetry: onRetry,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                track.durationFormatted,
                style: TextStyle(
                  color: isCurrent
                      ? AppColors.textPrimary.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
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
          onTap: () {
            HapticFeedback.mediumImpact();
            onRetry?.call();
          },
          child: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.error),
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
