import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final playStatsProvider = Provider((ref) => PlayStatsService());

class TrackPlayStats {
  final int playCount;
  final int skipCount;
  final int lastPlayedMs;
  final int totalListenMs;

  const TrackPlayStats({
    this.playCount = 0,
    this.skipCount = 0,
    this.lastPlayedMs = 0,
    this.totalListenMs = 0,
  });

  double get skipRatio {
    final events = playCount + skipCount;
    if (events == 0) return 0;
    return skipCount / events;
  }

  TrackPlayStats copyWith({
    int? playCount,
    int? skipCount,
    int? lastPlayedMs,
    int? totalListenMs,
  }) {
    return TrackPlayStats(
      playCount: playCount ?? this.playCount,
      skipCount: skipCount ?? this.skipCount,
      lastPlayedMs: lastPlayedMs ?? this.lastPlayedMs,
      totalListenMs: totalListenMs ?? this.totalListenMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'playCount': playCount,
        'skipCount': skipCount,
        'lastPlayedMs': lastPlayedMs,
        'totalListenMs': totalListenMs,
      };

  factory TrackPlayStats.fromJson(Map<String, dynamic> json) {
    return TrackPlayStats(
      playCount: json['playCount'] as int? ?? 0,
      skipCount: json['skipCount'] as int? ?? 0,
      lastPlayedMs: json['lastPlayedMs'] as int? ?? 0,
      totalListenMs: json['totalListenMs'] as int? ?? 0,
    );
  }
}

class PlayStatsService {
  static const _boxName = 'play_stats';
  Box<String>? _box;

  Duration _listenAccum = Duration.zero;
  Duration? _lastPos;
  String? _activeTrackId;
  bool _sawCompleted = false;
  Duration _trackListenWall = Duration.zero;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  Future<TrackPlayStats> get(String trackId) async {
    await init();
    final raw = _box!.get(trackId);
    if (raw == null || raw.isEmpty) return const TrackPlayStats();
    try {
      return TrackPlayStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const TrackPlayStats();
    }
  }

  Future<Map<String, TrackPlayStats>> all() async {
    await init();
    final out = <String, TrackPlayStats>{};
    for (final key in _box!.keys) {
      final id = key as String;
      out[id] = await get(id);
    }
    return out;
  }

  Future<void> _put(String trackId, TrackPlayStats stats) async {
    await init();
    await _box!.put(trackId, jsonEncode(stats.toJson()));
  }

  void onTrackBecameActive(String trackId) {
    unawaited(_flushListen());
    _activeTrackId = trackId;
    _listenAccum = Duration.zero;
    _trackListenWall = Duration.zero;
    _lastPos = null;
    _sawCompleted = false;
  }

  void markCompleted() => _sawCompleted = true;

  bool consumeCompletedFlag() {
    final v = _sawCompleted;
    _sawCompleted = false;
    return v;
  }

  void onPosition(Duration position, {required bool playing}) {
    if (!playing || _activeTrackId == null) {
      _lastPos = position;
      return;
    }
    if (_lastPos != null && position > _lastPos!) {
      final delta = position - _lastPos!;
      _listenAccum += delta;
      _trackListenWall += delta;
    }
    _lastPos = position;
  }

  Future<void> flushListen() => _flushListen();

  Future<void> _flushListen() async {
    final id = _activeTrackId;
    if (id == null || _listenAccum <= Duration.zero) return;
    final addMs = _listenAccum.inMilliseconds;
    _listenAccum = Duration.zero;
    final cur = await get(id);
    await _put(id, cur.copyWith(totalListenMs: cur.totalListenMs + addMs));
  }

  Future<void> onTrackLeft({
    required String leavingTrackId,
    required bool completed,
  }) async {
    final listenMs = _trackListenWall.inMilliseconds;
    _trackListenWall = Duration.zero;
    await _flushListen();

    final cur = await get(leavingTrackId);
    var next = cur;

    if (completed || listenMs >= 15000) {
      next = next.copyWith(
        playCount: next.playCount + 1,
        lastPlayedMs: DateTime.now().millisecondsSinceEpoch,
      );
    } else if (listenMs < 10000) {
      next = next.copyWith(skipCount: next.skipCount + 1);
    }

    await _put(leavingTrackId, next);
    _sawCompleted = false;
  }
}
