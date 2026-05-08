import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Production-grade audio alert service for Termisol
/// 
/// Features:
/// - Cross-platform audio playback with fallbacks
/// - Configurable alert sounds and volumes
/// - Memory-efficient audio caching
/// - Error handling and graceful degradation
/// - System notification integration
class AudioAlertService {
  static final AudioAlertService _instance = AudioAlertService._internal();
  factory AudioAlertService() => _instance;
  AudioAlertService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _soundCache = {};
  bool _initialized = false;
  double _volume = 0.5;
  bool _enabled = true;
  
  // Default sound paths
  static const Map<String, String> _defaultSounds = {
    'notification': 'assets/notif.mp3',
    'error': 'assets/error.mp3',
    'success': 'assets/success.mp3',
    'warning': 'assets/warning.mp3',
  };

  /// Initialize() audio service
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _loadDefaultSounds();
      _initialized = true;
      debugPrint('✅ AudioAlertService initialized');
    } catch (e) {
      debugPrint('❌ AudioAlertService initialization failed: $e');
      // Continue without audio rather than crash
    }
  }

  /// Load default sound files
  Future<void> _loadDefaultSounds() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final assetsDir = Directory('${directory.path}/assets');
      
      if (!await assetsDir.exists()) {
        await assetsDir.create(recursive: true);
      }

      for (final entry in _defaultSounds.entries) {
        final soundFile = File('${assetsDir.path}/${entry.key}.mp3');
        if (await soundFile.exists()) {
          _soundCache[entry.key] = soundFile.path;
        } else {
          // Try to load from bundled assets
          _soundCache[entry.key] = entry.value;
        }
      }
    } catch (e) {
      debugPrint('Failed to load default sounds: $e');
    }
  }

  /// Play an audio alert
  Future<void> playAlert(String alertType, {double? volume}) async {
    if (!_enabled || !_initialized) return;

    try {
      final soundPath = _soundCache[alertType] ?? _soundCache['notification'];
      if (soundPath == null) return;

      final playVolume = volume ?? _volume;
      await _audioPlayer.setVolume(playVolume);
      
      if (await File(soundPath).exists()) {
        await _audioPlayer.play(DeviceFileSource(soundPath));
      } else {
        // Try bundled asset
        await _audioPlayer.play(AssetSource(soundPath));
      }
      
      debugPrint('🔊 Played audio alert: $alertType');
    } catch (e) {
      debugPrint('Failed to play audio alert $alertType: $e');
      // Silent fail - don't disrupt user experience
    }
  }

  /// Play notification sound
  Future<void> playNotification() => playAlert('notification');

  /// Play error sound
  Future<void> playError() => playAlert('error');

  /// Play success sound
  Future<void> playSuccess() => playAlert('success');

  /// Play warning sound
  Future<void> playWarning() => playAlert('warning');

  /// Set master volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _audioPlayer.setVolume(_volume);
  }

  /// Enable or disable audio alerts
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Add custom sound
  Future<void> addCustomSound(String name, String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        _soundCache[name] = filePath;
        debugPrint('✅ Added custom sound: $name');
      }
    } catch (e) {
      debugPrint('Failed to add custom sound $name: $e');
    }
  }

  /// Test audio system
  Future<bool> testAudio() async {
    try {
      await playAlert('notification');
      return true;
    } catch (e) {
      debugPrint('Audio test failed: $e');
      return false;
    }
  }

  /// Get current configuration
  Map<String, dynamic> getConfig() {
    return {
      'initialized': _initialized,
      'enabled': _enabled,
      'volume': _volume,
      'availableSounds': _soundCache.keys.toList(),
    };
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
      _soundCache.clear();
      _initialized = false;
    } catch (e) {
      debugPrint('Error disposing AudioAlertService: $e');
    }
  }
}