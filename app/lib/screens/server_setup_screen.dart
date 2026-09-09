import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/scale_button.dart';

class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = SettingsStore.normalizeServerUrl(_controller.text);
    if (url.isEmpty) {
      setState(() => _error = 'Enter the URL from start.sh');
      return;
    }
    await ref.read(settingsStoreProvider).setServerUrl(url);
    ref.read(serverUrlProvider.notifier).state = url;
    setState(() => _error = null);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.dns_outlined, size: 56, color: AppColors.accent),
              const SizedBox(height: 24),
              Text(
                'Connect server',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Run start.sh on your computer, then paste the URL it prints.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: SettingsStore.serverUrlExample,
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  errorText: _error,
                  filled: true,
                  fillColor: AppColors.surfaceHighlight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              ScaleButton(
                onPressed: _save,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      color: AppColors.background,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

bool hasServerConfigured(WidgetRef ref) {
  return ref.watch(serverUrlProvider).isNotEmpty;
}

Future<bool> ensureServerConfigured(BuildContext context, WidgetRef ref) async {
  if (ref.read(settingsStoreProvider).hasServerUrl) return true;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ServerSetupScreen()),
  );
  return ref.read(settingsStoreProvider).hasServerUrl;
}
