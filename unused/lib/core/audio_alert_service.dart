import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// Audio Alert Service
///
/// Plays configurable audio alerts for terminal events: command completion,
/// long-running task finish, errors, and custom notifications.
class AudioAlertService {
  final AudioPlayer _player = AudioPlayer();
  final Map<String, AlertProfile> _profiles = {};
  final Map<String, AlertEvent> _events = {};
  AlertProfile? _activeProfile;
  bool _muted = false;
  double _volume = 0.7;
  final StreamController<AlertEvent> _eventController = StreamController<AlertEvent>.broadcast();

  Stream<AlertEvent> get alerts => _eventController.stream;
  bool get isMuted => _muted;

  Future<void> initialize() async {
    _loadDefaultProfiles();
    _activeProfile = _profiles['default'];
    debugPrint('AudioAlertService initialized');
  }

  void addProfile(AlertProfile profile) {
    _profiles[profile.name] = profile;
  }

  void setActiveProfile(String name) {
    _activeProfile = _profiles[name] ?? _activeProfile;
  }

  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      _player.stop();
    }
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _player.setVolume(_volume);
  }

  Future<void> playAlert(AlertType type, {String? customSound, double? volume}) async {
    if (_muted) return;

    final profile = _activeProfile;
    if (profile == null) return;

    String? soundAsset;

    switch (type) {
      case AlertType.commandComplete:
        soundAsset = profile.commandCompleteSound;
        break;
      case AlertType.taskComplete:
        soundAsset = profile.taskCompleteSound;
        break;
      case AlertType.error:
        soundAsset = profile.errorSound;
        break;
      case AlertType.notification:
        soundAsset = profile.notificationSound;
        break;
      case AlertType.bell:
        soundAsset = profile.bellSound;
        break;
      case AlertType.warning:
        soundAsset = profile.warningSound;
        break;
      case AlertType.success:
        soundAsset = profile.successSound;
        break;
    }

    soundAsset ??= customSound;

    if (soundAsset == null) return;

    try {
      await _player.setVolume(volume ?? _volume);
      if (soundAsset.startsWith('assets/')) {
        await _player.play(AssetSource(soundAsset));
      } else {
        await _player.play(UrlSource(soundAsset));
      }

      final event = AlertEvent(type: type, soundAsset: soundAsset);
      _events[type.name] = event;
      _eventController.add(event);
    } catch (e) {
      debugPrint('Failed to play alert sound: $e');
    }
  }

  Future<void> playCommandComplete() => playAlert(AlertType.commandComplete);
  Future<void> playTaskComplete() => playAlert(AlertType.taskComplete);
  Future<void> playError() => playAlert(AlertType.error);
  Future<void> playNotification() => playAlert(AlertType.notification);
  Future<void> playBell() => playAlert(AlertType.bell);
  Future<void> playWarning() => playAlert(AlertType.warning);
  Future<void> playSuccess() => playAlert(AlertType.success);

  Future<void> playTerminalBell() async {
    await _player.setVolume(_volume);
    await _player.play(AssetSource('assets/sounds/bell.wav'));
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _eventController.close();
  }

  void _loadDefaultProfiles() {
    _profiles['default'] = AlertProfile(
      name: 'default',
      commandCompleteSound: 'assets/sounds/complete.wav',
      taskCompleteSound: 'assets/sounds/complete.wav',
      errorSound: 'assets/sounds/error.wav',
      notificationSound: 'assets/sounds/notification.wav',
      bellSound: 'assets/sounds/bell.wav',
      warningSound: 'assets/sounds/warning.wav',
      successSound: 'assets/sounds/success.wav',
    );

    _profiles['minimal'] = AlertProfile(
      name: 'minimal',
      commandCompleteSound: null,
      taskCompleteSound: 'assets/sounds/complete.wav',
      errorSound: null,
      notificationSound: null,
      bellSound: 'assets/sounds/bell.wav',
    );

    _profiles['intrusive'] = AlertProfile(
      name: 'intrusive',
      commandCompleteSound: 'assets/sounds/complete.wav',
      taskCompleteSound: 'assets/sounds/complete.wav',
      errorSound: 'assets/sounds/error.wav',
      notificationSound: 'assets/sounds/notification.wav',
      bellSound: 'assets/sounds/bell.wav',
      warningSound: 'assets/sounds/warning.wav',
      successSound: 'assets/sounds/success.wav',
    );
  }
}

enum AlertType { commandComplete, taskComplete, error, notification, bell, warning, success }

class AlertProfile {
  final String name;
  final String? commandCompleteSound;
  final String? taskCompleteSound;
  final String? errorSound;
  final String? notificationSound;
  final String? bellSound;
  final String? warningSound;
  final String? successSound;

  AlertProfile({
    required this.name,
    this.commandCompleteSound,
    this.taskCompleteSound,
    this.errorSound,
    this.notificationSound,
    this.bellSound,
    this.warningSound,
    this.successSound,
  });
}

class AlertEvent {
  final AlertType type;
  final String soundAsset;
  final DateTime timestamp;

  AlertEvent({required this.type, required this.soundAsset})
      : timestamp = DateTime.now();
}