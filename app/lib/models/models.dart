enum TrackStatus { queued, downloading, ready, failed, resolving }

class Track {
  final String id;
  final String name;
  final String artist;
  final int durationMs;
  final String? albumArt;
  final TrackStatus status;
  final int position;

  Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.durationMs,
    this.albumArt,
    this.status = TrackStatus.queued,
    this.position = 0,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      name: json['name'] as String,
      artist: json['artist'] as String,
      durationMs: json['duration_ms'] as int? ?? 0,
      albumArt: json['album_art'] as String?,
      status: _parseStatus(json['status'] as String?),
      position: json['position'] as int? ?? 0,
    );
  }

  Track copyWith({TrackStatus? status, int? position}) => Track(
        id: id,
        name: name,
        artist: artist,
        durationMs: durationMs,
        albumArt: albumArt,
        status: status ?? this.status,
        position: position ?? this.position,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'artist': artist,
        'duration_ms': durationMs,
        'album_art': albumArt,
        'status': status.name,
        'position': position,
      };

  static TrackStatus _parseStatus(String? s) {
    switch (s) {
      case 'ready':
        return TrackStatus.ready;
      case 'downloading':
        return TrackStatus.downloading;
      case 'failed':
        return TrackStatus.failed;
      case 'resolving':
        return TrackStatus.resolving;
      default:
        return TrackStatus.queued;
    }
  }

  String get durationFormatted {
    final totalSec = durationMs ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

class PlaylistSummary {
  final String id;
  final String name;
  final String? coverUrl;
  final int trackCount;
  final int readyCount;
  final bool syncing;
  final String spotifyUrl;

  PlaylistSummary({
    required this.id,
    required this.name,
    this.coverUrl,
    required this.trackCount,
    required this.readyCount,
    required this.syncing,
    required this.spotifyUrl,
  });

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      coverUrl: json['cover_url'] as String?,
      trackCount: json['track_count'] as int? ?? 0,
      readyCount: json['ready_count'] as int? ?? 0,
      syncing: json['syncing'] as bool? ?? false,
      spotifyUrl: json['spotify_url'] as String? ?? '',
    );
  }
}

class PlaylistDetail {
  final String id;
  final String name;
  final String? coverUrl;
  final String spotifyUrl;
  final List<Track> tracks;
  final int readyCount;
  final bool syncing;

  PlaylistDetail({
    required this.id,
    required this.name,
    this.coverUrl,
    required this.spotifyUrl,
    required this.tracks,
    required this.readyCount,
    required this.syncing,
  });

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) {
    final tracks = (json['tracks'] as List)
        .map((t) => Track.fromJson(t as Map<String, dynamic>))
        .toList();
    return PlaylistDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      coverUrl: json['cover_url'] as String?,
      spotifyUrl: json['spotify_url'] as String? ?? '',
      tracks: tracks,
      readyCount: json['ready_count'] as int? ?? 0,
      syncing: json['syncing'] as bool? ?? false,
    );
  }

  PlaylistDetail copyWith({List<Track>? tracks, int? readyCount, bool? syncing}) =>
      PlaylistDetail(
        id: id,
        name: name,
        coverUrl: coverUrl,
        spotifyUrl: spotifyUrl,
        tracks: tracks ?? this.tracks,
        readyCount: readyCount ?? this.readyCount,
        syncing: syncing ?? this.syncing,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cover_url': coverUrl,
        'spotify_url': spotifyUrl,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'ready_count': readyCount,
        'syncing': syncing,
      };
}

enum PlayerRepeatMode { off, one, all }
