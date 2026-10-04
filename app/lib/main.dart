import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'screens/shell.dart';
import 'services/local_store.dart';
import 'services/notification_service.dart';
import 'services/playback_session_store.dart';
import 'services/play_stats_store.dart';
import 'services/server_connectivity.dart';
import 'services/settings_store.dart' show bootstrapServerUrl, settingsStoreProvider, serverUrlProvider;
import 'services/user_prefs_store.dart';
import 'services/widget_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.spotplayer.spotplayer.audio',
    androidNotificationChannelName: 'SpotPlayer',
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
    androidShowNotificationBadge: true,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();
  final settingsBox = await Hive.openBox<String>('settings');
  bootstrapServerUrl = settingsBox.get('server_url')?.trim() ?? '';

  runApp(const ProviderScope(child: SpotPlayerApp()));
}

class SpotPlayerApp extends ConsumerStatefulWidget {
  const SpotPlayerApp({super.key});

  @override
  ConsumerState<SpotPlayerApp> createState() => _SpotPlayerAppState();
}

class _SpotPlayerAppState extends ConsumerState<SpotPlayerApp> with WidgetsBindingObserver {
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await ref.read(localStoreProvider).init();
    await ref.read(userPrefsProvider.notifier).init();
    await ref.read(playbackSessionProvider).init();
    await ref.read(playStatsProvider).init();
    await ref.read(settingsStoreProvider).init();
    ref.read(serverUrlProvider.notifier).state =
        ref.read(settingsStoreProvider).serverUrl.isNotEmpty
            ? ref.read(settingsStoreProvider).serverUrl
            : bootstrapServerUrl;
    await ref.read(widgetServiceProvider).init();
    await ref.read(notificationServiceProvider).init();
    await ref.read(serverReachableProvider.notifier).refresh();
    await ref.read(libraryProvider.notifier).load();
    await ref.read(playerProvider.notifier).restoreSession();
    await _maybeContinueListeningReminder();
    if (ref.read(serverReachableProvider)) {
      ref.read(libraryProvider.notifier).autoSyncAllIfEnabled();
    }
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      ref.read(serverReachableProvider.notifier).refresh();
    });
  }

  Future<void> _maybeContinueListeningReminder() async {
    final session = await ref.read(playbackSessionProvider).load();
    if (session == null || session.isEmpty) return;
    final ended = await ref.read(playbackSessionProvider).lastSessionEndedAt();
    if (ended == null) return;
    final quiet = DateTime.now().difference(ended);
    if (quiet < const Duration(hours: 24)) return;
    final lastShown = ref.read(userPrefsProvider).lastContinueNotifMs;
    if (lastShown > 0) {
      final shownAt = DateTime.fromMillisecondsSinceEpoch(lastShown);
      if (DateTime.now().difference(shownAt) < const Duration(hours: 24)) return;
    }
    await ref.read(notificationServiceProvider).notifyContinueListening();
    await ref.read(userPrefsProvider.notifier).markContinueListeningNotifShown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeContinueListeningReminder();
      ref.read(serverReachableProvider.notifier).refresh().then((up) {
        if (up) {
          ref.read(libraryProvider.notifier).autoSyncAllIfEnabled();
          ref.read(libraryProvider.notifier).load();
        }
      });
    } else if (state == AppLifecycleState.paused) {
      unawaited(ref.read(playbackSessionProvider).touchEndedAt());
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpotPlayer',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
  }
}
