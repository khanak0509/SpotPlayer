import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'equalizer_bars.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: isCurrent && isPlaying
                    ? const EqualizerBars()
                    : Text(
                        '${index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isCurrent ? AppColors.accent : AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
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
              const SizedBox(width: 8),
              _StatusIndicator(
                status: track.status,
                onRetry: onRetry,
              ),
              const SizedBox(width: 8),
              Text(
                track.durationFormatted,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
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
        return const Icon(Icons.check_circle, size: 16, color: AppColors.success);
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
