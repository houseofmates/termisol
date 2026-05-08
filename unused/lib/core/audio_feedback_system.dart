import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:xterm/xterm.dart';

/// Audio Feedback System - Smart notification sounds for terminal events
/// 
/// Implements comprehensive audio feedback:
/// - Command completion notifications
/// - Hermes agent completion detection
/// - Long-running command alerts
/// - Error and success sounds
/// - Customizable audio profiles
class AudioFeedbackSystem {
  bool _isInitialized = false;
  AudioPlayer? _audioPlayer;
  AudioCache? _audioCache;
  
  // Audio state
  bool _soundEnabled = true;
  double _volume = 0.5;
  bool _isPlaying = false;
  
  // Command tracking
  final Map<String, DateTime> _commandStartTimes = {};
  final Map<String, Timer> _commandTimers = {};
  final Duration _longCommandThreshold = const Duration(seconds: 5);
  
  // Hermes detection
  final List<String> _hermesCommands = [
    'hermes',
    'hermes ssh',
    'hermes-webui',
    'python3 server.py',
  ];
  
  // Audio file paths
  String _notificationSound = 'assets/audio/notif.mp3';
  String _errorSound = 'assets/audio/error.mp3';
  String _successSound = 'assets/audio/success.mp3';
  String _longCommandSound = 'assets/audio/long_command.mp3';
  
  // Audio profiles
  Map<String, AudioProfile> _audioProfiles = {};
  String _currentProfile = 'default';
  
  AudioFeedbackSystem();
  
  bool get isInitialized => _isInitialized;
  bool get soundEnabled => _soundEnabled;
  double get volume => _volume;
  bool get isPlaying => _isPlaying;
  String get currentProfile => _currentProfile;
  
  /// Initialize audio feedback system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize audio player
      _audioPlayer = AudioPlayer();
      _audioCache = AudioCache(prefix: 'assets/audio/');
      
      // Setup audio player listeners
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        _isPlaying = state == PlayerState.playing;
      });
      
      // Load default audio profiles
      await _loadDefaultProfiles();
      
      // Check if notification sound exists
      await _ensureNotificationSound();
      
      _isInitialized = true;
      debugPrint('🔊 Audio Feedback System initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Audio Feedback System: $e');
      // Continue without audio rather than crash
      _soundEnabled = false;
    }
  }
  
  /// Load default audio profiles
  Future<void> _loadDefaultProfiles() async {
    _audioProfiles = {
      'default': AudioProfile(
        name: 'Default',
        notificationSound: _notificationSound,
        errorSound: _errorSound,
        successSound: _successSound,
        longCommandSound: _longCommandSound,
        volume: 0.5,
        enabled: true,
      ),
      'minimal': AudioProfile(
        name: 'Minimal',
        notificationSound: _notificationSound,
        errorSound: null, // No error sound
        successSound: null, // No success sound
        longCommandSound: null, // No long command sound
        volume: 0.3,
        enabled: true,
      ),
      'verbose': AudioProfile(
        name: 'Verbose',
        notificationSound: _notificationSound,
        errorSound: _errorSound,
        successSound: _successSound,
        longCommandSound: _longCommandSound,
        volume: 0.7,
        enabled: true,
      ),
      'silent': AudioProfile(
        name: 'Silent',
        notificationSound: null,
        errorSound: null,
        successSound: null,
        longCommandSound: null,
        volume: 0.0,
        enabled: false,
      ),
    };
  }
  
  /// Ensure notification sound exists
  Future<void> _ensureNotificationSound() async {
    try {
      final file = File(_notificationSound);
      if (!await file.exists()) {
        // Create default notification sound if it doesn't exist
        await _createDefaultNotificationSound();
      }
    } catch (e) {
      debugPrint('⚠️ Could not verify notification sound: $e');
    }
  }
  
  /// Create default notification sound
  Future<void> _createDefaultNotificationSound() async {
    try {
      // Create a simple beep sound using system beep
      debugPrint('🔊 Creating default notification sound');
      // In a real implementation, you would generate or copy a sound file
    } catch (e) {
      debugPrint('⚠️ Could not create default notification sound: $e');
    }
  }
  
  /// Track command start
  void trackCommandStart(String command, String sessionId) {
    if (!_soundEnabled || !_isInitialized) return;
    
    final commandId = '$sessionId:$command';
    _commandStartTimes[commandId] = DateTime.now();
    
    // Set timer for long command detection
    _commandTimers[commandId] = Timer(_longCommandThreshold, () {
      _onLongCommand(command, sessionId);
    });
    
    debugPrint('⏱️ Tracking command: $command');
  }
  
  /// Track command completion
  void trackCommandComplete(String command, String sessionId, {bool success = true}) {
    if (!_soundEnabled || !_isInitialized) return;
    
    final commandId = '$sessionId:$command';
    final startTime = _commandStartTimes[commandId];
    
    // Cancel long command timer
    _commandTimers[commandId]?.cancel();
    _commandTimers.remove(commandId);
    
    // Check if this is a Hermes command
    final isHermesCommand = _isHermesCommand(command);
    final wasLongCommand = startTime != null && 
        DateTime.now().difference(startTime) > _longCommandThreshold;
    
    // Play appropriate sound
    if (isHermesCommand || wasLongCommand) {
      _playNotificationSound();
      debugPrint('🔊 Played notification for ${isHermesCommand ? 'Hermes' : 'long'} command: $command');
    } else if (!success) {
      _playErrorSound();
      debugPrint('🔊 Played error sound for failed command: $command');
    }
    
    // Clean up
    _commandStartTimes.remove(commandId);
  }
  
  /// Check if command is Hermes-related
  bool _isHermesCommand(String command) {
    final lowerCommand = command.toLowerCase().trim();
    return _hermesCommands.any((hermesCmd) => lowerCommand.contains(hermesCmd.toLowerCase()));
  }
  
  /// Handle long command detection
  void _onLongCommand(String command, String sessionId) {
    if (!_soundEnabled || !_isInitialized) return;
    
    _playLongCommandSound();
    debugPrint('🔊 Played long command sound for: $command');
  }
  
  /// Play notification sound
  Future<void> _playNotificationSound() async {
    if (!_soundEnabled || !_isInitialized) return;
    
    try {
      final profile = _audioProfiles[_currentProfile];
      if (profile?.notificationSound != null) {
        await _audioPlayer!.play(AssetSource(profile!.notificationSound!));
      } else {
        // Fallback to system beep
        await _playSystemBeep();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to play notification sound: $e');
      await _playSystemBeep();
    }
  }
  
  /// Play error sound
  Future<void> _playErrorSound() async {
    if (!_soundEnabled || !_isInitialized) return;
    
    try {
      final profile = _audioProfiles[_currentProfile];
      if (profile?.errorSound != null) {
        await _audioPlayer!.play(AssetSource(profile!.errorSound!));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to play error sound: $e');
    }
  }
  
  /// Play success sound
  Future<void> _playSuccessSound() async {
    if (!_soundEnabled || !_isInitialized) return;
    
    try {
      final profile = _audioProfiles[_currentProfile];
      if (profile?.successSound != null) {
        await _audioPlayer!.play(AssetSource(profile!.successSound!));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to play success sound: $e');
    }
  }
  
  /// Play long command sound
  Future<void> _playLongCommandSound() async {
    if (!_soundEnabled || !_isInitialized) return;
    
    try {
      final profile = _audioProfiles[_currentProfile];
      if (profile?.longCommandSound != null) {
        await _audioPlayer!.play(AssetSource(profile!.longCommandSound!));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to play long command sound: $e');
    }
  }
  
  /// Play system beep as fallback
  Future<void> _playSystemBeep() async {
    try {
      // Use system beep
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint('⚠️ Failed to play system beep: $e');
    }
  }
  
  /// Play custom sound
  Future<void> playCustomSound(String soundPath) async {
    if (!_soundEnabled || !_isInitialized) return;
    
    try {
      if (soundPath.startsWith('assets/')) {
        await _audioPlayer!.play(AssetSource(soundPath));
      } else {
        await _audioPlayer!.play(DeviceFileSource(soundPath));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to play custom sound: $e');
    }
  }
  
  /// Enable/disable sound
  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
    debugPrint('🔊 Sound ${enabled ? 'enabled' : 'disabled'}');
  }
  
  /// Set volume
  Future<void> setVolume(double volume) async {
    if (volume < 0.0) volume = 0.0;
    if (volume > 1.0) volume = 1.0;
    
    _volume = volume;
    
    if (_audioPlayer != null) {
      await _audioPlayer!.setVolume(volume);
    }
    
    debugPrint('🔊 Volume set to ${(volume * 100).toInt()}%');
  }
  
  /// Set audio profile
  void setAudioProfile(String profileName) {
    if (_audioProfiles.containsKey(profileName)) {
      _currentProfile = profileName;
      final profile = _audioProfiles[profileName]!;
      _soundEnabled = profile.enabled;
      setVolume(profile.volume);
      debugPrint('🔊 Audio profile set to: $profileName');
    } else {
      debugPrint('⚠️ Audio profile not found: $profileName');
    }
  }
  
  /// Add custom audio profile
  void addAudioProfile(String name, AudioProfile profile) {
    _audioProfiles[name] = profile;
    debugPrint('🔊 Added audio profile: $name');
  }
  
  /// Get available audio profiles
  List<String> getAvailableProfiles() {
    return _audioProfiles.keys.toList();
  }
  
  /// Get current audio profile
  AudioProfile? getCurrentProfile() {
    return _audioProfiles[_currentProfile];
  }
  
  /// Test notification sound
  Future<void> testNotificationSound() async {
    await _playNotificationSound();
  }
  
  /// Test error sound
  Future<void> testErrorSound() async {
    await _playErrorSound();
  }
  
  /// Test success sound
  Future<void> testSuccessSound() async {
    await _playSuccessSound();
  }
  
  /// Test long command sound
  Future<void> testLongCommandSound() async {
    await _playLongCommandSound();
  }
  
  /// Stop all sounds
  Future<void> stopAllSounds() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.stop();
    }
    
    // Cancel all timers
    for (final timer in _commandTimers.values) {
      timer.cancel();
    }
    _commandTimers.clear();
    
    debugPrint('🔊 Stopped all sounds');
  }
  
  /// Clean up completed command tracking
  void cleanupCompletedCommands() {
    final now = DateTime.now();
    final expiredCommands = <String>[];
    
    for (final entry in _commandStartTimes.entries) {
      if (now.difference(entry.value) > const Duration(minutes: 30)) {
        expiredCommands.add(entry.key);
      }
    }
    
    for (final commandId in expiredCommands) {
      _commandStartTimes.remove(commandId);
      _commandTimers[commandId]?.cancel();
      _commandTimers.remove(commandId);
    }
    
    if (expiredCommands.isNotEmpty) {
      debugPrint('🧹 Cleaned up ${expiredCommands.length} expired command trackers');
    }
  }
  
  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'soundEnabled': _soundEnabled,
      'volume': _volume,
      'isPlaying': _isPlaying,
      'currentProfile': _currentProfile,
      'activeCommands': _commandStartTimes.length,
      'activeTimers': _commandTimers.length,
      'availableProfiles': _audioProfiles.keys.toList(),
    };
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    // Cancel all timers
    for (final timer in _commandTimers.values) {
      timer.cancel();
    }
    _commandTimers.clear();
    
    // Stop audio player
    if (_audioPlayer != null) {
      await _audioPlayer!.dispose();
      _audioPlayer = null;
    }
    
    _audioCache = null;
    _commandStartTimes.clear();
    _audioProfiles.clear();
    
    _isInitialized = false;
    debugPrint('🔊 Audio Feedback System disposed');
  }
}

/// Audio profile configuration
class AudioProfile {
  final String name;
  final String? notificationSound;
  final String? errorSound;
  final String? successSound;
  final String? longCommandSound;
  final double volume;
  final bool enabled;
  
  AudioProfile({
    required this.name,
    this.notificationSound,
    this.errorSound,
    this.successSound,
    this.longCommandSound,
    required this.volume,
    required this.enabled,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'notificationSound': notificationSound,
      'errorSound': errorSound,
      'successSound': successSound,
      'longCommandSound': longCommandSound,
      'volume': volume,
      'enabled': enabled,
    };
  }
  
  factory AudioProfile.fromJson(Map<String, dynamic> json) {
    return AudioProfile(
      name: json['name'],
      notificationSound: json['notificationSound'],
      errorSound: json['errorSound'],
      successSound: json['successSound'],
      longCommandSound: json['longCommandSound'],
      volume: json['volume']?.toDouble() ?? 0.5,
      enabled: json['enabled'] ?? true,
    );
  }
  
  @override
  String toString() {
    return 'AudioProfile(name: $name, volume: $volume, enabled: $enabled)';
  }
}

/// Terminal output analyzer for audio feedback
class TerminalOutputAnalyzer {
  final AudioFeedbackSystem _audioSystem;
  final Map<String, StringBuffer> _sessionBuffers = {};
  final Map<String, DateTime> _lastOutputTimes = {};
  
  TerminalOutputAnalyzer(this._audioSystem);
  
  /// Analyze terminal output for command completion
  void analyzeOutput(String output, String sessionId) {
    // Update session buffer
    _sessionBuffers[sessionId] ??= StringBuffer();
    _sessionBuffers[sessionId]!.write(output);
    _lastOutputTimes[sessionId] = DateTime.now();
    
    // Check for command completion patterns
    if (_isCommandComplete(output)) {
      _onCommandComplete(output, sessionId);
    }
    
    // Check for Hermes completion patterns
    if (_isHermesComplete(output)) {
      _onHermesComplete(output, sessionId);
    }
  }
  
  /// Check if output indicates command completion
  bool _isCommandComplete(String output) {
    final patterns = [
      RegExp(r'\$\s*$'), // Shell prompt
      RegExp(r'#\s*$'), // Root prompt
      RegExp(r'>\s*$'), // Secondary prompt
      RegExp(r'[\r\n]+[a-zA-Z0-9._-]+@[\w.-]+:[^\$#]+[\$#]\s*$'), // Full prompt
    ];
    
    return patterns.any((pattern) => pattern.hasMatch(output));
  }
  
  /// Check if output indicates Hermes completion
  bool _isHermesComplete(String output) {
    final patterns = [
      RegExp(r'Hermes.*completed', caseSensitive: false),
      RegExp(r'Task.*finished', caseSensitive: false),
      RegExp(r'All.*done', caseSensitive: false),
      RegExp(r'Process.*completed', caseSensitive: false),
      RegExp(r'✓.*All.*tasks.*completed', caseSensitive: false),
      RegExp(r'Server.*running.*on.*port', caseSensitive: false),
      RegExp(r'WebUI.*available.*at', caseSensitive: false),
    ];
    
    return patterns.any((pattern) => pattern.hasMatch(output));
  }
  
  /// Handle command completion
  void _onCommandComplete(String output, String sessionId) {
    // Extract the last command from buffer
    final buffer = _sessionBuffers[sessionId]?.toString() ?? '';
    final lastCommand = _extractLastCommand(buffer);
    
    if (lastCommand.isNotEmpty) {
      final success = !_isErrorOutput(output);
      _audioSystem.trackCommandComplete(lastCommand, sessionId, success: success);
    }
    
    // Clear buffer for next command
    _sessionBuffers[sessionId] = StringBuffer();
  }
  
  /// Handle Hermes completion
  void _onHermesComplete(String output, String sessionId) {
    // Play notification sound for Hermes completion
    _audioSystem.trackCommandComplete('hermes', sessionId, success: true);
    
    // Clear buffer
    _sessionBuffers[sessionId] = StringBuffer();
  }
  
  /// Extract last command from buffer
  String _extractLastCommand(String buffer) {
    final lines = buffer.split('\n');
    
    // Find the last line that looks like a command
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isNotEmpty && !line.startsWith('$') && !line.startsWith('#')) {
        return line;
      }
    }
    
    return '';
  }
  
  /// Check if output indicates error
  bool _isErrorOutput(String output) {
    final errorPatterns = [
      RegExp(r'error:', caseSensitive: false),
      RegExp(r'failed', caseSensitive: false),
      RegExp(r'command not found', caseSensitive: false),
      RegExp(r'permission denied', caseSensitive: false),
      RegExp(r'no such file', caseSensitive: false),
      RegExp(r'cannot', caseSensitive: false),
      RegExp(r'unable to', caseSensitive: false),
    ];
    
    return errorPatterns.any((pattern) => pattern.hasMatch(output));
  }
  
  /// Clean up old session data
  void cleanupOldSessions() {
    final now = DateTime.now();
    final expiredSessions = <String>[];
    
    for (final entry in _lastOutputTimes.entries) {
      if (now.difference(entry.value) > const Duration(hours: 1)) {
        expiredSessions.add(entry.key);
      }
    }
    
    for (final sessionId in expiredSessions) {
      _sessionBuffers.remove(sessionId);
      _lastOutputTimes.remove(sessionId);
    }
  }
  
  /// Dispose analyzer
  void dispose() {
    _sessionBuffers.clear();
    _lastOutputTimes.clear();
  }
}
