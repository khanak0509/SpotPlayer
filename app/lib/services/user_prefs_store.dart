import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';

final userPrefsProvider = StateNotifierProvider<UserPrefsNotifier, UserPrefs>((ref) {
  return UserPrefsNotifier();
});

class UserPrefs {
  final Map<String, int> favoriteLikedAt;
  final List<Track> recentTracks;
  final bool onboardingComplete;
  final bool autoSync;
  final bool crossfade;
  final bool remindersEnabled;
  final double playbackSpeed;
  final int lastContinueNotifMs;

  const UserPrefs({
    this.favoriteLikedAt = const {},
    this.recentTracks = const [],
    this.onboardingComplete = false,
    this.autoSync = false,
    this.crossfade = false,
    this.remindersEnabled = true,
    this.playbackSpeed = 1.0,
    this.lastContinueNotifMs = 0,
  });

  Set<String> get favoriteIds => favoriteLikedAt.keys.toSet();

  UserPrefs copyWith({
    Map<String, int>? favoriteLikedAt,
    List<Track>? recentTracks,
    bool? onboardingComplete,
    bool? autoSync,
    bool? crossfade,
    bool? remindersEnabled,
    double? playbackSpeed,
    int? lastContinueNotifMs,
  }) {
    return UserPrefs(
      favoriteLikedAt: favoriteLikedAt ?? this.favoriteLikedAt,
      recentTracks: recentTracks ?? this.recentTracks,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      autoSync: autoSync ?? this.autoSync,
      crossfade: crossfade ?? this.crossfade,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      lastContinueNotifMs: lastContinueNotifMs ?? this.lastContinueNotifMs,
    );
  }

  bool isFavorite(String trackId) => favoriteLikedAt.containsKey(trackId);
}

class UserPrefsNotifier extends StateNotifier<UserPrefs> {
  UserPrefsNotifier() : super(const UserPrefs());

  static const _boxName = 'user_prefs';
  Box<String>? _box;
  Future<void>? _opening;

  Future<void> init() {
    return _opening ??= () async {
      _box = await Hive.openBox<String>(_boxName);
      state = _load();
    }();
  }

  UserPrefs _load() {
    if (_box == null) return const UserPrefs();
    return UserPrefs(
      favoriteLikedAt: _decodeFavorites(_box!.get('favorite_ids')),
      recentTracks: _decodeTracks(_box!.get('recent_tracks')),
      onboardingComplete: _box!.get('onboarding_complete') == 'true',
      autoSync: _box!.get('auto_sync') == 'true',
      crossfade: _box!.get('crossfade') == 'true',
      remindersEnabled: _box!.get('reminders_enabled') != 'false',
      playbackSpeed: double.tryParse(_box!.get('playback_speed') ?? '') ?? 1.0,
      lastContinueNotifMs: int.tryParse(_box!.get('last_continue_notif_ms') ?? '') ?? 0,
    );
  }

  Map<String, int> _decodeFavorites(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
      if (decoded is List) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final map = <String, int>{
          for (final id in decoded.cast<String>()) id: now,
        };
        unawaitedPersistFavorites(map);
        return map;
      }
    } catch (_) {}
    return {};
  }

  void unawaitedPersistFavorites(Map<String, int> map) {
    Future.microtask(() => _persist('favorite_ids', jsonEncode(map)));
  }

  List<Track> _decodeTracks(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist(String key, String value) async {
    await init();
    await _box!.put(key, value);
  }

  Future<void> toggleFavorite(String trackId) async {
    await init();
    final next = Map<String, int>.from(state.favoriteLikedAt);
    if (next.containsKey(trackId)) {
      next.remove(trackId);
    } else {
      next[trackId] = DateTime.now().millisecondsSinceEpoch;
    }
    state = state.copyWith(favoriteLikedAt: next);
    await _persist('favorite_ids', jsonEncode(next));
  }

  Future<void> addRecentTrack(Track track) async {
    await init();
    final list = [track, ...state.recentTracks.where((t) => t.id != track.id)].take(20).toList();
    state = state.copyWith(recentTracks: list);
    await _persist('recent_tracks', jsonEncode(list.map((t) => t.toJson()).toList()));
  }

  Future<void> setOnboardingComplete(bool value) async {
    await init();
    state = state.copyWith(onboardingComplete: value);
    await _persist('onboarding_complete', value.toString());
  }

  Future<void> setAutoSync(bool value) async {
    await init();
    state = state.copyWith(autoSync: value);
    await _persist('auto_sync', value.toString());
  }

  Future<void> setCrossfade(bool value) async {
    await init();
    state = state.copyWith(crossfade: value);
    await _persist('crossfade', value.toString());
  }

  Future<void> setRemindersEnabled(bool value) async {
    await init();
    state = state.copyWith(remindersEnabled: value);
    await _persist('reminders_enabled', value.toString());
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await init();
    state = state.copyWith(playbackSpeed: speed);
    await _persist('playback_speed', speed.toString());
  }

  Future<void> markContinueListeningNotifShown() async {
    await init();
    final now = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(lastContinueNotifMs: now);
    await _persist('last_continue_notif_ms', now.toString());
  }
}

class TrackWithPlaylist {
  final Track track;
  final String playlistId;
  final String playlistName;

  TrackWithPlaylist({
    required this.track,
    required this.playlistId,
    required this.playlistName,
  });
}
