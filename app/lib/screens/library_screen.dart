import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../services/local_store.dart';
import '../services/server_connectivity.dart';
import '../services/user_prefs_store.dart';
import '../theme/app_theme.dart';
import '../widgets/import_sheet.dart';
import '../widgets/playlist_card.dart';
import '../widgets/offline_banner.dart';
import '../widgets/scale_button.dart';
import 'favorites_screen.dart';
import 'listening_stats_screen.dart';
import 'onboarding_screen.dart';
import 'playlist_detail_screen.dart';
import 'search_screen.dart';
import 'server_setup_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showOnboardingIfNeeded(context, ref);
    });
  }

  Future<void> _playRecent(TrackWithPlaylist entry) async {
    final detail = ref.read(localStoreProvider).getPlaylist(entry.playlistId);
    if (detail == null) return;
    final idx = detail.tracks.indexWhere((t) => t.id == entry.track.id);
    await ref.read(playerProvider.notifier).playTracks(
          tracks: detail.tracks,
          startIndex: idx >= 0 ? idx : 0,
          playlistId: detail.id,
          playlistName: detail.name,
          playlistCover: detail.coverUrl,
        );
    if (!mounted) return;
    final err = ref.read(playerProvider).playError;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      ref.read(playerProvider.notifier).clearPlayError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    ref.watch(libraryTickProvider);
    final prefs = ref.watch(userPrefsProvider);
    final favoriteCount = prefs.favoriteIds.length;
    final reachable = ref.watch(serverReachableProvider);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Library'),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 24),
                tooltip: 'Search library',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.insights_rounded, size: 24),
                tooltip: 'Listening stats',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ListeningStatsScreen()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded, size: 24),
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 28),
                tooltip: 'Import playlist',
                onPressed: () async {
                  if (!await ensureServerConfigured(context, ref)) return;
                  if (!await ensureServerReachable(ref)) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Not connected')),
                      );
                    }
                    return;
                  }
                  if (!context.mounted) return;
                  await showImportSheet(context);
                  ref.read(libraryProvider.notifier).load();
                },
              ),
            ],
          ),
          if (!reachable)
            const SliverToBoxAdapter(child: OfflineBanner()),
          if (library.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  library.error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (prefs.recentTracks.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'RECENTLY PLAYED',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: prefs.recentTracks.take(10).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final track = prefs.recentTracks[i];
                    final entry = ref.read(localStoreProvider).getAllTrackEntries().where(
                          (e) => e.track.id == track.id,
                        ).firstOrNull;
                    return ScaleButton(
                      onPressed: entry == null ? null : () => _playRecent(entry),
                      child: SizedBox(
                        width: 220,
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: track.albumArt != null
                                  ? CachedNetworkImage(
                                      imageUrl: track.albumArt!,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 56,
                                      height: 56,
                                      color: AppColors.surfaceHighlight,
                                      child: const Icon(Icons.music_note, color: AppColors.textMuted),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ScaleButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.favorite_rounded, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Liked songs',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '$favoriteCount',
                        style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'PLAYLISTS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final playlist = library.playlists[i];
                  return PlaylistCard(
                    playlist: playlist,
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder<void>(
                          transitionDuration: const Duration(milliseconds: 260),
                          reverseTransitionDuration: const Duration(milliseconds: 220),
                          pageBuilder: (_, __, ___) =>
                              PlaylistDetailScreen(playlistId: playlist.id),
                          transitionsBuilder: (_, animation, __, child) {
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            return FadeTransition(
                              opacity: curved,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero,
                                ).animate(curved),
                                child: child,
                              ),
                            );
                          },
                        ),
                      );
                    },
                    onLongPress: () => _showOptions(context, ref, playlist.id, playlist.name),
                  );
                },
                childCount: library.playlists.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref, String id, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded, color: AppColors.textPrimary),
              title: const Text('Re-sync'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(libraryProvider.notifier).syncPlaylist(id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: const Text('Remove from library', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(libraryProvider.notifier).removePlaylist(id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
