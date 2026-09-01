import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/library_provider.dart';
import 'screens/shell.dart';
import 'services/api.dart';
import 'services/local_store.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const ProviderScope(child: SpotPlayerApp()));
}

class SpotPlayerApp extends ConsumerStatefulWidget {
  const SpotPlayerApp({super.key});

  @override
  ConsumerState<SpotPlayerApp> createState() => _SpotPlayerAppState();
}

class _SpotPlayerAppState extends ConsumerState<SpotPlayerApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(localStoreProvider).init();
      await ref.read(apiProvider).init();
      ref.read(libraryProvider.notifier).load();
    });
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
