import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const _baseUrl = 'http://152.70.78.160:8081';

  static Future<Map<String, dynamic>> identify(String path) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/music/full'),
      );

      request.files.add(await http.MultipartFile.fromPath('file', path));

      // Stamp exactly when we fire the request — song is at 'offset' seconds at this moment
      final requestSentAt = DateTime.now();

      final streamed = await request.send().timeout(const Duration(seconds: 20));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw Exception('Server error ${streamed.statusCode}: $body');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      final rawLyrics = json['lyrics'] as List? ?? [];
      final parsedLyrics = rawLyrics
          .map((item) => {
        'time': (item['time'] as num).toInt(),
        'text': (item['text'] as String).trim(),
      })
          .where((item) => (item['text'] as String).isNotEmpty)
          .toList();

      return {
        'title': json['title'] ?? 'Unknown',
        'artist': json['artist'] ?? '',
        'offset': (json['offset'] as num?)?.toInt() ?? 0,
        'synced': json['synced'] ?? false,
        'currentIndex': (json['currentIndex'] as num?)?.toInt() ?? 0,
        'lyrics': parsedLyrics,
        'albumArt': json['albumArt'] ?? '',
        'requestSentAt': requestSentAt, // ← the anchor
      };
    } catch (e) {
      print('ApiService error: $e');
      rethrow;
    }
  }
}