import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../theme/app_theme.dart';

class MiniPlayerBar extends ConsumerWidget {
  final VoidCallback onExpand;

  const MiniPlayerBar({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    if (!player.hasTrack) return const SizedBox.shrink();

    final track = player.currentTrack!;

    return GestureDetector(
      onTap: onExpand,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          border: Border(top: BorderSide(color: AppColors.divider.withValues(alpha: 0.5))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Hero(
                  tag: 'now-playing-art',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: track.albumArt != null
                        ? CachedNetworkImage(
                            imageUrl: track.albumArt!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: AppColors.surfaceHighlight,
                            child: const Icon(Icons.music_note, color: AppColors.textMuted),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                  ),
                  onPressed: () => ref.read(playerProvider.notifier).togglePlay(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 28),
                  onPressed: () => ref.read(playerProvider.notifier).next(),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
