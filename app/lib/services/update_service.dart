import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final updateMessageProvider = FutureProvider<String?>((ref) async {
  try {
    final response = await http
        .get(Uri.parse('https://ping-162f.onrender.com/ping'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final message = data['message'] as String?;
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
  } catch (_) {
    // Ignore ping failures
  }
  return null;
});

final updateDismissedProvider = StateProvider<bool>((ref) => false);
