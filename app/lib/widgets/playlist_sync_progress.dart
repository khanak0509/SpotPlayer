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
    ref.watch(libraryTickProvider);
    final total = tracks.length;
    if (total == 0) return const SizedBox.shrink();

    final reachable = ref.watch(serverReachableProvider);
    final store = ref.read(localStoreProvider);
    final saved = store.localSavedCount(tracks);
    final failed = tracks.where((t) => !store.hasTrack(t.id) && t.status == TrackStatus.failed).length;
    final saving = ref.read(trackSyncProvider).activeDownloadCount;
    final pending = total - saved - failed;
    final progress = total == 0 ? 0.0 : saved / total;
    final done = saved + failed >= total && saving == 0;

    if (!reachable && saved < total) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        child: Text(
          saved > 0 ? '$saved / $total on phone' : 'Server offline',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
        ),
      );
    }

    String status;
    if (failed > 0 && pending == 0 && saving == 0) {
      status = '$failed failed';
    } else if (saving > 0) {
      status = 'Saving $saving…';
    } else if (pending > 0) {
      status = 'Preparing…';
    } else if (done && saved == total) {
      status = 'All on phone';
    } else {
      status = '';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: done ? 1.0 : progress.clamp(0.0, 1.0),
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
                '$saved / $total on phone',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (status.isNotEmpty)
                Text(
                  status,
                  style: TextStyle(
                    color: failed > 0 && pending == 0 ? AppColors.error : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
                icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                label: Text(
                  failed == 1 ? 'Retry failed' : 'Retry all failed ($failed)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
