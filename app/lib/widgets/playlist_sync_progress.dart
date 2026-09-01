import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class PlaylistSyncProgress extends StatelessWidget {
  final List<Track> tracks;

  const PlaylistSyncProgress({super.key, required this.tracks});

  @override
  Widget build(BuildContext context) {
    final total = tracks.length;
    if (total == 0) return const SizedBox.shrink();

    final ready = tracks.where((t) => t.status == TrackStatus.ready).length;
    final failed = tracks.where((t) => t.status == TrackStatus.failed).length;
    final active = tracks.where((t) =>
        t.status == TrackStatus.downloading ||
        t.status == TrackStatus.queued ||
        t.status == TrackStatus.resolving).length;
    final progress = ready / total;
    final done = ready + failed >= total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: done ? 1.0 : progress.clamp(0.02, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.surfaceHighlight,
              color: failed > 0 && ready == 0
                  ? AppColors.error.withValues(alpha: 0.7)
                  : AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$ready / $total saved',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (failed > 0)
                Text(
                  '$failed failed',
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                )
              else if (active > 0)
                Text(
                  'Downloading…',
                  style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.9), fontSize: 12),
                )
              else if (ready == total)
                const Text(
                  'All ready',
                  style: TextStyle(color: AppColors.success, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
