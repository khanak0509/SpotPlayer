import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../services/local_store.dart';

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref);
});

class PlayerState {
  final Track? currentTrack;
  final List<Track> queue;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final PlayerRepeatMode repeat;
  final String? playlistId;
  final String? playlistName;
  final String? playlistCover;

  const PlayerState({
    this.currentTrack,
    this.queue = const [],
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = PlayerRepeatMode.off,
    this.playlistId,
    this.playlistName,
    this.playlistCover,
  });

  bool get hasTrack => currentTrack != null;

  PlayerState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    PlayerRepeatMode? repeat,
    String? playlistId,
    String? playlistName,
    String? playlistCover,
    bool clearTrack = false,
  }) {
    return PlayerState(
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName ?? this.playlistName,
      playlistCover: playlistCover ?? this.playlistCover,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier(this.ref) : super(const PlayerState()) {
    _init();
  }

  final Ref ref;
  final _player = AudioPlayer();
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;
  final _rng = Random();

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _posSub = _player.positionStream.listen((p) {
      state = state.copyWith(position: p);
    });
    _durSub = _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      state = state.copyWith(isPlaying: s.playing);
    });
    _completeSub = _player.processingStateStream.listen((ps) {
      if (ps == ProcessingState.completed) _onTrackComplete();
    });
  }

  void _onTrackComplete() {
    if (state.repeat == PlayerRepeatMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    next();
  }

  Future<void> playTracks({
    required List<Track> tracks,
    int startIndex = 0,
    bool shuffle = false,
    String? playlistId,
    String? playlistName,
    String? playlistCover,
  }) async {
    var queue = List<Track>.from(tracks.where((t) => _isPlayable(t)));
    if (queue.isEmpty) return;

    if (shuffle) {
      queue.shuffle(_rng);
    } else if (startIndex > 0 && startIndex < tracks.length) {
      final target = tracks[startIndex];
      final idx = queue.indexWhere((t) => t.id == target.id);
      if (idx > 0) {
        final picked = queue.removeAt(idx);
        queue.insert(0, picked);
      }
    }

    state = state.copyWith(
      queue: queue,
      shuffle: shuffle,
      repeat: PlayerRepeatMode.off,
      playlistId: playlistId,
      playlistName: playlistName,
      playlistCover: playlistCover,
    );
    await _playTrack(queue.first);
  }

  bool _isPlayable(Track track) {
    final store = ref.read(localStoreProvider);
    return store.hasTrack(track.id) || track.status == TrackStatus.ready;
  }

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (!_isPlayable(track)) return;
    if (queue != null) {
      state = state.copyWith(queue: queue);
    }
    await _playTrack(track);
  }

  Future<void> _playTrack(Track track) async {
    final store = ref.read(localStoreProvider);
    final sync = ref.read(trackSyncProvider);
    state = state.copyWith(currentTrack: track, position: Duration.zero);

    try {
      var path = store.getTrackPath(track.id);
      if (path == null) {
        path = await sync.downloadTrack(track);
      }
      if (path == null) return;

      await _player.setFilePath(path);
      await _player.play();
      HapticFeedback.lightImpact();
    } catch (_) {
      state = state.copyWith(isPlaying: false);
    }
  }

  Future<void> togglePlay() async {
    if (!state.hasTrack) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    HapticFeedback.lightImpact();
  }

  Future<void> pause() => _player.pause();

  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    final currentIdx = state.queue.indexWhere((t) => t.id == state.currentTrack?.id);
    if (currentIdx < 0) return;

    if (currentIdx + 1 < state.queue.length) {
      await _playTrack(state.queue[currentIdx + 1]);
    } else if (state.repeat == PlayerRepeatMode.all) {
      await _playTrack(state.queue.first);
    }
    HapticFeedback.selectionClick();
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (state.queue.isEmpty) return;
    final currentIdx = state.queue.indexWhere((t) => t.id == state.currentTrack?.id);
    if (currentIdx > 0) {
      await _playTrack(state.queue[currentIdx - 1]);
    } else {
      await _player.seek(Duration.zero);
    }
    HapticFeedback.selectionClick();
  }

  void toggleShuffle() {
    state = state.copyWith(shuffle: !state.shuffle);
    HapticFeedback.selectionClick();
  }

  void cycleRepeat() {
    final next = switch (state.repeat) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    state = state.copyWith(repeat: next);
    HapticFeedback.selectionClick();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final queue = List<Track>.from(state.queue);
    if (newIndex > oldIndex) newIndex--;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    state = state.copyWith(queue: queue);
  }

  void removeFromQueue(int index) {
    final queue = List<Track>.from(state.queue);
    queue.removeAt(index);
    state = state.copyWith(queue: queue);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
