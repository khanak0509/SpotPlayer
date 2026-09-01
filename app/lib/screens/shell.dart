import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/import_sheet.dart';
import '../widgets/mini_player.dart';
import 'import_empty_screen.dart';
import 'library_screen.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final result = await showImportSheet(context);
    if (result != null && context.mounted) {
      ref.read(libraryProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);

    if (library.loading && library.playlists.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    if (library.isEmpty) {
      return ImportEmptyScreen(onImport: () => _import(context, ref));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: const LibraryScreen(),
      bottomNavigationBar: MiniPlayerBar(onExpand: () => openNowPlaying(context)),
    );
  }
}
