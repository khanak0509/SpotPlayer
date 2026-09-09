import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import '../services/local_store.dart';
import '../services/playback_session_store.dart';
import '../services/server_connectivity.dart';
import '../services/user_prefs_store.dart';
import '../services/widget_service.dart';

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref);
});

class PlayerState {
  final Track? currentTrack;
  final List<Track> queue;
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool shuffle;
  final PlayerRepeatMode repeat;
  final String? playlistId;
  final String? playlistName;
  final String? playlistCover;
  final double playbackSpeed;
  final DateTime? sleepEndsAt;
  final String? playError;

  const PlayerState({
    this.currentTrack,
    this.queue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = false,
    this.repeat = PlayerRepeatMode.off,
    this.playlistId,
    this.playlistName,
    this.playlistCover,
    this.playbackSpeed = 1.0,
    this.sleepEndsAt,
    this.playError,
  });

  bool get hasTrack => currentTrack != null;

  Duration? get sleepRemaining {
    if (sleepEndsAt == null) return null;
    final left = sleepEndsAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  PlayerState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? shuffle,
    PlayerRepeatMode? repeat,
    String? playlistId,
    String? playlistName,
    String? playlistCover,
    double? playbackSpeed,
    DateTime? sleepEndsAt,
    String? playError,
    bool clearSleep = false,
    bool clearTrack = false,
    bool clearError = false,
  }) {
    return PlayerState(
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName ?? this.playlistName,
      playlistCover: playlistCover ?? this.playlistCover,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      sleepEndsAt: clearSleep ? null : (sleepEndsAt ?? this.sleepEndsAt),
      playError: clearError ? null : (playError ?? this.playError),
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
  StreamSubscription? _indexSub;
  StreamSubscription? _interruptionSub;
  StreamSubscription? _noisySub;
  Timer? _sleepTimer;
  Timer? _persistTimer;
  final _rng = Random();
  bool _wasPlayingBeforeInterruption = false;
  bool _pausedByUser = false;
  bool _notificationPermissionAsked = false;
  bool _loadingPlaylist = false;
  bool _restoringSession = false;
  bool _crossfadeOutActive = false;
  List<Track> _sourceOrder = [];

  static const _crossfadeWindow = Duration(milliseconds: 2800);

  bool get _crossfadeEnabled => ref.read(userPrefsProvider).crossfade;

  Future<void> _ensureNotificationPermission() async {
    if (_notificationPermissionAsked || !Platform.isAndroid) return;
    _notificationPermissionAsked = true;
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  Future<void> _init() async {
    final prefs = ref.read(userPrefsProvider);
    state = state.copyWith(playbackSpeed: prefs.playbackSpeed);

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (event.type == AudioInterruptionType.pause ||
            event.type == AudioInterruptionType.duck) {
          _wasPlayingBeforeInterruption = _player.playing && !_pausedByUser;
          _player.pause();
        }
      } else if (event.type == AudioInterruptionType.pause) {
        if (_wasPlayingBeforeInterruption && !_pausedByUser) {
          _player.play();
        }
        _wasPlayingBeforeInterruption = false;
      }
    });

    _noisySub = session.becomingNoisyEventStream.listen((_) {
      _pausedByUser = true;
      _player.pause();
    });

    _posSub = _player.positionStream.listen((p) {
      state = state.copyWith(position: p);
      _maybeCrossfadeOut(p);
      _schedulePersist();
    });
    _durSub = _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      state = state.copyWith(isPlaying: s.playing);
      ref.read(widgetServiceProvider).updateNowPlaying(
            state.currentTrack,
            isPlaying: s.playing,
          );
      _schedulePersist();
    });
    _indexSub = _player.currentIndexStream.listen((index) async {
      if (_loadingPlaylist || index == null) return;
      if (index < 0 || index >= state.queue.length) return;
      final track = state.queue[index];
      if (state.currentTrack?.id == track.id && state.currentIndex == index) return;
      _crossfadeOutActive = false;
      state = state.copyWith(currentTrack: track, currentIndex: index, position: Duration.zero);
      if (_crossfadeEnabled) {
        await _fadeVolume(from: 0, to: 1, steps: 14, stepMs: 40);
      } else {
        await _player.setVolume(1);
      }
      ref.read(userPrefsProvider.notifier).addRecentTrack(track);
      ref.read(widgetServiceProvider).updateNowPlaying(track, isPlaying: _player.playing);
      _schedulePersist();
    });

    await _player.setSpeed(prefs.playbackSpeed);
    await _player.setLoopMode(LoopMode.off);
    try {
      await _player.setAutomaticallyWaitsToMinimizeStalling(true);
    } catch (_) {}
  }

  void _maybeCrossfadeOut(Duration position) {
    if (!_crossfadeEnabled || _loadingPlaylist || !_player.playing || _crossfadeOutActive) return;
    final duration = state.duration;
    if (duration <= _crossfadeWindow) return;
    if (!_player.hasNext && state.repeat != PlayerRepeatMode.all) return;
    final remaining = duration - position;
    if (remaining <= Duration.zero || remaining > _crossfadeWindow) return;
    final t = remaining.inMilliseconds / _crossfadeWindow.inMilliseconds;
    unawaited(_player.setVolume(t.clamp(0.05, 1.0)));
  }

  Future<void> _fadeVolume({
    required double from,
    required double to,
    int steps = 12,
    int stepMs = 35,
  }) async {
    if (steps <= 0) {
      await _player.setVolume(to);
      return;
    }
    await _player.setVolume(from);
    for (var i = 1; i <= steps; i++) {
      final v = from + (to - from) * (i / steps);
      await _player.setVolume(v.clamp(0.0, 1.0));
      await Future.delayed(Duration(milliseconds: stepMs));
    }
  }

  void _schedulePersist() {
    if (_restoringSession || _loadingPlaylist) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_persistSession());
    });
  }

  Future<void> _persistSession() async {
    if (!state.hasTrack || state.queue.isEmpty) {
      await ref.read(playbackSessionProvider).clear();
      return;
    }
    await ref.read(playbackSessionProvider).save(PlaybackSession(
          queue: state.queue,
          sourceOrder: _sourceOrder.isEmpty ? state.queue : _sourceOrder,
          currentIndex: state.currentIndex,
          positionMs: state.position.inMilliseconds,
          shuffle: state.shuffle,
          repeat: state.repeat,
          playlistId: state.playlistId,
          playlistName: state.playlistName,
          playlistCover: state.playlistCover,
        ));
  }

  /// Restore last queue/position after cold start. Loads paused (no autoplay).
  Future<void> restoreSession() async {
    if (state.hasTrack) return;
    final saved = await ref.read(playbackSessionProvider).load();
    if (saved == null || saved.isEmpty) return;

    final store = ref.read(localStoreProvider);
    final queue = saved.queue.where((t) => store.hasTrack(t.id)).toList();
    if (queue.isEmpty) {
      await ref.read(playbackSessionProvider).clear();
      return;
    }

    _sourceOrder = saved.sourceOrder.where((t) => store.hasTrack(t.id)).toList();
    if (_sourceOrder.isEmpty) _sourceOrder = List<Track>.from(queue);

    var index = saved.currentIndex.clamp(0, queue.length - 1);
    final wantedId = saved.currentIndex >= 0 && saved.currentIndex < saved.queue.length
        ? saved.queue[saved.currentIndex].id
        : null;
    if (wantedId != null) {
      final mapped = queue.indexWhere((t) => t.id == wantedId);
      if (mapped >= 0) index = mapped;
    }

    _restoringSession = true;
    try {
      state = state.copyWith(
        shuffle: saved.shuffle,
        repeat: saved.repeat,
        playlistId: saved.playlistId,
        playlistName: saved.playlistName,
        playlistCover: saved.playlistCover,
      );
      await _loadPlaylist(
        queue,
        initialIndex: index,
        initialPosition: Duration(milliseconds: saved.positionMs.clamp(0, 1 << 30)),
        autoplay: false,
      );
      _pausedByUser = true;
    } finally {
      _restoringSession = false;
    }
  }

  Future<void> playTracks({
    required List<Track> tracks,
    int startIndex = 0,
    bool shuffle = false,
    String? playlistId,
    String? playlistName,
    String? playlistCover,
  }) async {
    await _ensureNotificationPermission();

    final store = ref.read(localStoreProvider);
    Track? wanted;
    if (startIndex >= 0 && startIndex < tracks.length) {
      wanted = tracks[startIndex];
      if (!store.hasTrack(wanted.id) &&
          ref.read(serverReachableProvider) &&
          wanted.status == TrackStatus.ready) {
        await ref.read(trackSyncProvider).downloadTrack(wanted);
      }
    }

    final ordered = tracks.where((t) => store.hasTrack(t.id)).toList();
    if (ordered.isEmpty) {
      state = state.copyWith(
        playError: ref.read(serverReachableProvider)
            ? 'No downloaded tracks yet'
            : 'No downloaded tracks. Start backend to download.',
      );
      return;
    }

    _sourceOrder = List<Track>.from(ordered);
    var queue = List<Track>.from(ordered);
    var playIndex = 0;
    if (shuffle) {
      queue.shuffle(_rng);
      if (wanted != null) {
        final idx = queue.indexWhere((t) => t.id == wanted!.id);
        if (idx > 0) {
          final picked = queue.removeAt(idx);
          queue.insert(0, picked);
        }
      }
      playIndex = 0;
    } else if (wanted != null) {
      final idx = queue.indexWhere((t) => t.id == wanted!.id);
      playIndex = idx >= 0 ? idx : 0;
    }

    state = state.copyWith(
      queue: queue,
      shuffle: shuffle,
      playlistId: playlistId,
      playlistName: playlistName,
      playlistCover: playlistCover,
      currentIndex: playIndex,
      clearError: true,
    );

    await _loadPlaylist(queue, initialIndex: playIndex);
  }

  bool _canAttemptPlay(Track track) {
    final store = ref.read(localStoreProvider);
    if (store.hasTrack(track.id)) return true;
    return ref.read(serverReachableProvider) && track.status == TrackStatus.ready;
  }

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (queue != null && queue.isNotEmpty) {
      final start = queue.indexWhere((t) => t.id == track.id);
      await playTracks(
        tracks: queue,
        startIndex: start >= 0 ? start : 0,
        shuffle: state.shuffle,
        playlistId: state.playlistId,
        playlistName: state.playlistName,
        playlistCover: state.playlistCover,
      );
      return;
    }
    if (!_canAttemptPlay(track)) {
      state = state.copyWith(
        playError: ref.read(serverReachableProvider)
            ? 'Track is not ready yet'
            : 'Start backend to download this track',
      );
      return;
    }
    await playTracks(tracks: [track], startIndex: 0);
  }

  MediaItem _mediaItemFor(Track track) {
    return MediaItem(
      id: track.id,
      title: track.name,
      artist: track.artist,
      album: state.playlistName ?? 'SpotPlayer',
      duration: Duration(milliseconds: track.durationMs),
      artUri: track.albumArt != null ? Uri.tryParse(track.albumArt!) : null,
      playable: true,
    );
  }

  Future<void> _loadPlaylist(
    List<Track> queue, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
    bool autoplay = true,
  }) async {
    final store = ref.read(localStoreProvider);
    _loadingPlaylist = true;
    _crossfadeOutActive = false;
    try {
      final playable = <Track>[];
      final children = <AudioSource>[];
      for (final track in queue) {
        final path = store.getTrackPath(track.id);
        if (path == null) continue;
        playable.add(track);
        children.add(AudioSource.file(path, tag: _mediaItemFor(track)));
      }
      if (children.isEmpty) {
        state = state.copyWith(playError: 'No playable files found', isPlaying: false, queue: const []);
        return;
      }

      var safeIndex = initialIndex.clamp(0, playable.length - 1);
      final wantedId = initialIndex >= 0 && initialIndex < queue.length ? queue[initialIndex].id : null;
      if (wantedId != null) {
        final mapped = playable.indexWhere((t) => t.id == wantedId);
        if (mapped >= 0) safeIndex = mapped;
      }

      final session = await AudioSession.instance;
      await session.setActive(true);

      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: children,
          useLazyPreparation: true,
        ),
        initialIndex: safeIndex,
        initialPosition: initialPosition,
      );

      await _player.setLoopMode(
        state.repeat == PlayerRepeatMode.one
            ? LoopMode.one
            : state.repeat == PlayerRepeatMode.all
                ? LoopMode.all
                : LoopMode.off,
      );
      await _player.setShuffleModeEnabled(false);
      await _player.setVolume(1);

      final track = playable[safeIndex];
      state = state.copyWith(
        queue: playable,
        currentTrack: track,
        currentIndex: safeIndex,
        position: initialPosition,
        clearError: true,
      );

      if (autoplay) {
        _pausedByUser = false;
        if (_crossfadeEnabled) {
          await _player.setVolume(0);
          await _player.play();
          await _fadeVolume(from: 0, to: 1, steps: 12, stepMs: 30);
        } else {
          await _player.play();
        }
      } else {
        await _player.pause();
      }

      await ref.read(userPrefsProvider.notifier).addRecentTrack(track);
      await ref.read(widgetServiceProvider).updateNowPlaying(track, isPlaying: _player.playing);
      if (autoplay) HapticFeedback.lightImpact();
      _schedulePersist();
    } catch (_) {
      state = state.copyWith(isPlaying: false, playError: 'Playback failed');
    } finally {
      _loadingPlaylist = false;
    }
  }

  void clearPlayError() => state = state.copyWith(clearError: true);

  Future<void> togglePlay() async {
    if (!state.hasTrack) return;
    if (_player.playing) {
      _pausedByUser = true;
      await _player.pause();
    } else {
      _pausedByUser = false;
      await AudioSession.instance.then((s) => s.setActive(true));
      await _player.setVolume(1);
      await _player.play();
    }
    HapticFeedback.lightImpact();
    _schedulePersist();
  }

  Future<void> pause() async {
    _pausedByUser = true;
    await _player.pause();
    _schedulePersist();
  }

  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> cyclePlaybackSpeed() async {
    const speeds = [0.8, 1.0, 1.25];
    final idx = speeds.indexWhere((s) => (s - state.playbackSpeed).abs() < 0.01);
    final next = speeds[(idx + 1) % speeds.length];
    await _player.setSpeed(next);
    state = state.copyWith(playbackSpeed: next);
    await ref.read(userPrefsProvider.notifier).setPlaybackSpeed(next);
    HapticFeedback.selectionClick();
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    if (duration <= Duration.zero) {
      state = state.copyWith(clearSleep: true);
      return;
    }
    final endsAt = DateTime.now().add(duration);
    state = state.copyWith(sleepEndsAt: endsAt);
    _sleepTimer = Timer(duration, () async {
      _pausedByUser = true;
      await _player.pause();
      state = state.copyWith(clearSleep: true, isPlaying: false);
      _schedulePersist();
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> next() async {
    if (state.queue.length <= 1) return;
    if (_player.hasNext) {
      _pausedByUser = false;
      await _player.seekToNext();
      if (!_player.playing) await _player.play();
    } else if (state.repeat == PlayerRepeatMode.all) {
      await _player.seek(Duration.zero, index: 0);
      if (!_player.playing) await _player.play();
    }
    HapticFeedback.selectionClick();
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_player.hasPrevious) {
      _pausedByUser = false;
      await _player.seekToPrevious();
      if (!_player.playing) await _player.play();
    } else {
      await _player.seek(Duration.zero);
    }
    HapticFeedback.selectionClick();
  }

  Future<void> toggleShuffle() async {
    final enabling = !state.shuffle;
    if (state.queue.length <= 1) {
      state = state.copyWith(shuffle: enabling);
      HapticFeedback.selectionClick();
      _schedulePersist();
      return;
    }

    final current = state.currentTrack;
    final wasPlaying = _player.playing;
    final pos = _player.position;

    if (enabling) {
      if (_sourceOrder.isEmpty) {
        _sourceOrder = List<Track>.from(state.queue);
      }
      var queue = List<Track>.from(state.queue);
      if (current != null) {
        queue.removeWhere((t) => t.id == current.id);
        queue.shuffle(_rng);
        queue.insert(0, current);
      } else {
        queue.shuffle(_rng);
      }
      state = state.copyWith(shuffle: true, queue: queue, currentIndex: 0);
      await _loadPlaylist(
        queue,
        initialIndex: 0,
        initialPosition: pos,
        autoplay: wasPlaying,
      );
    } else {
      final source = _sourceOrder.isNotEmpty ? List<Track>.from(_sourceOrder) : List<Track>.from(state.queue);
      var index = 0;
      if (current != null) {
        final idx = source.indexWhere((t) => t.id == current.id);
        index = idx >= 0 ? idx : 0;
      }
      state = state.copyWith(shuffle: false, queue: source, currentIndex: index);
      await _loadPlaylist(
        source,
        initialIndex: index,
        initialPosition: pos,
        autoplay: wasPlaying,
      );
    }
    HapticFeedback.selectionClick();
  }

  Future<void> cycleRepeat() async {
    final next = switch (state.repeat) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    state = state.copyWith(repeat: next);
    await _player.setLoopMode(
      next == PlayerRepeatMode.one
          ? LoopMode.one
          : next == PlayerRepeatMode.all
              ? LoopMode.all
              : LoopMode.off,
    );
    HapticFeedback.selectionClick();
    _schedulePersist();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final queue = List<Track>.from(state.queue);
    if (newIndex > oldIndex) newIndex--;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    if (!state.shuffle) {
      _sourceOrder = List<Track>.from(queue);
    }
    final currentId = state.currentTrack?.id;
    final newCurrent = currentId == null ? 0 : queue.indexWhere((t) => t.id == currentId);
    final wasPlaying = _player.playing;
    final pos = _player.position;
    state = state.copyWith(queue: queue, currentIndex: newCurrent < 0 ? 0 : newCurrent);
    unawaited(_loadPlaylist(
      queue,
      initialIndex: newCurrent < 0 ? 0 : newCurrent,
      initialPosition: pos,
      autoplay: wasPlaying,
    ));
  }

  void removeFromQueue(int index) {
    final queue = List<Track>.from(state.queue);
    if (index < 0 || index >= queue.length) return;
    final removingCurrent = index == state.currentIndex;
    final removed = queue.removeAt(index);
    _sourceOrder = _sourceOrder.where((t) => t.id != removed.id).toList();
    if (queue.isEmpty) {
      unawaited(_player.stop());
      state = const PlayerState();
      unawaited(ref.read(widgetServiceProvider).updateNowPlaying(null));
      unawaited(ref.read(playbackSessionProvider).clear());
      return;
    }
    final currentId = state.currentTrack?.id;
    var newIndex = currentId == null ? 0 : queue.indexWhere((t) => t.id == currentId);
    if (newIndex < 0) newIndex = index.clamp(0, queue.length - 1);
    state = state.copyWith(queue: queue, currentIndex: newIndex);
    if (removingCurrent) {
      unawaited(_loadPlaylist(queue, initialIndex: newIndex));
    } else {
      unawaited(_loadPlaylist(
        queue,
        initialIndex: newIndex,
        initialPosition: _player.position,
        autoplay: _player.playing,
      ));
    }
  }

  Future<void> removeTrackFromQueue(String trackId) async {
    final queue = state.queue.where((t) => t.id != trackId).toList();
    _sourceOrder = _sourceOrder.where((t) => t.id != trackId).toList();
    if (state.currentTrack?.id == trackId) {
      if (queue.isEmpty) {
        await _player.stop();
        state = const PlayerState();
        await ref.read(widgetServiceProvider).updateNowPlaying(null);
        await ref.read(playbackSessionProvider).clear();
        return;
      }
      final nextIndex = state.currentIndex.clamp(0, queue.length - 1);
      state = state.copyWith(queue: queue);
      await _loadPlaylist(queue, initialIndex: nextIndex);
      return;
    }
    final currentId = state.currentTrack?.id;
    final newIndex = currentId == null ? 0 : queue.indexWhere((t) => t.id == currentId);
    state = state.copyWith(queue: queue, currentIndex: newIndex < 0 ? 0 : newIndex);
    _schedulePersist();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _persistTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _indexSub?.cancel();
    _interruptionSub?.cancel();
    _noisySub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
