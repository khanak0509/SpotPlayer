import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';

final playbackSessionProvider = Provider((ref) => PlaybackSessionStore());

class PlaybackSession {
  final List<Track> queue;
  final List<Track> sourceOrder;
  final int currentIndex;
  final int positionMs;
  final bool shuffle;
  final PlayerRepeatMode repeat;
  final String? playlistId;
  final String? playlistName;
  final String? playlistCover;

  const PlaybackSession({
    this.queue = const [],
    this.sourceOrder = const [],
    this.currentIndex = 0,
    this.positionMs = 0,
    this.shuffle = false,
    this.repeat = PlayerRepeatMode.off,
    this.playlistId,
    this.playlistName,
    this.playlistCover,
  });

  bool get isEmpty => queue.isEmpty;

  Map<String, dynamic> toJson() => {
        'queue': queue.map((t) => t.toJson()).toList(),
        'source_order': sourceOrder.map((t) => t.toJson()).toList(),
        'current_index': currentIndex,
        'position_ms': positionMs,
        'shuffle': shuffle,
        'repeat': repeat.name,
        'playlist_id': playlistId,
        'playlist_name': playlistName,
        'playlist_cover': playlistCover,
      };

  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    List<Track> parseTracks(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final repeatName = json['repeat'] as String? ?? 'off';
    final repeat = PlayerRepeatMode.values.firstWhere(
      (m) => m.name == repeatName,
      orElse: () => PlayerRepeatMode.off,
    );

    return PlaybackSession(
      queue: parseTracks(json['queue']),
      sourceOrder: parseTracks(json['source_order']),
      currentIndex: json['current_index'] as int? ?? 0,
      positionMs: json['position_ms'] as int? ?? 0,
      shuffle: json['shuffle'] as bool? ?? false,
      repeat: repeat,
      playlistId: json['playlist_id'] as String?,
      playlistName: json['playlist_name'] as String?,
      playlistCover: json['playlist_cover'] as String?,
    );
  }
}

class PlaybackSessionStore {
  static const _boxName = 'playback_session';
  static const _key = 'session';
  Box<String>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  Future<PlaybackSession?> load() async {
    await init();
    final raw = _box!.get(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PlaybackSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PlaybackSession session) async {
    await init();
    if (session.isEmpty) {
      await clear();
      return;
    }
    await _box!.put(_key, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    await init();
    await _box!.delete(_key);
  }
}
