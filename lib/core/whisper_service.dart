import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// whisper speech-to-text service for local server integration
class WhisperService {
  final String serverUrl;
  final Duration timeout;
  
  WhisperService({
    this.serverUrl = 'http://192.168.4.250:9000',
    this.timeout = const Duration(seconds: 30),
  });

  /// check if whisper server is available
  Future<bool> isServerAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/health'),
      ).timeout(timeout);
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Whisper server unavailable: $e');
      return false;
    }
  }

  /// transcribe audio file with whisper
  Future<String> transcribeAudioFile(String audioFilePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/transcribe'),
      );
      
      // add audio file
      final audioFile = await http.MultipartFile.fromPath(
        'audio',
        audioFilePath,
      );
      request.files.add(audioFile);
      
      // add parameters
      request.fields['language'] = 'en';
      request.fields['task'] = 'transcribe';
      request.fields['temperature'] = '0.0';
      request.fields['best_of'] = '1';
      
      final response = await request.send().timeout(timeout);
      
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final result = jsonDecode(responseData);
        return result['text'] as String? ?? '';
      } else {
        throw Exception('Whisper API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Transcription failed: $e');
    }
  }

  /// transcribe audio bytes directly
  Future<String> transcribeAudioBytes(List<int> audioBytes, String filename) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/transcribe'),
      );
      
      // add audio bytes
      final audioFile = http.MultipartFile.fromBytes(
        'audio',
        audioBytes,
        filename: filename,
      );
      request.files.add(audioFile);
      
      // add parameters
      request.fields['language'] = 'en';
      request.fields['task'] = 'transcribe';
      request.fields['temperature'] = '0.0';
      request.fields['best_of'] = '1';
      
      final response = await request.send().timeout(timeout);
      
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final result = jsonDecode(responseData);
        return result['text'] as String? ?? '';
      } else {
        throw Exception('Whisper API error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Transcription failed: $e');
    }
  }

  /// clean up transcription by removing filler words and normalizing
  static String cleanTranscription(String text) {
    if (text.isEmpty) return text;
    
    final fillerWords = [
      'uhh', 'uhm', 'umm', 'uhhhs', 'uhmms', 'errrh', 'errs',
      'uh', 'um', 'er', 'ah', 'like', 'you know', 'I mean',
      'actually', 'basically', 'literally', 'sort of', 'kind of',
      'so', 'well', 'anyway', 'you know what I mean', 'right'
    ];
    
    String cleaned = text.trim();
    
    // Remove filler words with proper spacing
    for (final filler in fillerWords) {
      cleaned = cleaned.replaceAll(RegExp('\\b$filler\\b', caseSensitive: false), '');
    }
    
    // Clean up extra spaces and punctuation
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+([.,!?;:])'), r'\1');
    cleaned = cleaned.replaceAll(RegExp(r'[.,!?;:]+([.,!?;:])'), r'\1');
    
    // Remove leading/trailing punctuation after cleanup
    cleaned = cleaned.replaceAll(RegExp(r'^[.,!?;:\s]+|[.,!?;:\s]+$'), '');
    
    cleaned = cleaned.trim();
    
    // Capitalize first letter and add period if missing
    if (cleaned.isNotEmpty) {
      cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
      if (!RegExp(r'[.!?]$').hasMatch(cleaned)) {
        cleaned += '.';
      }
    }
    
    return cleaned;
  }
}

/// Mock Whisper service for testing when server is unavailable
class MockWhisperService extends WhisperService {
  @override
  Future<bool> isServerAvailable() async {
    // Simulate server check
    await Future.delayed(Duration(milliseconds: 500));
    return true;
  }

  @override
  Future<String> transcribeAudioFile(String audioFilePath) async {
    // Simulate processing time
    await Future.delayed(Duration(seconds: 2));
    
    // Return mock transcription based on time of day
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning. This is a mock transcription from Whisper.';
    } else if (hour < 17) {
      return 'Good afternoon. This is a sample transcription from the Whisper service.';
    } else {
      return 'Good evening. This is a test transcription from Whisper API.';
    }
  }

  @override
  Future<String> transcribeAudioBytes(List<int> audioBytes, String filename) async {
    return await transcribeAudioFile(filename);
  }
}

/// Audio recording simulation for testing
class AudioRecorder {
  bool _isRecording = false;
  Timer? _recordingTimer;
  List<int> _audioBuffer = [];

  /// Start recording (simulated)
  void startRecording() {
    _isRecording = true;
    _audioBuffer.clear();
    
    // Simulate audio data generation
    _recordingTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (_isRecording) {
        // Generate mock audio data
        _audioBuffer.addAll(List.filled(1024, 0));
      }
    });
  }

  /// Stop recording and return audio bytes
  List<int> stopRecording() {
    _isRecording = false;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    
    // Return mock audio data
    return List.from(_audioBuffer);
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Get recording duration
  Duration get recordingDuration {
    if (_recordingTimer == null) return Duration.zero;
    return Duration(milliseconds: _audioBuffer.length ~/ 10);
  }
}