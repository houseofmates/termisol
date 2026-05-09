import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:termisol/core/logging_system.dart';

/// Long command notification system.
class LongCommandNotifier extends ChangeNotifier {
  static const Duration _defaultTimeout = Duration(seconds: 40);
  static const String _notificationFile = 'termisol_long_commands.log';

  final Map<String, Timer> _activeCommands = {};
  final List<Timer> _soundTimers = [];
  AudioPlayer? _audioPlayer;

  LongCommandNotifier() {
    if (const bool.fromEnvironment('FLUTTER_TEST')) {
      _audioPlayer = null;
      return;
    }

    try {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.setPlayerMode(PlayerMode.lowLatency);
    } on Exception catch (e, stack) {
      if (kDebugMode) debugPrint('AudioPlayer init failed: $e\n$stack');
      _audioPlayer = null;
    }
  }

  Future<void> notifyLongCommand(String command, {Duration? timeout}) async {
    final commandTimeout = timeout ?? _defaultTimeout;

    // Cancel any existing timer for this command.
    _activeCommands[command]?.cancel();
    _activeCommands.remove(command);

    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] LONG_COMMAND: $command\n';

    try {
      final logFile = File(_notificationFile);
      await logFile.writeAsString(logEntry, mode: FileMode.append);
    } on Exception catch (e, stack) {
      TermisolLogger().severe('Failed to log long command', null, e);
      if (kDebugMode) debugPrint('Long command log failed: $e\n$stack');
    }

    // Play notification sound after 30 seconds.
    final soundTimer = Timer(const Duration(seconds: 30), () async {
      try {
        await _audioPlayer?.setSourceAsset('assets/notif.mp3');
        await _audioPlayer?.resume();
      } on Exception catch (e, stack) {
        TermisolLogger().severe('Failed to play notification sound', null, e);
        if (kDebugMode) debugPrint('Notification sound failed: $e\n$stack');
      }
    });
    _soundTimers.add(soundTimer);

    // Schedule notification after timeout.
    _activeCommands[command] = Timer(commandTimeout, () async {
      try {
        await _audioPlayer?.setSourceAsset('assets/notif.mp3');
        await _audioPlayer?.resume();
      } on Exception catch (e, stack) {
        if (kDebugMode) debugPrint('Timeout sound failed: $e\n$stack');
      }
      _activeCommands.remove(command);
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelNotification(String command) {
    final timer = _activeCommands[command];
    if (timer != null) {
      timer.cancel();
      _activeCommands.remove(command);
      notifyListeners();
    }
  }

  bool isCommandRunning(String command) {
    final timer = _activeCommands[command];
    return timer?.isActive ?? false;
  }

  Map<String, bool> get activeCommands {
    return Map.fromEntries(
      _activeCommands.entries.map((entry) => MapEntry(entry.key, entry.value.isActive)),
    );
  }

  @override
  void dispose() {
    for (final timer in _activeCommands.values) {
      timer.cancel();
    }
    _activeCommands.clear();

    for (final timer in _soundTimers) {
      timer.cancel();
    }
    _soundTimers.clear();

    _audioPlayer?.dispose();
    super.dispose();
  }
}
