import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/user_prefs_store.dart';
import '../theme/app_theme.dart';
import '../widgets/scale_button.dart';

Future<void> showOnboardingIfNeeded(BuildContext context, WidgetRef ref) async {
  if (ref.read(userPrefsProvider).onboardingComplete) return;
  await showOnboardingTips(context);
  await ref.read(userPrefsProvider.notifier).setOnboardingComplete(true);
}

Future<void> showOnboardingTips(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    builder: (ctx) => const _OnboardingSheet(),
  );
}

class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet();

  static const _steps = [
    (Icons.dns_outlined, 'Start server', 'Run start.sh (Mac/Linux) or start.bat (Windows).'),
    (Icons.link_rounded, 'Paste URL', 'Copy the URL it prints into Settings → Server.'),
    (Icons.queue_music_rounded, 'Import from Spotify', 'Paste a playlist, album, or track link to download.'),
    (Icons.offline_bolt_rounded, 'Play offline', 'After import, your music works without the server.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
              'How SpotPlayer works',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            for (final step in _steps) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(step.$1, color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          step.$3,
                          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            ScaleButton(
              onPressed: () => Navigator.pop(context),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Got it',
                  style: TextStyle(
                    color: AppColors.background,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
