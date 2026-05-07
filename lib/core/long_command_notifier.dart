import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

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
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  LongCommandNotifier() {
    _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
    _isInitialized = true;
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
          await _audioPlayer.play(AssetSource.asset('assets/notif.mp3'));
        } catch (e) {
          print('Failed to play notification sound: $e');
        }
      });
      
      // Schedule notification after timeout
      _activeCommands[command] = Timer(commandTimeout, () async {
        await _audioPlayer.play(AssetSource.asset('assets/notif.mp3'));
      });
    } catch (e) {
      print('Failed to log long command: $e');
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
    
    _audioPlayer.dispose();
    _isInitialized = false;
  }
}
