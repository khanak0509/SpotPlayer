import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/import_sheet.dart';
import '../widgets/playlist_card.dart';
import 'playlist_detail_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Library'),
            actions: [
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
                  await showImportSheet(context);
                  ref.read(libraryProvider.notifier).load();
                },
              ),
            ],
          ),
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
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
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
