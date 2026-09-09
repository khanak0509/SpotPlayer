import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../models/models.dart';

final widgetServiceProvider = Provider((ref) => WidgetService());

class WidgetService {
  static const _androidWidgetName = 'SpotPlayerWidget';

  Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId('group.com.spotplayer.spotplayer');
      // Controls are wired in Kotlin via MediaButtonReceiver (play/pause/next/prev).
      await HomeWidget.registerInteractivityCallback(_backgroundCallback);
    } catch (_) {}
  }

  Future<void> updateNowPlaying(Track? track, {bool isPlaying = false}) async {
    try {
      await HomeWidget.saveWidgetData<String>('title', track?.name ?? 'SpotPlayer');
      await HomeWidget.saveWidgetData<String>('artist', track?.artist ?? 'Tap to open');
      await HomeWidget.saveWidgetData<bool>('is_playing', isPlaying);
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
        iOSName: _androidWidgetName,
      );
    } catch (_) {}
  }

  @pragma('vm:entry-point')
  static Future<void> _backgroundCallback(Uri? uri) async {}
}
