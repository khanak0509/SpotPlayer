import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class SyncKeepAlive {
  static bool _ready = false;
  static bool _running = false;

  static Future<void> update(bool syncing) async {
    if (!Platform.isAndroid || syncing == _running) return;
    _running = syncing;
    try {
      if (syncing) {
        _init();
        final result = await FlutterForegroundTask.startService(
          serviceId: 412,
          serviceTypes: [ForegroundServiceTypes.dataSync],
          notificationTitle: 'SpotPlayer',
          notificationText: 'Syncing songs to your phone',
        );
        if (result is ServiceRequestFailure) _running = false;
      } else if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      _running = false;
    }
  }

  static void _init() {
    if (_ready) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'com.spotplayer.spotplayer.sync',
        channelName: 'Syncing',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: true,
      ),
    );
    _ready = true;
  }
}
