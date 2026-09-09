import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

String bootstrapServerUrl = '';

final settingsStoreProvider = Provider((ref) => SettingsStore());

final serverUrlProvider = StateProvider<String>((ref) => bootstrapServerUrl);

class SettingsStore {
  static const serverUrlExample = 'http://192.168.1.42:8000/api';
  static const _boxName = 'settings';
  static const _serverUrlKey = 'server_url';

  Box<String>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  String get serverUrl => _box?.get(_serverUrlKey)?.trim() ?? '';

  bool get hasServerUrl => serverUrl.isNotEmpty;

  Future<void> setServerUrl(String url) async {
    await init();
    final normalized = normalizeServerUrl(url);
    if (normalized.isEmpty) {
      await _box!.delete(_serverUrlKey);
    } else {
      await _box!.put(_serverUrlKey, normalized);
    }
  }

  static String normalizeServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/api')) {
      url = '$url/api';
    }
    return url;
  }
}
