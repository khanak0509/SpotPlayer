import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store.dart';
import '../services/play_stats_store.dart';
import '../theme/app_theme.dart';

class ListeningStatsScreen extends ConsumerStatefulWidget {
  const ListeningStatsScreen({super.key});

  @override
  ConsumerState<ListeningStatsScreen> createState() => _ListeningStatsScreenState();
}

class _ListeningStatsScreenState extends ConsumerState<ListeningStatsScreen> {
  List<(String id, TrackPlayStats stats, String title, String artist)> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await ref.read(playStatsProvider).all();
    final store = ref.read(localStoreProvider);
    final byId = <String, ({String title, String artist})>{};
    for (final e in store.getAllTrackEntries(uniqueByTrackId: true)) {
      byId[e.track.id] = (title: e.track.name, artist: e.track.artist);
    }
    final rows = stats.entries.map((e) {
      final meta = byId[e.key];
      return (
        e.key,
        e.value,
        meta?.title ?? e.key,
        meta?.artist ?? '',
      );
    }).toList()
      ..sort((a, b) => b.$2.playCount.compareTo(a.$2.playCount));
    if (!mounted) return;
    setState(() {
      _rows = rows.take(40).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('For your ears')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _rows.isEmpty
              ? const Center(
                  child: Text(
                    'Play some music — stats show up here.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
                  itemBuilder: (context, i) {
                    final row = _rows[i];
                    final s = row.$2;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${row.$4} · ${s.playCount} plays · ${s.skipCount} skips',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: Text(
                        '${(s.totalListenMs / 60000).round()}m',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    );
                  },
                ),
    );
  }
}
