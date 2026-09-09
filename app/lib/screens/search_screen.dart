import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../services/local_store.dart';
import '../services/user_prefs_store.dart';
import '../theme/app_theme.dart';
import '../widgets/track_row.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TrackWithPlaylist> _results() {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return ref
        .read(localStoreProvider)
        .getAllTrackEntries()
        .where((e) =>
            e.track.name.toLowerCase().contains(q) ||
            e.track.artist.toLowerCase().contains(q) ||
            e.playlistName.toLowerCase().contains(q))
        .toList();
  }

  void _play(TrackWithPlaylist entry, List<TrackWithPlaylist> all) {
    final store = ref.read(localStoreProvider);
    final detail = store.getPlaylist(entry.playlistId);
    if (detail == null) return;
    final idx = detail.tracks.indexWhere((t) => t.id == entry.track.id);
    ref.read(playerProvider.notifier).playTracks(
          tracks: detail.tracks,
          startIndex: idx >= 0 ? idx : 0,
          playlistId: detail.id,
          playlistName: detail.name,
          playlistCover: detail.coverUrl,
        );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          decoration: const InputDecoration(
            hintText: 'Search songs, artists, playlists',
            hintStyle: TextStyle(color: AppColors.textMuted),
            border: InputBorder.none,
          ),
        ),
      ),
      body: results.isEmpty
          ? Center(
              child: Text(
                _controller.text.trim().isEmpty
                    ? 'Search your whole library'
                    : 'No matches',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: results.length,
              itemBuilder: (context, i) {
                final entry = results[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (i == 0 || results[i - 1].playlistId != entry.playlistId)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          entry.playlistName,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 64,
                      child: Row(
                        children: [
                          Expanded(
                            child: TrackRow(
                              track: entry.track,
                              index: i,
                              showFavorite: false,
                              onTap: () => _play(entry, results),
                            ),
                          ),
                          FavoriteHeartButton(
                            trackId: entry.track.id,
                            isFavorite: ref.watch(
                              userPrefsProvider.select((p) => p.isFavorite(entry.track.id)),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
