import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';

final userPrefsProvider = StateNotifierProvider<UserPrefsNotifier, UserPrefs>((ref) {
  return UserPrefsNotifier();
});

class UserPrefs {
  final Set<String> favoriteIds;
  final List<Track> recentTracks;
  final bool onboardingComplete;
  final bool autoSync;
  final bool crossfade;
  final double playbackSpeed;

  const UserPrefs({
    this.favoriteIds = const {},
    this.recentTracks = const [],
    this.onboardingComplete = false,
    this.autoSync = false,
    this.crossfade = false,
    this.playbackSpeed = 1.0,
  });

  UserPrefs copyWith({
    Set<String>? favoriteIds,
    List<Track>? recentTracks,
    bool? onboardingComplete,
    bool? autoSync,
    bool? crossfade,
    double? playbackSpeed,
  }) {
    return UserPrefs(
      favoriteIds: favoriteIds ?? this.favoriteIds,
      recentTracks: recentTracks ?? this.recentTracks,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      autoSync: autoSync ?? this.autoSync,
      crossfade: crossfade ?? this.crossfade,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  bool isFavorite(String trackId) => favoriteIds.contains(trackId);
}

class UserPrefsNotifier extends StateNotifier<UserPrefs> {
  UserPrefsNotifier() : super(const UserPrefs());

  static const _boxName = 'user_prefs';
  Box<String>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(_boxName);
    state = _load();
  }

  UserPrefs _load() {
    if (_box == null) return const UserPrefs();
    final favorites = _decodeStringList(_box!.get('favorite_ids'));
    final recent = _decodeTracks(_box!.get('recent_tracks'));
    return UserPrefs(
      favoriteIds: favorites.toSet(),
      recentTracks: recent,
      onboardingComplete: _box!.get('onboarding_complete') == 'true',
      autoSync: _box!.get('auto_sync') == 'true',
      crossfade: _box!.get('crossfade') == 'true',
      playbackSpeed: double.tryParse(_box!.get('playback_speed') ?? '') ?? 1.0,
    );
  }

  List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
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
    final next = Set<String>.from(state.favoriteIds);
    if (next.contains(trackId)) {
      next.remove(trackId);
    } else {
      next.add(trackId);
    }
    state = state.copyWith(favoriteIds: next);
    await _persist('favorite_ids', jsonEncode(next.toList()));
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

  Future<void> setPlaybackSpeed(double speed) async {
    await init();
    state = state.copyWith(playbackSpeed: speed);
    await _persist('playback_speed', speed.toString());
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
