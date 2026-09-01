import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

final apiProvider = Provider((ref) => ApiService());

class ApiService {
  static const defaultBaseUrl = 'https://spotplayer-api.onrender.com/api';
  static const coldStartTimeout = Duration(seconds: 90);
  static const normalTimeout = Duration(seconds: 30);

  late Dio _dio;
  final String baseUrl = defaultBaseUrl;

  Future<void> init() async {
    _dio = _buildDio(normalTimeout);
  }

  Dio _buildDio(Duration timeout) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: timeout,
        receiveTimeout: timeout,
      ));

  String streamUrl(String trackId) => '$baseUrl/tracks/$trackId/stream';

  Future<ImportResult> importPlaylist(String url) async {
    final dio = _buildDio(coldStartTimeout);
    dio.options.baseUrl = baseUrl;
    final res = await dio.post('/playlists/import', data: {'url': url});
    return ImportResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<ImportResult> syncPlaylist(String spotifyUrl) async {
    final dio = _buildDio(coldStartTimeout);
    dio.options.baseUrl = baseUrl;
    final res = await dio.post('/playlists/sync', data: {'url': spotifyUrl});
    return ImportResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> queueTracks(List<Track> tracks) async {
    await _dio.post('/tracks/queue', data: {
      'tracks': tracks
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'artist': t.artist,
                'duration_ms': t.durationMs,
              })
          .toList(),
    });
  }

  Future<Map<String, TrackStatus>> batchTrackStatus(List<String> trackIds) async {
    if (trackIds.isEmpty) return {};
    final res = await _dio.post('/tracks/status', data: {'track_ids': trackIds});
    final statuses = res.data['statuses'] as Map<String, dynamic>? ?? {};
    return statuses.map((k, v) => MapEntry(k, _parseStatus(v?.toString())));
  }

  TrackStatus _parseStatus(String? s) {
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

  Future<void> retryTrack(String trackId, List<Track> tracks) async {
    await _dio.post('/tracks/$trackId/retry', data: {
      'tracks': tracks
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'artist': t.artist,
                'duration_ms': t.durationMs,
              })
          .toList(),
    });
  }

  Future<bool> ping() async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: baseUrl.replaceAll('/api', ''),
        connectTimeout: coldStartTimeout,
        receiveTimeout: coldStartTimeout,
      ));
      await dio.get('/health');
      return true;
    } catch (_) {
      return false;
    }
  }
}

class ImportResult {
  final String playlistId;
  final String name;
  final int trackCount;
  final PlaylistDetail playlist;

  ImportResult({
    required this.playlistId,
    required this.name,
    required this.trackCount,
    required this.playlist,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      playlistId: json['playlist_id'] as String,
      name: json['name'] as String,
      trackCount: json['track_count'] as int? ?? 0,
      playlist: PlaylistDetail.fromJson(json['playlist'] as Map<String, dynamic>),
    );
  }
}
