import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/pkm_theme.dart';

/// DeepL translation service for translating terminal text.
///
/// Uses the DeepL API (free or pro tier). Set DEEPL_API_KEY in your .env file
/// or enter it via the settings prompt.
class DeepLTranslationService {
  static final _instance = DeepLTranslationService._internal();
  factory DeepLTranslationService() => _instance;
  DeepLTranslationService._internal();

  final _storage = const FlutterSecureStorage();
  String? _apiKey;
  bool _initialized = false;

  bool get isAvailable => _initialized && _apiKey != null && _apiKey!.isNotEmpty;

  String? get apiKey => _apiKey;

  Future<void> initialize() async {
    if (_initialized) return;
    _apiKey = Platform.environment['DEEPL_API_KEY'];
    if (_apiKey == null || _apiKey!.isEmpty) {
      try {
        _apiKey = await _storage.read(key: 'deepl_api_key');
      } catch (e) {
        debugPrint('failed to read deepl key from secure storage: $e');
      }
    }
    _initialized = true;
  }

  Future<void> _saveApiKey(String key) async {
    _apiKey = key;
    try {
      await _storage.write(key: 'deepl_api_key', value: key);
    } catch (e) {
      debugPrint('failed to write deepl key to secure storage: $e');
    }
  }

  /// Show a dialog to enter the DeepL API key.
  Future<void> promptForApiKey(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PkmTheme.background,
        title: const Text(
          'enter deepl api key',
          style: TextStyle(
            color: PkmTheme.primary,
            fontFamily: PkmTheme.fontUi,
          ),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(
            color: PkmTheme.text,
            fontFamily: PkmTheme.fontUi,
          ),
          decoration: InputDecoration(
            hintText: 'api key',
            hintStyle: TextStyle(
              color: PkmTheme.text.withValues(alpha: 0.5),
              fontFamily: PkmTheme.fontUi,
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: PkmTheme.primary),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: PkmTheme.primary, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'cancel',
              style: TextStyle(
                color: PkmTheme.text,
                fontFamily: PkmTheme.fontUi,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                await _saveApiKey(key);
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text(
              'save',
              style: TextStyle(
                color: PkmTheme.primary,
                fontFamily: PkmTheme.fontUi,
              ),
            ),
          ),
        ],
      ),
    );
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
    } catch (e, stack) {
      stderr.writeln('[deepL] translation error: $e');
      debugPrintStack(stackTrace: stack);
    }
    return null;
  }
}
