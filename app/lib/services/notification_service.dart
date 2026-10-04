import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'user_prefs_store.dart';

final notificationServiceProvider = Provider((ref) => NotificationService(ref));

class NotificationService {
  NotificationService(this.ref);

  final Ref ref;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'spotplayer.tips';
  static const _channelName = 'SpotPlayer tips';

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Download finished and listening reminders',
        importance: Importance.defaultImportance,
      ),
    );
    _ready = true;
  }

  bool get _enabled => ref.read(userPrefsProvider).remindersEnabled;

  Future<void> notifyDownloadBatchFinished(String playlistName, int count) async {
    if (!_enabled || count <= 0) return;
    await init();
    await _plugin.show(
      1001,
      'Downloads ready',
      count == 1
          ? '1 track saved in $playlistName'
          : '$count tracks saved in $playlistName',
      _details(),
    );
  }

  Future<void> notifyContinueListening() async {
    if (!_enabled) return;
    await init();
    await _plugin.show(
      1002,
      'Continue listening',
      'Pick up where you left off',
      _details(),
    );
  }

  Future<void> notifySleepTimerEnded() async {
    if (!_enabled) return;
    await init();
    await _plugin.show(
      1003,
      'Sleep timer',
      'Playback paused',
      _details(),
    );
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Download finished and listening reminders',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
  }
}
