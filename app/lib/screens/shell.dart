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
import '../services/update_service.dart';

class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(updateDismissedProvider)) return const SizedBox.shrink();
    
    final messageAsync = ref.watch(updateMessageProvider);
    return messageAsync.when(
      data: (message) {
        if (message == null || message.isEmpty) return const SizedBox.shrink();
        return Material(
          color: AppColors.accent,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.black),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: () => ref.read(updateDismissedProvider.notifier).state = true,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

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

    Widget content;
    if (library.loading && library.playlists.isEmpty) {
      content = const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    } else if (library.playlists.isNotEmpty) {
      content = Scaffold(
        backgroundColor: AppColors.background,
        body: const LibraryScreen(),
        bottomNavigationBar: MiniPlayerBar(onExpand: () => openNowPlaying(context)),
      );
    } else if (!hasServer) {
      content = const ServerSetupScreen();
    } else {
      content = ImportEmptyScreen(
        onImport: () => _import(context, ref),
        onOpenSettings: () => _openSettings(context),
      );
    }

    return Column(
      children: [
        const UpdateBanner(),
        Expanded(child: content),
      ],
    );
  }
}
