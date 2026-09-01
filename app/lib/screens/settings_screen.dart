import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../services/local_store.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _localBytes = 0;
  int _trackCount = 0;
  int _playlistCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final store = ref.read(localStoreProvider);
      final bytes = await store.trackStorageBytes();
      if (mounted) {
        setState(() {
          _localBytes = bytes;
          _trackCount = store.cachedTrackCount;
          _playlistCount = store.getAllPlaylists().length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatBytes(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  Future<void> _clearLocalCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Clear downloaded tracks?'),
        content: const Text('This removes all locally saved audio. Playlists stay in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(localStoreProvider).clearAllTracks();
      ref.read(libraryProvider.notifier).load();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _SectionHeader('Storage'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
            )
          else ...[
            _SettingsTile(
              title: 'Downloaded tracks',
              subtitle: '${_formatBytes(_localBytes)} · $_trackCount tracks · $_playlistCount playlists',
            ),
            ListTile(
              title: const Text('Clear downloaded tracks', style: TextStyle(color: AppColors.error)),
              trailing: const Icon(Icons.delete_outline, color: AppColors.error),
              onTap: _clearLocalCache,
            ),
          ],
          const SizedBox(height: 16),
          _SectionHeader('About'),
          const _SettingsTile(
            title: 'SpotPlayer',
            subtitle: 'v1.0.0',
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SettingsTile({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
