import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/library_provider.dart';
import '../services/local_store.dart';
import '../services/server_connectivity.dart';
import '../theme/app_theme.dart';

class PlaylistSyncProgress extends ConsumerWidget {
  final List<Track> tracks;
  final String? playlistId;

  const PlaylistSyncProgress({
    super.key,
    required this.tracks,
    this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = tracks.length;
    if (total == 0) return const SizedBox.shrink();

    final reachable = ref.watch(serverReachableProvider);
    final store = ref.read(localStoreProvider);
    final saved = store.localSavedCount(tracks);
    final failed = tracks.where((t) => !store.hasTrack(t.id) && t.status == TrackStatus.failed).length;

    if (!reachable && saved < total) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        child: Text(
          saved > 0
              ? '$saved / $total saved offline · start backend to download rest'
              : 'Start backend with start.sh to download tracks',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
        ),
      );
    }

    final ready = tracks.where((t) => t.status == TrackStatus.ready).length;
    final downloading = tracks.where((t) => t.status == TrackStatus.downloading).length;
    final queued = tracks.where((t) =>
        t.status == TrackStatus.queued || t.status == TrackStatus.resolving).length;
    final progress = saved / total;
    final done = saved + failed >= total && downloading == 0 && queued == 0;

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
              color: failed > 0 && saved == 0
                  ? AppColors.error.withValues(alpha: 0.7)
                  : AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$saved / $total downloaded',
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
                  style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w500),
                )
              else if (downloading > 0)
                Text(
                  '$downloading downloading',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (queued > 0)
                Text(
                  '$queued queued · $ready ready on server',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (saved == total)
                const Text(
                  'All downloaded',
                  style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w500),
                ),
            ],
          ),
          if (failed > 0 && playlistId != null && reachable) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  ref.read(libraryProvider.notifier).retryFailedTracks(playlistId!);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.accent),
                label: Text(
                  'Retry $failed failed',
                  style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
