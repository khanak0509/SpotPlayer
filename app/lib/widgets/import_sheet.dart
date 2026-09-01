import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/library_provider.dart';
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
  bool _waking = false;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.contains('open.spotify.com/playlist/') ||
        text.contains('spotify.com/playlist/')) {
      _controller.text = text;
    }
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _waking = false;
    });

    final wakeTimer = Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _submitting) setState(() => _waking = true);
    });

    final result = await ref.read(libraryProvider.notifier).importPlaylist(url);
    await wakeTimer;

    if (mounted) {
      setState(() {
        _submitting = false;
        _waking = false;
      });
      if (result != null) {
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
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Import playlist',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a Spotify playlist link',
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
              hintText: 'https://open.spotify.com/playlist/...',
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
                  _waking
                      ? 'Server is waking up, this can take up to a minute…'
                      : 'Resolving playlist…',
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
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.accentMuted],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Import',
                  style: TextStyle(
                    color: Colors.white,
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
  return showModalBottomSheet<PlaylistSummary>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    builder: (_) => const ImportSheet(),
  );
}
