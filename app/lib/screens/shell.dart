import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/import_sheet.dart';
import '../widgets/mini_player.dart';
import 'import_empty_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;
  bool _showFullPlayer = false;

  void _openFullPlayer() => setState(() => _showFullPlayer = true);
  void _closeFullPlayer() => setState(() => _showFullPlayer = false);

  Future<void> _importFromEmpty() async {
    final result = await showImportSheet(context);
    if (result != null && mounted) {
      ref.read(libraryProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);

    if (library.loading && library.playlists.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    if (library.isEmpty) {
      return ImportEmptyScreen(onImport: _importFromEmpty);
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          body: IndexedStack(
            index: _tab,
            children: const [
              LibraryScreen(),
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MiniPlayerBar(onExpand: _openFullPlayer),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        _TabItem(
                          icon: Icons.library_music_rounded,
                          label: 'Library',
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                        _TabItem(
                          icon: Icons.settings_rounded,
                          label: 'Settings',
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showFullPlayer)
          NowPlayingScreen(onDismiss: _closeFullPlayer),
      ],
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: selected ? AppColors.accent : AppColors.textMuted),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
