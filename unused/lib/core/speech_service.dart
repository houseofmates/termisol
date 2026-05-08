import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-text service wrapping the speech_to_text package.
///
/// Robust error handling, availability checks, and clean start/stop.
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  String _lastWords = '';

  bool get isAvailable => _speech.isAvailable;
  bool get isListening => _speech.isListening;
  String get lastWords => _lastWords;

  /// Initialize the speech recognizer. Returns true if speech recognition
  /// is available on this device.
  Future<bool> initialize() async {
    if (_initialized) return _speech.isAvailable;
    try {
      _initialized = await _speech.initialize(
        onError: (error) => debugPrint('[speech] error: $error'),
        onStatus: (status) => debugPrint('[speech] status: $status'),
      );
    } catch (e) {
      debugPrint('[speech] init exception: $e');
      _initialized = false;
    }
    return _initialized && _speech.isAvailable;
  }

  /// Start listening. [onResult] is called whenever the recognizer has
  /// a result (partial or final depending on [partialResults]).
  /// Returns false if listening could not be started.
  Future<bool> listen({
    required void Function(String text, bool isFinal) onResult,
    bool partialResults = false,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return false;
    }
    if (!_speech.isAvailable) return false;
    if (_speech.isListening) return false;

    _lastWords = '';
    try {
      await _speech.listen(
        onResult: (result) {
          _lastWords = result.recognizedWords;
          if (_lastWords.isNotEmpty) {
            onResult(_lastWords, result.finalResult);
          }
        },
        listenMode: ListenMode.dictation,
        partialResults: partialResults,
        cancelOnError: false,
      );
      return true;
    } catch (e) {
      debugPrint('[speech] listen exception: $e');
      return false;
    }
  }

  /// Stop listening and return the final transcription.
  Future<String?> stop() async {
    if (!_speech.isListening) return _lastWords.isNotEmpty ? _lastWords : null;
    try {
      await _speech.stop();
      // Give the final result callback a moment to fire.
      await Future.delayed(const Duration(milliseconds: 300));
      return _lastWords.isNotEmpty ? _lastWords : null;
    } catch (e) {
      debugPrint('[speech] stop exception: $e');
      return _lastWords.isNotEmpty ? _lastWords : null;
    }
  }

  void dispose() {
    try {
      _speech.cancel();
    } catch (e) {
      debugPrint('Failed to cancel speech: $e');
    }
  }
}
