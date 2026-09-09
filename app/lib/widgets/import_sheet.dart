import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/library_provider.dart';
import '../services/settings_store.dart';
import '../theme/app_theme.dart';
import 'scale_button.dart';

class ImportSheet extends ConsumerStatefulWidget {
  const ImportSheet({super.key});

  @override
  ConsumerState<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<ImportSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _submitting) return;

    if (!ref.read(settingsStoreProvider).hasServerUrl) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _submitting = true);

    final result = await ref.read(libraryProvider.notifier).importPlaylist(url);

    if (mounted) {
      setState(() => _submitting = false);
      if (result != null) {
        _controller.clear();
        Navigator.pop(context, result);
      } else {
        final err = ref.read(libraryProvider).error;
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err.length > 120 ? '${err.substring(0, 120)}…' : err)),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Import from Spotify',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: _submitting ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Paste a playlist, album, or track link',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_submitting,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'https://open.spotify.com/playlist/…',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceHighlight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_submitting) ...[
            const SizedBox(height: 20),
            Column(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
                const SizedBox(height: 12),
                Text(
                  'Importing…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 16),
            ScaleButton(
              onPressed: _submit,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Import',
                  style: TextStyle(
                    color: AppColors.background,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<PlaylistSummary?> showImportSheet(BuildContext context) {
  return showDialog<PlaylistSummary>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (_) => Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: const ImportSheet(),
    ),
  );
}
