import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

final apiProvider = Provider((ref) => ApiService());

class ApiService {
  static const defaultBaseUrl = 'http://localhost:8000/api';
  static const coldStartTimeout = Duration(seconds: 90);
  static const normalTimeout = Duration(seconds: 30);

  late Dio _dio;
  String baseUrl = defaultBaseUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('backend_url') ?? defaultBaseUrl;
    _dio = _buildDio(normalTimeout);
  }

  Dio _buildDio(Duration timeout) => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: timeout,
        receiveTimeout: timeout,
      ));

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.endsWith('/api') ? url : '$url/api';
    _dio.options.baseUrl = baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', baseUrl);
  }

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
    return statuses.map((k, v) => MapEntry(k, Track.fromJson({'status': v}).status));
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
