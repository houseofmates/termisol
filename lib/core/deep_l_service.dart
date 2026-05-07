import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// DeepL translation service for translating terminal text.
///
/// Uses the DeepL API (free or pro tier). Set DEEPL_API_KEY in your .env file.
class DeepLTranslationService {
  static final _instance = DeepLTranslationService._internal();
  factory DeepLTranslationService() => _instance;
  DeepLTranslationService._internal();

  String? _apiKey;
  bool _initialized = false;

  bool get isAvailable => _initialized && _apiKey != null && _apiKey!.isNotEmpty;

  void initialize() {
    if (_initialized) return;
    _apiKey = Platform.environment['DEEPL_API_KEY'];
    _initialized = true;
  }

  /// Translate text to English.
  ///
  /// Returns the translated text, or null if translation fails.
  Future<String?> translateToEnglish(String text) async {
    if (!isAvailable) return null;
    if (text.trim().isEmpty) return null;

    final url = Uri.parse('https://api-free.deepl.com/v2/translate');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'DeepL-Auth-Key $_apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'text': text,
          'target_lang': 'EN',
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final translations = json['translations'] as List<dynamic>?;
        if (translations != null && translations.isNotEmpty) {
          final first = translations.first as Map<String, dynamic>;
          return first['text'] as String?;
        }
      } else {
        stderr.writeln('[deepL] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      stderr.writeln('[deepL] translation error: $e');
    }
    return null;
  }
}
