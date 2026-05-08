import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:termisol/core/logging_system.dart';

/// Long command notification system
/// 
/// Features:
/// - Audio notification for long-running commands
/// - Configurable timeout (default 40 seconds)
/// - Progress indication
/// - Command cancellation support
class LongCommandNotifier {
  static const Duration _defaultTimeout = Duration(seconds: 40);
  static const String _notificationFile = 'termisol_long_commands.log';
  
  final Map<String, Timer> _activeCommands = {};
  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;

  LongCommandNotifier() {
    // Skip audio initialization in tests
    if (const bool.fromEnvironment('FLUTTER_TEST', defaultValue: false)) {
      _audioPlayer = null;
      _isInitialized = true;
      return;
    }

    try {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.setPlayerMode(PlayerMode.lowLatency);
      _isInitialized = true;
    } catch (e) {
      // Audio not available
      _audioPlayer = null;
      _isInitialized = true;
    }
  }

  /// Notify about long-running command
  Future<void> notifyLongCommand(String command, {Duration? timeout}) async {
    final commandTimeout = timeout ?? _defaultTimeout;
    
    // Create log entry
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] LONG_COMMAND: $command\n';
    
    try {
      final logFile = File(_notificationFile);
      await logFile.writeAsString(logEntry, mode: FileMode.append);
      
      // Play notification sound after 30 seconds
      Timer(const Duration(seconds: 30), () async {
        try {
            await _audioPlayer?.setSourceAsset('assets/notif.mp3');
            await _audioPlayer?.resume();
        } catch (e) {
          TermisolLogger().error('Failed to play notification sound', error: e);
        }
      });
      
      // Schedule notification after timeout
      _activeCommands[command] = Timer(commandTimeout, () async {
        await _audioPlayer?.setSourceAsset('assets/notif.mp3');
        await _audioPlayer?.resume();
      });
    } catch (e) {
      TermisolLogger().error('Failed to log long command', error: e);
    }
  }

  /// Cancel notification for command
  void cancelNotification(String command) {
    final timer = _activeCommands[command];
    if (timer != null) {
      timer.cancel();
      _activeCommands.remove(command);
    }
  }

  /// Check if command is still running
  bool isCommandRunning(String command) {
    final timer = _activeCommands[command];
    return timer?.isActive ?? false;
  }

  /// Get active long commands
  Map<String, bool> get activeCommands {
    return Map.fromEntries(
      _activeCommands.entries.map((entry) => MapEntry(entry.key, entry.value?.isActive ?? false)),
    );
  }

  /// Dispose resources
  void dispose() {
    // Cancel all active timers
    for (final timer in _activeCommands.values) {
      timer?.cancel();
    }
    _activeCommands.clear();
    
    _audioPlayer?.dispose();
    _isInitialized = false;
  }
}
