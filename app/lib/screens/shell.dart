import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../services/server_connectivity.dart';
import '../theme/app_theme.dart';
import '../widgets/import_sheet.dart';
import '../widgets/mini_player.dart';
import 'import_empty_screen.dart';
import 'library_screen.dart';
import 'server_setup_screen.dart';
import 'settings_screen.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
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
    final result = await showImportSheet(context);
    if (result != null && context.mounted) {
      ref.read(libraryProvider.notifier).load();
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final hasServer = hasServerConfigured(ref);

    if (library.loading && library.playlists.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    // Offline-first: if music is already on the phone, show library even without server URL.
    if (library.playlists.isNotEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const LibraryScreen(),
        bottomNavigationBar: MiniPlayerBar(onExpand: () => openNowPlaying(context)),
      );
    }

    if (!hasServer) {
      return const ServerSetupScreen();
    }

    return ImportEmptyScreen(
      onImport: () => _import(context, ref),
      onOpenSettings: () => _openSettings(context),
    );
  }
}
