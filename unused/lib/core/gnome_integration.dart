import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GNOME Desktop Environment Integration
///
/// Integrates with GNOME desktop: system notifications via D-Bus,
/// dark/light theme detection and synchronization, workspace management,
/// and system appearance tracking.
class GnomeIntegration {
  bool _isInitialized = false;
  final StreamController<GnomeThemeEvent> _themeController = StreamController<GnomeThemeEvent>.broadcast();
  final StreamController<GnomeNotificationEvent> _notificationController = StreamController<GnomeNotificationEvent>.broadcast();
  GnomeThemeMode _currentTheme = GnomeThemeMode.light;
  GnomeAccentColor _currentAccent = GnomeAccentColor.blue;
  bool _isDarkMode = false;
  Timer? _themeWatchTimer;
  String? _dbusAddress;

  Stream<GnomeThemeEvent> get themeChanges => _themeController.stream;
  Stream<GnomeNotificationEvent> get notifications => _notificationController.stream;
  GnomeThemeMode get currentTheme => _currentTheme;
  GnomeAccentColor get currentAccent => _currentAccent;
  bool get isDarkMode => _isDarkMode;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      _dbusAddress = Platform.environment['DBUS_SESSION_BUS_ADDRESS'];
      await _detectCurrentTheme();
      await _detectAccentColor();
      _themeWatchTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollThemeChanges());
      _isInitialized = true;
      debugPrint('GNOME integration initialized (theme: ${_currentTheme.name})');
    } catch (e) {
      debugPrint('Failed to initialize GNOME integration: $e');
      _isInitialized = true;
    }
  }

  Future<bool> isRunningOnGNOME() async {
    if (Platform.isLinux) {
      final desktopEnv = Platform.environment['XDG_CURRENT_DESKTOP'] ?? '';
      final sessionDesktop = Platform.environment['GDMSESSION'] ?? '';
      return desktopEnv.toLowerCase().contains('gnome') || sessionDesktop.toLowerCase().contains('gnome');
    }
    return false;
  }

  Future<void> sendNotification({
    required String title,
    required String body,
    String? icon,
    int timeoutMs = 5000,
    GnomeNotificationUrgency urgency = GnomeNotificationUrgency.normal,
    List<GnomeNotificationAction>? actions,
  }) async {
    try {
      if (await isRunningOnGNOME()) {
        await _sendDbusNotification(title, body, icon: icon, timeoutMs: timeoutMs, urgency: urgency, actions: actions);
      }
      _notificationController.add(GnomeNotificationEvent(
        title: title,
        body: body,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Failed to send GNOME notification: $e');
    }
  }

  Future<void> _sendDbusNotification(
    String title,
    String body, {
    String? icon,
    int timeoutMs = 5000,
    GnomeNotificationUrgency urgency = GnomeNotificationUrgency.normal,
    List<GnomeNotificationAction>? actions,
  }) async {
    try {
      final result = await Process.run('gdbus', [
        'call', '--session', '--dest', 'org.freedesktop.Notifications',
        '--object-path', '/org/freedesktop/Notifications',
        '--method', 'org.freedesktop.Notifications.Notify',
        'Termisol', '0', icon ?? 'utilities-terminal', title, body,
        actions != null ? json.encode(actions.map((a) => a.toList()).toList()) : '[]',
        json.encode({'urgency': urgency.byteValue}),
        timeoutMs.toString(),
      ]);
      if (result.exitCode != 0) {
        debugPrint('D-Bus notification failed: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('D-Bus notification error: $e');
    }
  }

  Future<GnomeThemeMode> _detectCurrentTheme() async {
    try {
      final isDark = await _detectDarkMode();
      _isDarkMode = isDark;
      _currentTheme = isDark ? GnomeThemeMode.dark : GnomeThemeMode.light;
      return _currentTheme;
    } catch (e) {
      return GnomeThemeMode.light;
    }
  }

  Future<bool> _detectDarkMode() async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('gsettings', ['get', 'org.gnome.desktop.interface', 'color-scheme']);
        final output = result.stdout.toString().trim().toLowerCase();
        if (output.contains('prefer-dark') || output.contains('dark')) {
          return true;
        }
        final gtkResult = await Process.run('gsettings', ['get', 'org.gnome.desktop.interface', 'gtk-theme']);
        final gtkOutput = gtkResult.stdout.toString().trim().toLowerCase();
        if (gtkOutput.contains('dark')) {
          return true;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('gnome_dark_mode') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _detectAccentColor() async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('gsettings', ['get', 'org.gnome.desktop.interface', 'accent-color']);
        final output = result.stdout.toString().trim().toLowerCase();
        _currentAccent = _parseAccentColor(output);
      }
    } catch (e) {
      _currentAccent = GnomeAccentColor.blue;
    }
  }

  GnomeAccentColor _parseAccentColor(String value) {
    for (final color in GnomeAccentColor.values) {
      if (value.contains(color.name)) return color;
    }
    return GnomeAccentColor.blue;
  }

  Future<void> _pollThemeChanges() async {
    try {
      final wasDark = _isDarkMode;
      await _detectCurrentTheme();
      if (wasDark != _isDarkMode) {
        _themeController.add(GnomeThemeEvent(
          mode: _currentTheme,
          accent: _currentAccent,
          isDark: _isDarkMode,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      // Silently ignore polling errors
    }
  }

  Future<List<GnomeWorkspace>> getWorkspaces() async {
    try {
      if (!Platform.isLinux) return [];
      final result = await Process.run('gsettings', ['get', 'org.gnome.desktop.wm.preferences', 'num-workspaces']);
      final count = int.tryParse(result.stdout.toString().trim()) ?? 1;
      return List.generate(count, (i) => GnomeWorkspace(id: i, name: 'Workspace ${i + 1}', active: false));
    } catch (e) {
      return [GnomeWorkspace(id: 0, name: 'Workspace 1', active: true)];
    }
  }

  Future<int?> getActiveWorkspace() async {
    try {
      if (!Platform.isLinux) return null;
      final result = await Process.run('xdotool', ['get_desktop']);
      return int.tryParse(result.stdout.toString().trim());
    } catch (e) {
      return null;
    }
  }

  Future<bool> switchWorkspace(int workspaceId) async {
    try {
      final result = await Process.run('xdotool', ['set_desktop', workspaceId.toString()]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  Future<String?> getSystemFont() async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('gsettings', ['get', 'org.gnome.desktop.interface', 'monospace-font-name']);
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return output.replaceAll("'", "").split(' ').first;
        }
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  Future<double> getSystemFontScaling() async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('gsettings', ['get', 'org.gnome.desktop.interface', 'text-scaling-factor']);
        return double.tryParse(result.stdout.toString().trim()) ?? 1.0;
      }
    } catch (e) {
      // Ignore
    }
    return 1.0;
  }

  Future<Map<String, String>> getSystemColors() async {
    final colors = <String, String>{};
    try {
      if (!Platform.isLinux) return colors;
      final keys = ['background-color', 'foreground-color', 'cursor-color', 'selection-background-color', 'selection-foreground-color'];
      for (final key in keys) {
        final result = await Process.run('gsettings', ['get', 'org.gnome.Terminal.ProfilesList', key]);
        colors[key] = result.stdout.toString().trim();
      }
    } catch (e) {
      // Ignore
    }
    return colors;
  }

  Future<void> setDarkMode(bool dark) async {
    try {
      if (Platform.isLinux) {
        final scheme = dark ? 'prefer-dark' : 'prefer-light';
        await Process.run('gsettings', ['set', 'org.gnome.desktop.interface', 'color-scheme', scheme]);
      }
      _isDarkMode = dark;
      _currentTheme = dark ? GnomeThemeMode.dark : GnomeThemeMode.light;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('gnome_dark_mode', dark);
      _themeController.add(GnomeThemeEvent(
        mode: _currentTheme,
        accent: _currentAccent,
        isDark: dark,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Failed to set dark mode: $e');
    }
  }

  void dispose() {
    _themeWatchTimer?.cancel();
    _themeController.close();
    _notificationController.close();
  }
}

enum GnomeThemeMode { light, dark }
enum GnomeAccentColor { blue, teal, green, yellow, orange, red, pink, purple, slate }
enum GnomeNotificationUrgency { low, normal, critical }

extension GnomeNotificationUrgencyExt on GnomeNotificationUrgency {
  int get byteValue {
    switch (this) {
      case GnomeNotificationUrgency.low: return 0;
      case GnomeNotificationUrgency.normal: return 1;
      case GnomeNotificationUrgency.critical: return 2;
    }
  }
}

class GnomeThemeEvent {
  final GnomeThemeMode mode;
  final GnomeAccentColor accent;
  final bool isDark;
  final DateTime timestamp;

  GnomeThemeEvent({
    required this.mode,
    required this.accent,
    required this.isDark,
    required this.timestamp,
  });
}

class GnomeNotificationEvent {
  final String title;
  final String body;
  final DateTime timestamp;

  GnomeNotificationEvent({
    required this.title,
    required this.body,
    required this.timestamp,
  });
}

class GnomeNotificationAction {
  final String id;
  final String label;

  GnomeNotificationAction({required this.id, required this.label});

  List<dynamic> toList() => [id, label];
}

class GnomeWorkspace {
  final int id;
  final String name;
  bool active;

  GnomeWorkspace({required this.id, required this.name, this.active = false});
}