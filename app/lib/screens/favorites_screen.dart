import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../services/local_store.dart';
import '../services/user_prefs_store.dart';
import '../theme/app_theme.dart';
import '../widgets/track_row.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(userPrefsProvider).favoriteIds;
    final liked = ref.read(localStoreProvider).getLikedTracks(favorites);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Liked songs')),
      body: liked.isEmpty
          ? const Center(
              child: Text(
                'Tap the heart on any track to save it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: liked.length,
              itemExtent: 64,
              itemBuilder: (context, i) {
                final track = liked[i];
                final isFavorite = ref.watch(userPrefsProvider.select((p) => p.isFavorite(track.id)));
                return SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      Expanded(
                        child: TrackRow(
                          track: track,
                          index: i,
                          showFavorite: false,
                          onTap: () async {
                            await ref.read(playerProvider.notifier).playTracks(
                                  tracks: liked,
                                  startIndex: i,
                                  playlistId: 'liked',
                                  playlistName: 'Liked songs',
                                );
                            if (!context.mounted) return;
                            final err = ref.read(playerProvider).playError;
                            if (err != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(err)),
                              );
                              ref.read(playerProvider.notifier).clearPlayError();
                            }
                          },
                        ),
                      ),
                      FavoriteHeartButton(trackId: track.id, isFavorite: isFavorite),
                      const SizedBox(width: 4),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
