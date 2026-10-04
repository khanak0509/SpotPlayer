import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio/just_audio.dart' as ja show PlayerState;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';
import '../services/local_store.dart';
import '../services/notification_service.dart';
import '../services/play_stats_store.dart';
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
    _ready = _init();
  }

  final Ref ref;
  final _player = AudioPlayer();
  late final Future<void> _ready;
  ConcatenatingAudioSource? _playlist;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _indexSub;
  Timer? _sleepTimer;
  Timer? _persistTimer;
  final _rng = Random();
  bool _notificationPermissionAsked = false;
  bool _loadingPlaylist = false;
  bool _restoringSession = false;
  bool _sleepAfterCurrentTrack = false;
  bool _fadedOut = false;
  int _loadGen = 0;
  int _fadeToken = 0;
  int _pauseSerial = 0;
  List<Track> _sourceOrder = [];

  static const _crossfadeWindow = Duration(milliseconds: 2800);

  bool get _crossfadeEnabled => ref.read(userPrefsProvider).crossfade;

  static LoopMode _loopModeFor(PlayerRepeatMode repeat) => switch (repeat) {
        PlayerRepeatMode.one => LoopMode.one,
        PlayerRepeatMode.all => LoopMode.all,
        PlayerRepeatMode.off => LoopMode.off,
      };

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

    _posSub = _player.positionStream.listen((p) {
      state = state.copyWith(position: p);
      ref.read(playStatsProvider).onPosition(p, playing: _player.playing);
      _maybeCrossfadeOut(p);
      _schedulePersist();
    });
    _durSub = _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
    _indexSub = _player.currentIndexStream.listen(_onIndexChanged);

    await _player.setSpeed(prefs.playbackSpeed);
    await _player.setLoopMode(LoopMode.off);
    try {
      await _player.setAutomaticallyWaitsToMinimizeStalling(true);
    } catch (_) {}
  }

  void _onPlayerState(ja.PlayerState s) {
    final completed = s.processingState == ProcessingState.completed;
    if (completed) {
      ref.read(playStatsProvider).markCompleted();
      unawaited(_player.pause());
      unawaited(_player.seek(Duration.zero));
      if (_sleepAfterCurrentTrack) _finishSleep();
    }
    final playing = s.playing && !completed;
    state = state.copyWith(isPlaying: playing);
    if (!playing) {
      unawaited(ref.read(playStatsProvider).flushListen());
    }
    ref.read(widgetServiceProvider).updateNowPlaying(state.currentTrack, isPlaying: playing);
    _schedulePersist();
  }

  void _onIndexChanged(int? index) {
    if (_loadingPlaylist || index == null) return;
    if (index < 0 || index >= state.queue.length) return;
    final track = state.queue[index];
    final prev = state.currentTrack;
    if (prev?.id == track.id) {
      if (state.currentIndex != index) state = state.copyWith(currentIndex: index);
      return;
    }

    final stats = ref.read(playStatsProvider);
    if (prev != null) {
      final remaining = state.duration - state.position;
      final nearEnd = state.duration > Duration.zero && remaining < const Duration(seconds: 4);
      final completed = stats.consumeCompletedFlag() || nearEnd;
      unawaited(stats.onTrackLeft(leavingTrackId: prev.id, completed: completed));
    }
    stats.onTrackBecameActive(track.id);

    state = state.copyWith(
      currentTrack: track,
      currentIndex: index,
      position: Duration.zero,
      duration: track.durationMs > 0 ? Duration(milliseconds: track.durationMs) : null,
    );

    if (_sleepAfterCurrentTrack && prev != null) {
      _finishSleep();
    }

    final wasFadedOut = _fadedOut;
    _fadedOut = false;
    if (_crossfadeEnabled && _player.playing) {
      unawaited(_fadeVolume(from: wasFadedOut ? 0.05 : 0, to: 1, steps: 14, stepMs: 40));
    } else {
      _fadeToken++;
      unawaited(_player.setVolume(1));
    }

    unawaited(ref.read(userPrefsProvider.notifier).addRecentTrack(track));
    ref.read(widgetServiceProvider).updateNowPlaying(track, isPlaying: _player.playing);
    _schedulePersist();
  }

  void _maybeCrossfadeOut(Duration position) {
    if (_loadingPlaylist) return;
    final duration = state.duration;
    final remaining = duration - position;
    final inWindow = _crossfadeEnabled &&
        _player.playing &&
        state.repeat != PlayerRepeatMode.one &&
        duration > _crossfadeWindow &&
        (_player.hasNext || state.repeat == PlayerRepeatMode.all) &&
        remaining > Duration.zero &&
        remaining <= _crossfadeWindow;
    if (!inWindow) {
      if (_fadedOut) {
        _fadedOut = false;
        unawaited(_player.setVolume(1));
      }
      return;
    }
    _fadedOut = true;
    _fadeToken++;
    final t = remaining.inMilliseconds / _crossfadeWindow.inMilliseconds;
    unawaited(_player.setVolume(t.clamp(0.05, 1.0)));
  }

  Future<void> _fadeVolume({
    required double from,
    required double to,
    int steps = 12,
    int stepMs = 35,
  }) async {
    final token = ++_fadeToken;
    await _player.setVolume(from);
    for (var i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: stepMs));
      if (token != _fadeToken) return;
      final v = from + (to - from) * (i / steps);
      await _player.setVolume(v.clamp(0.0, 1.0));
    }
  }

  void _finishSleep() {
    _sleepAfterCurrentTrack = false;
    _sleepTimer?.cancel();
    _pauseSerial++;
    unawaited(_player.pause());
    state = state.copyWith(clearSleep: true, isPlaying: false);
    _schedulePersist();
    unawaited(ref.read(notificationServiceProvider).notifySleepTimerEnded());
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
    final queue = List<Track>.from(ordered);
    var playIndex = 0;
    if (shuffle) {
      queue.shuffle(_rng);
      if (wanted != null) {
        final idx = queue.indexWhere((t) => t.id == wanted!.id);
        if (idx > 0) queue.insert(0, queue.removeAt(idx));
      }
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
    final gen = ++_loadGen;
    final pauseAtStart = _pauseSerial;
    _loadingPlaylist = true;
    _fadedOut = false;
    _fadeToken++;
    try {
      await _ready;
      final store = ref.read(localStoreProvider);
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

      final playlist = ConcatenatingAudioSource(children: children, useLazyPreparation: true);
      await _player.setAudioSource(
        playlist,
        initialIndex: safeIndex,
        initialPosition: initialPosition,
      );
      if (gen != _loadGen) return;
      _playlist = playlist;
      await _player.setLoopMode(_loopModeFor(state.repeat));
      await _player.setShuffleModeEnabled(false);

      final track = playable[safeIndex];
      final prev = state.currentTrack;
      final stats = ref.read(playStatsProvider);
      if (prev?.id != track.id) {
        if (prev != null) {
          unawaited(stats.onTrackLeft(leavingTrackId: prev.id, completed: stats.consumeCompletedFlag()));
        }
        stats.onTrackBecameActive(track.id);
      }
      state = state.copyWith(
        queue: playable,
        currentTrack: track,
        currentIndex: safeIndex,
        position: initialPosition,
        duration: track.durationMs > 0 ? Duration(milliseconds: track.durationMs) : null,
        clearError: true,
      );

      final shouldPlay = autoplay && _pauseSerial == pauseAtStart;
      if (shouldPlay) {
        if (_crossfadeEnabled) {
          await _player.setVolume(0);
          unawaited(_player.play());
          unawaited(_fadeVolume(from: 0, to: 1, steps: 12, stepMs: 30));
        } else {
          await _player.setVolume(1);
          unawaited(_player.play());
        }
        HapticFeedback.lightImpact();
      } else {
        await _player.setVolume(1);
        await _player.pause();
      }

      unawaited(ref.read(userPrefsProvider.notifier).addRecentTrack(track));
      ref.read(widgetServiceProvider).updateNowPlaying(track, isPlaying: shouldPlay);
    } catch (_) {
      if (gen == _loadGen) {
        state = state.copyWith(isPlaying: false, playError: 'Playback failed');
      }
    } finally {
      if (gen == _loadGen) {
        _loadingPlaylist = false;
        _schedulePersist();
      }
    }
  }

  void clearPlayError() => state = state.copyWith(clearError: true);

  Future<void> togglePlay() async {
    if (!state.hasTrack) return;
    HapticFeedback.lightImpact();
    if (_player.playing) {
      await pause();
      return;
    }
    await resume();
  }

  Future<void> resume() async {
    if (!state.hasTrack) return;
    if (_playlist == null || _player.processingState == ProcessingState.idle) {
      await _loadPlaylist(
        state.queue,
        initialIndex: state.currentIndex,
        initialPosition: state.position,
      );
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: state.currentIndex);
    }
    _fadeToken++;
    _fadedOut = false;
    await _player.setVolume(1);
    unawaited(_player.play());
  }

  Future<void> pause() async {
    _pauseSerial++;
    _fadeToken++;
    await _player.pause();
    await ref.read(playStatsProvider).flushListen();
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

  void setSleepTimer(Duration duration, {bool afterCurrentTrack = false}) {
    _sleepTimer?.cancel();
    _sleepAfterCurrentTrack = false;
    if (afterCurrentTrack) {
      _sleepAfterCurrentTrack = true;
      final remaining = state.duration - state.position;
      final endsAt = DateTime.now().add(remaining.isNegative ? Duration.zero : remaining);
      state = state.copyWith(sleepEndsAt: endsAt);
      HapticFeedback.mediumImpact();
      return;
    }
    if (duration <= Duration.zero) {
      state = state.copyWith(clearSleep: true);
      return;
    }
    state = state.copyWith(sleepEndsAt: DateTime.now().add(duration));
    _sleepTimer = Timer(duration, _finishSleep);
    HapticFeedback.mediumImpact();
  }

  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    if (_playlist == null || _loadingPlaylist) {
      await _loadPlaylist(state.queue, initialIndex: index);
      return;
    }
    await _player.seek(Duration.zero, index: index);
    if (!_player.playing) {
      _fadeToken++;
      await _player.setVolume(1);
      unawaited(_player.play());
    }
  }

  Future<void> next() async {
    final len = state.queue.length;
    if (len == 0) return;
    var target = state.currentIndex + 1;
    if (target >= len) {
      if (state.repeat == PlayerRepeatMode.off) return;
      target = 0;
    }
    HapticFeedback.selectionClick();
    await skipToIndex(target);
  }

  Future<void> previous() async {
    HapticFeedback.selectionClick();
    if (state.position.inSeconds > 3 || state.currentIndex == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await skipToIndex(state.currentIndex - 1);
  }

  Future<void> toggleShuffle() async {
    final enabling = !state.shuffle;
    HapticFeedback.selectionClick();
    if (state.queue.length <= 1) {
      state = state.copyWith(shuffle: enabling);
      _schedulePersist();
      return;
    }

    final current = state.currentTrack;
    final wasPlaying = _player.playing;
    final pos = _player.position;

    if (enabling) {
      _sourceOrder = List<Track>.from(state.queue);
      final queue = List<Track>.from(state.queue);
      if (current != null) {
        queue.removeWhere((t) => t.id == current.id);
        queue.shuffle(_rng);
        queue.insert(0, current);
      } else {
        queue.shuffle(_rng);
      }
      state = state.copyWith(shuffle: true, queue: queue, currentIndex: 0);
      await _loadPlaylist(queue, initialIndex: 0, initialPosition: pos, autoplay: wasPlaying);
    } else {
      final source = _sourceOrder.isNotEmpty ? List<Track>.from(_sourceOrder) : List<Track>.from(state.queue);
      var index = 0;
      if (current != null) {
        final idx = source.indexWhere((t) => t.id == current.id);
        index = idx >= 0 ? idx : 0;
      }
      state = state.copyWith(shuffle: false, queue: source, currentIndex: index);
      await _loadPlaylist(source, initialIndex: index, initialPosition: pos, autoplay: wasPlaying);
    }
  }

  Future<void> cycleRepeat() async {
    final next = switch (state.repeat) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    state = state.copyWith(repeat: next);
    await _player.setLoopMode(_loopModeFor(next));
    HapticFeedback.selectionClick();
    _schedulePersist();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) => _moveInQueue(oldIndex, newIndex);

  Future<void> syncPlaylistOrder(String playlistId, List<Track> ordered) async {
    if (state.playlistId != playlistId || state.queue.isEmpty) return;
    final inQueue = {for (final t in state.queue) t.id};
    final target = ordered.where((t) => inQueue.contains(t.id)).toList();

    if (state.shuffle) {
      _sourceOrder = target;
      _schedulePersist();
      return;
    }
    if (target.length != state.queue.length) return;

    for (var i = 0; i < target.length; i++) {
      if (state.queue[i].id == target[i].id) continue;
      final from = state.queue.indexWhere((t) => t.id == target[i].id);
      if (from < 0) return;
      await _moveInQueue(from, i);
    }
  }

  Future<void> _moveInQueue(int oldIndex, int newIndex) async {
    final len = state.queue.length;
    if (oldIndex < 0 || oldIndex >= len) return;
    newIndex = newIndex.clamp(0, len - 1);
    if (newIndex == oldIndex) return;

    final queue = List<Track>.from(state.queue);
    queue.insert(newIndex, queue.removeAt(oldIndex));
    if (!state.shuffle) _sourceOrder = List<Track>.from(queue);
    final currentId = state.currentTrack?.id;
    final current = currentId == null ? 0 : queue.indexWhere((t) => t.id == currentId);
    state = state.copyWith(queue: queue, currentIndex: current < 0 ? 0 : current);

    final playlist = _playlist;
    if (playlist != null && !_loadingPlaylist && playlist.length == len) {
      try {
        await playlist.move(oldIndex, newIndex);
        _schedulePersist();
        return;
      } catch (_) {}
    }
    await _reloadKeepingPosition();
  }

  Future<void> removeFromQueue(int index) async {
    final len = state.queue.length;
    if (index < 0 || index >= len) return;
    final queue = List<Track>.from(state.queue);
    final removed = queue.removeAt(index);
    _sourceOrder = _sourceOrder.where((t) => t.id != removed.id).toList();

    if (queue.isEmpty) {
      _loadGen++;
      _loadingPlaylist = false;
      _playlist = null;
      await _player.stop();
      state = PlayerState(playbackSpeed: state.playbackSpeed, repeat: state.repeat);
      await ref.read(widgetServiceProvider).updateNowPlaying(null);
      await ref.read(playbackSessionProvider).clear();
      return;
    }

    if (index == state.currentIndex) {
      final wasPlaying = _player.playing;
      state = state.copyWith(queue: queue);
      await _loadPlaylist(
        queue,
        initialIndex: index.clamp(0, queue.length - 1),
        autoplay: wasPlaying,
      );
      return;
    }

    final current = state.currentIndex > index ? state.currentIndex - 1 : state.currentIndex;
    state = state.copyWith(queue: queue, currentIndex: current);

    final playlist = _playlist;
    if (playlist != null && !_loadingPlaylist && playlist.length == len) {
      try {
        await playlist.removeAt(index);
        _schedulePersist();
        return;
      } catch (_) {}
    }
    await _reloadKeepingPosition();
  }

  Future<void> removeTrackFromQueue(String trackId) async {
    final index = state.queue.indexWhere((t) => t.id == trackId);
    if (index < 0) {
      _sourceOrder = _sourceOrder.where((t) => t.id != trackId).toList();
      return;
    }
    await removeFromQueue(index);
  }

  Future<void> _reloadKeepingPosition() => _loadPlaylist(
        state.queue,
        initialIndex: state.currentIndex,
        initialPosition: _player.position,
        autoplay: _player.playing,
      );

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _persistTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _indexSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
