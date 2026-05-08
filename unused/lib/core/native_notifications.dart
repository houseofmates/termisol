import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Native notifications with custom sound support
/// Uses notif.mp3 for notification sound
class NativeNotifications {
  static const String _notificationSoundPath = 'assets/notif.mp3';
  static NativeNotifications? _instance;
  late AudioPlayer _audioPlayer;
  late SharedPreferences _prefs;
  bool _isInitialized = false;
  final StreamController<NotificationEvent> _eventController = StreamController<NotificationEvent>.broadcast();
  
  Stream<NotificationEvent> get events => _eventController.stream;

  static NativeNotifications get instance {
    _instance ??= NativeNotifications._();
    return _instance!;
  }

  NativeNotifications._() {
    _audioPlayer = AudioPlayer();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      
      // Preload the notification sound
      await _preloadNotificationSound();
      
      // Initialize platform-specific notification services
      await _initializePlatformNotifications();
      
      _isInitialized = true;
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.initialized,
        message: 'Native notifications initialized',
        data: {'soundPath': _notificationSoundPath},
      ));
      
      debugPrint('🔔 Native Notifications initialized');
    } catch (e) {
      debugPrint('Failed to initialize native notifications: $e');
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to initialize: $e',
      ));
    }
  }

  Future<void> _preloadNotificationSound() async {
    try {
      // Try to load the notification sound from assets
      await _audioPlayer.setSource(AssetSource(_notificationSoundPath));
      debugPrint('🔊 Notification sound preloaded: $_notificationSoundPath');
    } catch (e) {
      debugPrint('Failed to preload notification sound: $e');
      // Continue without sound if asset not found
    }
  }

  Future<void> _initializePlatformNotifications() async {
    if (Platform.isLinux) {
      await _initializeLinuxNotifications();
    } else if (Platform.isWindows) {
      await _initializeWindowsNotifications();
    } else if (Platform.isMacOS) {
      await _initializeMacOSNotifications();
    }
  }

  Future<void> _initializeLinuxNotifications() async {
    try {
      // Check for libnotify
      final result = await Process.run('which', ['notify-send']);
      if (result.exitCode == 0) {
        debugPrint('🔔 Linux notifications available via notify-send');
      } else {
        debugPrint('⚠️ notify-send not available');
      }
    } catch (e) {
      debugPrint('Failed to initialize Linux notifications: $e');
    }
  }

  Future<void> _initializeWindowsNotifications() async {
    try {
      // Windows notifications are handled through system APIs
      debugPrint('🔔 Windows notifications initialized');
    } catch (e) {
      debugPrint('Failed to initialize Windows notifications: $e');
    }
  }

  Future<void> _initializeMacOSNotifications() async {
    try {
      // Check for osascript availability
      final result = await Process.run('which', ['osascript']);
      if (result.exitCode == 0) {
        debugPrint('🔔 macOS notifications available via osascript');
      } else {
        debugPrint('⚠️ osascript not available');
      }
    } catch (e) {
      debugPrint('Failed to initialize macOS notifications: $e');
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? icon,
    String? sound,
    NotificationUrgency urgency = NotificationUrgency.normal,
    int? timeout,
    Map<String, dynamic>? data,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Play notification sound
      await _playNotificationSound(sound);

      // Show platform-specific notification
      await _showPlatformNotification(
        title: title,
        body: body,
        icon: icon,
        urgency: urgency,
        timeout: timeout,
        data: data,
      );

      // Log the notification
      await _logNotification(title, body, data);

      _eventController.add(NotificationEvent(
        type: NotificationEventType.notification_shown,
        message: 'Notification shown: $title',
        data: {
          'title': title,
          'body': body,
          'urgency': urgency.name,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));

      debugPrint('🔔 Notification: $title - $body');
    } catch (e) {
      debugPrint('Failed to show notification: $e');
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to show notification: $e',
        data: {'title': title, 'body': body},
      ));
    }
  }

  Future<void> _playNotificationSound(String? customSound) async {
    try {
      final soundPath = customSound ?? _notificationSoundPath;
      
      if (customSound != null) {
        // Play custom sound if provided
        await _audioPlayer.play(AssetSource(customSound));
      } else {
        // Play default notification sound
        await _audioPlayer.play(AssetSource(_notificationSoundPath));
      }
      
      debugPrint('🔊 Playing notification sound: $soundPath');
    } catch (e) {
      debugPrint('Failed to play notification sound: $e');
      // Continue without sound if playback fails
    }
  }

  Future<void> _showPlatformNotification({
    required String title,
    required String body,
    String? icon,
    required NotificationUrgency urgency,
    int? timeout,
    Map<String, dynamic>? data,
  }) async {
    if (Platform.isLinux) {
      await _showLinuxNotification(
        title: title,
        body: body,
        icon: icon,
        urgency: urgency,
        timeout: timeout,
      );
    } else if (Platform.isWindows) {
      await _showWindowsNotification(
        title: title,
        body: body,
        icon: icon,
        timeout: timeout,
      );
    } else if (Platform.isMacOS) {
      await _showMacOSNotification(
        title: title,
        body: body,
        icon: icon,
      );
    }
  }

  Future<void> _showLinuxNotification({
    required String title,
    required String body,
    String? icon,
    required NotificationUrgency urgency,
    int? timeout,
  }) async {
    try {
      final args = <String>[
        title,
        body,
      ];

      // Add icon if specified
      if (icon != null) {
        args.addAll(['-i', icon]);
      }

      // Add urgency
      args.addAll(['-u', urgency.name]);

      // Add timeout if specified
      if (timeout != null) {
        args.addAll(['-t', timeout.toString()]);
      }

      // Add app name
      args.addAll(['-a', 'Termisol']);

      await Process.run('notify-send', args);
    } catch (e) {
      debugPrint('Failed to show Linux notification: $e');
    }
  }

  Future<void> _showWindowsNotification({
    required String title,
    required String body,
    String? icon,
    int? timeout,
  }) async {
    try {
      // Windows toast notifications would require additional packages
      // For now, we'll just log it
      debugPrint('Windows notification: $title - $body');
    } catch (e) {
      debugPrint('Failed to show Windows notification: $e');
    }
  }

  Future<void> _showMacOSNotification({
    required String title,
    required String body,
    String? icon,
  }) async {
    try {
      final script = '''
        display notification "$title" with title "$body" subtitle "Termisol"
      ''';

      await Process.run('osascript', ['-e', script]);
    } catch (e) {
      debugPrint('Failed to show macOS notification: $e');
    }
  }

  Future<void> _logNotification(String title, String body, Map<String, dynamic>? data) async {
    try {
      final notifications = _prefs.getStringList('notifications') ?? [];
      final notification = {
        'title': title,
        'body': body,
        'timestamp': DateTime.now().toIso8601String(),
        'data': data,
      };
      
      notifications.add(jsonEncode(notification));
      
      // Keep only last 100 notifications
      if (notifications.length > 100) {
        notifications.removeRange(0, notifications.length - 100);
      }
      
      await _prefs.setStringList('notifications', notifications);
    } catch (e) {
      debugPrint('Failed to log notification: $e');
    }
  }

  Future<void> showCommandNotification({
    required String command,
    required String result,
    NotificationType type = NotificationType.info,
  }) async {
    final title = _getCommandNotificationTitle(type);
    final body = 'Command: $command\nResult: $result';
    
    await showNotification(
      title: title,
      body: body,
      urgency: _getNotificationUrgency(type),
      data: {
        'type': 'command',
        'command': command,
        'result': result,
        'notificationType': type.name,
      },
    );
  }

  String _getCommandNotificationTitle(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return '✅ Command Completed';
      case NotificationType.error:
        return '❌ Command Failed';
      case NotificationType.warning:
        return '⚠️ Command Warning';
      case NotificationType.info:
        return 'ℹ️ Command Info';
    }
  }

  NotificationUrgency _getNotificationUrgency(NotificationType type) {
    switch (type) {
      case NotificationType.error:
        return NotificationUrgency.critical;
      case NotificationType.warning:
        return NotificationUrgency.normal;
      case NotificationType.success:
      case NotificationType.info:
        return NotificationUrgency.low;
    }
  }

  Future<void> showSystemNotification({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
  }) async {
    await showNotification(
      title: title,
      body: message,
      urgency: _getNotificationUrgency(type),
      data: {
        'type': 'system',
        'notificationType': type.name,
      },
    );
  }

  Future<void> showFileOperationNotification({
    required String operation,
    required String filePath,
    bool success = true,
  }) async {
    final title = success ? '✅ File Operation Complete' : '❌ File Operation Failed';
    final body = '$operation: $filePath';
    
    await showNotification(
      title: title,
      body: body,
      urgency: success ? NotificationUrgency.low : NotificationUrgency.normal,
      data: {
        'type': 'file_operation',
        'operation': operation,
        'filePath': filePath,
        'success': success,
      },
    );
  }

  Future<void> showGitNotification({
    required String operation,
    required String repository,
    bool success = true,
  }) async {
    final title = success ? '✅ Git Operation Complete' : '❌ Git Operation Failed';
    final body = '$operation in $repository';
    
    await showNotification(
      title: title,
      body: body,
      urgency: success ? NotificationUrgency.low : NotificationUrgency.normal,
      data: {
        'type': 'git',
        'operation': operation,
        'repository': repository,
        'success': success,
      },
    );
  }

  Future<void> showDockerNotification({
    required String operation,
    required String container,
    bool success = true,
  }) async {
    final title = success ? '✅ Docker Operation Complete' : '❌ Docker Operation Failed';
    final body = '$operation: $container';
    
    await showNotification(
      title: title,
      body: body,
      urgency: success ? NotificationUrgency.low : NotificationUrgency.normal,
      data: {
        'type': 'docker',
        'operation': operation,
        'container': container,
        'success': success,
      },
    );
  }

  Future<void> showDebugNotification({
    required String message,
    required String filePath,
  }) async {
    await showNotification(
      title: '🐛 Debug Event',
      body: '$message\nFile: $filePath',
      urgency: NotificationUrgency.normal,
      data: {
        'type': 'debug',
        'message': message,
        'filePath': filePath,
      },
    );
  }

  Future<void> showPerformanceNotification({
    required String issue,
    required String suggestion,
  }) async {
    await showNotification(
      title: '⚡ Performance Alert',
      body: 'Issue: $issue\nSuggestion: $suggestion',
      urgency: NotificationUrgency.normal,
      data: {
        'type': 'performance',
        'issue': issue,
        'suggestion': suggestion,
      },
    );
  }

  Future<void> clearNotifications() async {
    try {
      if (Platform.isLinux) {
        await Process.run('notify-send', ['--close-all']);
      }
      
      await _prefs.remove('notifications');
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.notifications_cleared,
        message: 'Notifications cleared',
      ));
      
      debugPrint('🔔 Notifications cleared');
    } catch (e) {
      debugPrint('Failed to clear notifications: $e');
    }
  }

  Future<List<NotificationHistory>> getNotificationHistory() async {
    try {
      final notifications = _prefs.getStringList('notifications') ?? [];
      return notifications.map((notification) {
        final data = jsonDecode(notification);
        return NotificationHistory(
          title: data['title'],
          body: data['body'],
          timestamp: DateTime.parse(data['timestamp']),
          data: data['data'],
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to get notification history: $e');
      return [];
    }
  }

  Future<void> setNotificationSettings({
    bool? enabled,
    bool? soundEnabled,
    NotificationUrgency? defaultUrgency,
    int? defaultTimeout,
  }) async {
    try {
      if (enabled != null) {
        await _prefs.setBool('notifications_enabled', enabled);
      }
      if (soundEnabled != null) {
        await _prefs.setBool('notifications_sound_enabled', soundEnabled);
      }
      if (defaultUrgency != null) {
        await _prefs.setString('notifications_default_urgency', defaultUrgency.name);
      }
      if (defaultTimeout != null) {
        await _prefs.setInt('notifications_default_timeout', defaultTimeout);
      }
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.settings_updated,
        message: 'Notification settings updated',
      ));
    } catch (e) {
      debugPrint('Failed to update notification settings: $e');
    }
  }

  Future<NotificationSettings> getNotificationSettings() async {
    try {
      return NotificationSettings(
        enabled: _prefs.getBool('notifications_enabled') ?? true,
        soundEnabled: _prefs.getBool('notifications_sound_enabled') ?? true,
        defaultUrgency: NotificationUrgency.values.firstWhere(
          (urgency) => urgency.name == _prefs.getString('notifications_default_urgency'),
          orElse: () => NotificationUrgency.normal,
        ),
        defaultTimeout: _prefs.getInt('notifications_default_timeout') ?? 5000,
      );
    } catch (e) {
      debugPrint('Failed to get notification settings: $e');
      return NotificationSettings(
        enabled: true,
        soundEnabled: true,
        defaultUrgency: NotificationUrgency.normal,
        defaultTimeout: 5000,
      );
    }
  }

  Future<void> testNotification() async {
    await showNotification(
      title: '🔔 Test Notification',
      body: 'This is a test notification from Termisol',
      urgency: NotificationUrgency.normal,
      data: {
        'type': 'test',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'platform': Platform.operatingSystem,
      'soundPath': _notificationSoundPath,
      'supportedPlatforms': ['Linux', 'Windows', 'macOS'],
    };
  }

  Future<void> dispose() async {
    try {
      await _audioPlayer.dispose();
      _eventController.close();
      debugPrint('🔔 Native Notifications disposed');
    } catch (e) {
      debugPrint('Error disposing notifications: $e');
    }
  }
}

class NotificationHistory {
  final String title;
  final String body;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  NotificationHistory({
    required this.title,
    required this.body,
    required this.timestamp,
    this.data,
  });
}

class NotificationSettings {
  final bool enabled;
  final bool soundEnabled;
  final NotificationUrgency defaultUrgency;
  final int defaultTimeout;

  NotificationSettings({
    required this.enabled,
    required this.soundEnabled,
    required this.defaultUrgency,
    required this.defaultTimeout,
  });
}

enum NotificationType {
  success,
  error,
  warning,
  info,
}

enum NotificationUrgency {
  low,
  normal,
  critical,
}

enum NotificationEventType {
  initialized,
  notification_shown,
  notifications_cleared,
  settings_updated,
  error,
}

class NotificationEvent {
  final NotificationEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  NotificationEvent({
    required this.type,
    required this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

// Native notifications widget
class NativeNotificationsWidget extends StatefulWidget {
  const NativeNotificationsWidget({super.key});

  @override
  State<NativeNotificationsWidget> createState() => _NativeNotificationsWidgetState();
}

class _NativeNotificationsWidgetState extends State<NativeNotificationsWidget> {
  final NativeNotifications _notifications = NativeNotifications.instance;
  NotificationSettings? _settings;
  List<NotificationHistory> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadHistory();
    _notifications.initialize();
    _notifications.events.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final settings = await _notifications.getNotificationSettings();
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _notifications.getNotificationHistory();
      setState(() {
        _history = history;
      });
    } catch (e) {
      debugPrint('Failed to load notification history: $e');
    }
  }

  Future<void> _updateSettings(NotificationSettings newSettings) async {
    await _notifications.setNotificationSettings(
      enabled: newSettings.enabled,
      soundEnabled: newSettings.soundEnabled,
      defaultUrgency: newSettings.defaultUrgency,
      defaultTimeout: newSettings.defaultTimeout,
    );
    
    await _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_settings == null) {
      return const Center(
        child: Text('Failed to load notification settings'),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 600),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications, color: Colors.blue[400]),
                const SizedBox(width: 12),
                const Text(
                  'Native Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _notifications.testNotification,
                  icon: const Icon(Icons.play_arrow, color: Colors.green),
                  tooltip: 'Test Notification',
                ),
                IconButton(
                  onPressed: _notifications.clearNotifications,
                  icon: const Icon(Icons.clear_all, color: Colors.orange),
                  tooltip: 'Clear All',
                ),
              ],
            ),
          ),
          
          // Settings
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text(
                          'Enable Notifications',
                          style: TextStyle(color: Colors.white),
                        ),
                        value: _settings!.enabled,
                        onChanged: (value) {
                          _updateSettings(_settings!.copyWith(enabled: value));
                        },
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        title: const Text(
                          'Sound Enabled',
                          style: TextStyle(color: Colors.white),
                        ),
                        value: _settings!.soundEnabled,
                        onChanged: (value) {
                          _updateSettings(_settings!.copyWith(soundEnabled: value));
                        },
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                DropdownButtonFormField<NotificationUrgency>(
                  value: _settings!.defaultUrgency,
                  decoration: const InputDecoration(
                    labelText: 'Default Urgency',
                    labelStyle: TextStyle(color: Colors.white),
                    border: OutlineInputBorder(),
                  ),
                  items: NotificationUrgency.values.map((urgency) {
                    return DropdownMenuItem(
                      value: urgency,
                      child: Text(
                        urgency.name.toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _updateSettings(_settings!.copyWith(defaultUrgency: value));
                    }
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  initialValue: _settings!.defaultTimeout.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Default Timeout (ms)',
                    labelStyle: TextStyle(color: Colors.white),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final timeout = int.tryParse(value);
                    if (timeout != null) {
                      _updateSettings(_settings!.copyWith(defaultTimeout: timeout));
                    }
                  },
                ),
              ],
            ),
          ),
          
          // Quick actions
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Actions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _notifications.showCommandNotification(
                        command: 'echo "Hello World"',
                        result: 'Hello World',
                        type: NotificationType.success,
                      ),
                      icon: const Icon(Icons.terminal, size: 16),
                      label: const Text('Command Success'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _notifications.showCommandNotification(
                        command: 'false',
                        result: 'Command failed',
                        type: NotificationType.error,
                      ),
                      icon: const Icon(Icons.error, size: 16),
                      label: const Text('Command Error'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[700],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _notifications.showFileOperationNotification(
                        operation: 'File created',
                        filePath: '/tmp/example.txt',
                        success: true,
                      ),
                      icon: const Icon(Icons.file_present, size: 16),
                      label: const Text('File Operation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _notifications.showGitNotification(
                        operation: 'Commit',
                        repository: 'termisol',
                        success: true,
                      ),
                      icon: const Icon(Icons.git, size: 16),
                      label: const Text('Git Operation'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // History
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Notification History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_history.length} notifications',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _history.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_off, color: Colors.grey[400], size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _history.length,
                            itemBuilder: (context, index) {
                              final notification = _history[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            notification.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatTimestamp(notification.timestamp),
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      notification.body,
                                      style: const TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
