import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Native notification system for Termisol
/// 
/// Features:
/// - Native notifications with custom sound
/// - Multiple notification types
/// - Sound customization
/// - Priority levels
/// - Notification history
/// - System integration
class NotificationSystem {
  static const String _notificationSound = 'assets/notif.mp3';
  
  final StreamController<NotificationEvent> _eventController = StreamController<NotificationEvent>.broadcast();
  final List<NotificationRecord> _history = [];
  
  bool _isInitialized = false;
  AndroidNotificationChannel? _androidChannel;
  FlutterLocalNotificationsPlugin? _notificationsPlugin;
  
  Stream<NotificationEvent> get events => _eventController.stream;
  List<NotificationRecord> get history => List.unmodifiable(_history);
  bool get isInitialized => _isInitialized;
  
  /// Initialize notification system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize Flutter Local Notifications
      _notificationsPlugin = FlutterLocalNotificationsPlugin();
      
      // Android initialization
      const androidInitializationSettings = AndroidInitializationSettings(
        defaultIcon: '@mipmap/ic_launcher',
        defaultSound: RawResourceAndroidNotificationSound(_notificationSound),
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: const Color.fromARGB(255, 255, 0, 0),
        ledOnMs: 1000,
        ledOffMs: 500,
      );
      
      // iOS initialization
      const iosInitializationSettings = DarwinInitializationSettings(
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      await _notificationsPlugin!.initialize(
        androidInitializationSettings,
        iosInitializationSettings,
      );
      
      // Create notification channel
      const androidNotificationChannel = AndroidNotificationChannel(
        'termisol_notifications',
        'Termisol Notifications',
        channelDescription: 'High priority notifications for Termisol terminal',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound(_notificationSound),
        ledColor: const Color.fromARGB(255, 255, 0, 0),
        ledOnMs: 1000,
        ledOffMs: 500,
      );
      
      await _notificationsPlugin!.createNotificationChannel(androidNotificationChannel);
      _androidChannel = androidNotificationChannel;
      
      _isInitialized = true;
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.initialized,
        message: 'Notification system initialized',
        data: {'sound': _notificationSound},
      ));
      
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to initialize notifications: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Show notification
  Future<void> showNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.info,
    NotificationPriority priority = NotificationPriority.normal,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelName: 'termisol_notifications',
          icon: _getNotificationIcon(type),
          color: _getNotificationColor(type),
          importance: _getImportance(priority),
          priority: _getAndroidPriority(priority),
          largeIcon: _getLargeIcon(type),
          style: AndroidNotificationStyle.defaultStyle,
          enableLights: true,
          ledColor: _getNotificationColor(type),
          ledOnMs: 1000,
          ledOffMs: 500,
          enableVibration: true,
          vibrationPattern: _getVibrationPattern(priority),
          groupKey: _getGroupKey(type),
          setAsGroupSummary: false,
          groupAlertBehavior: GroupAlertBehavior.all,
          autoCancel: false,
          ongoing: false,
          silent: false,
          visibility: NotificationVisibility.public,
          timeoutAfter: _getTimeout(priority),
          category: _getCategory(type),
          fullScreenIntent: false,
          usesChronometer: false,
          additionalFlags: 0,
        ),
        iOS: IOSNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: _notificationSound,
          badgeNumber: _getBadgeNumber(type),
          attachments: [],
          subtitle: null,
          threadIdentifier: null,
          categoryIdentifier: _getCategory(type),
          interruptLevel: _getInterruptLevel(priority),
        ),
        payload: payload,
        id: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      
      await _notificationsPlugin!.show(
        0,
        notificationDetails,
      );
      
      // Add to history
      final record = NotificationRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        type: type,
        priority: priority,
        timestamp: DateTime.now(),
        payload: payload,
      );
      
      _history.insert(0, record);
      if (_history.length > 100) {
        _history.removeLast();
      }
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.notification_shown,
        message: 'Notification displayed',
        data: {'notification': record.toJson()},
      ));
      
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to show notification: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Show progress notification
  Future<void> showProgressNotification({
    required String title,
    required String content,
    int progress = 0,
    int maxProgress = 100,
  }) async {
    try {
      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelName: 'termisol_notifications',
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF00D4AA),
          importance: Importance.high,
          priority: Priority.high,
          style: AndroidNotificationStyle.bigProgress,
          enableLights: true,
          ledColor: const Color(0xFF00D4AA),
          ledOnMs: 1000,
          ledOffMs: 500,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 100]),
          groupKey: 'progress',
          setAsGroupSummary: false,
          groupAlertBehavior: GroupAlertBehavior.all,
          autoCancel: false,
          ongoing: true,
          silent: false,
          visibility: NotificationVisibility.public,
          timeoutAfter: 0,
          category: 'progress',
          fullScreenIntent: false,
          usesChronometer: false,
          additionalFlags: 0,
          progress: progress,
          maxProgress: maxProgress,
          indeterminate: false,
          showProgress: true,
        ),
        iOS: IOSNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: _notificationSound,
          badgeNumber: null,
          attachments: [],
          subtitle: content,
          threadIdentifier: null,
          categoryIdentifier: 'progress',
          interruptLevel: 'timeSensitive',
        ),
        payload: jsonEncode({
          'type': 'progress',
          'progress': progress,
          'max_progress': maxProgress,
        }),
        id: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      
      await _notificationsPlugin!.show(
        0,
        notificationDetails,
      );
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.progress_shown,
        message: 'Progress notification displayed',
        data: {
          'title': title,
          'progress': progress,
          'max_progress': maxProgress,
        },
      ));
      
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to show progress notification: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Update progress notification
  Future<void> updateProgressNotification(String notificationId, int progress, int maxProgress) async {
    try {
      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          channelName: 'termisol_notifications',
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF00D4AA),
          importance: Importance.high,
          priority: Priority.high,
          style: AndroidNotificationStyle.bigProgress,
          enableLights: true,
          ledColor: const Color(0xFF00D4AA),
          ledOnMs: 1000,
          ledOffMs: 500,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 100]),
          groupKey: 'progress',
          setAsGroupSummary: false,
          groupAlertBehavior: GroupAlertBehavior.all,
          autoCancel: false,
          ongoing: true,
          silent: false,
          visibility: NotificationVisibility.public,
          timeoutAfter: 0,
          category: 'progress',
          fullScreenIntent: false,
          usesChronometer: false,
          additionalFlags: 0,
          progress: progress,
          maxProgress: maxProgress,
          indeterminate: false,
          showProgress: true,
        ),
        iOS: IOSNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: _notificationSound,
          badgeNumber: null,
          attachments: [],
          subtitle: 'Progress: $progress/$maxProgress',
          threadIdentifier: null,
          categoryIdentifier: 'progress',
          interruptLevel: 'timeSensitive',
        ),
        payload: jsonEncode({
          'type': 'progress',
          'progress': progress,
          'max_progress': maxProgress,
        }),
        id: notificationId,
      );
      
      await _notificationsPlugin!.show(
        0,
        notificationDetails,
      );
      
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to update progress notification: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Cancel notification
  Future<void> cancelNotification(String notificationId) async {
    try {
      await _notificationsPlugin!.cancel(notificationId);
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.notification_cancelled,
        message: 'Notification cancelled',
        data: {'notification_id': notificationId},
      ));
      
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to cancel notification: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin!.cancelAll();
      
      _eventController.add(NotificationEvent(
        type: NotificationEventType.all_notifications_cancelled,
        message: 'All notifications cancelled',
        data: {},
      ));
      
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to cancel all notifications: $e',
        data: {'error': e.toString()},
      ));
    }
  }
  
  /// Get notification permissions
  Future<bool> getPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      final result = await _notificationsPlugin!.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin,
        AndroidFlutterLocalNotificationsPlugin,
      >();
      
      if (result is IOSFlutterLocalNotificationsPlugin) {
        final iosPlugin = result as IOSFlutterLocalNotificationsPlugin;
        final permissions = await iosPlugin.requestPermissions(
          const IOSNotificationSettings(
            alert: true,
            badge: true,
            sound: true,
          ),
        );
        
        return permissions.alert ?? false;
      } else if (result is AndroidFlutterLocalNotificationsPlugin) {
        final androidPlugin = result as AndroidFlutterLocalNotificationsPlugin;
        final permissions = await androidPlugin.requestNotificationsPermission();
        
        return permissions ?? false;
      }
      
      return false;
    } catch (e) {
      _eventController.add(NotificationEvent(
        type: NotificationEventType.error,
        message: 'Failed to get permissions: $e',
        data: {'error': e.toString()},
      ));
      return false;
    }
  }
  
  /// Get notification settings
  Map<String, dynamic> getSettings() {
    return {
      'is_initialized': _isInitialized,
      'sound_file': _notificationSound,
      'history_count': _history.length,
      'android_channel': _androidChannel?.name,
    };
  }
  
  /// Clear notification history
  void clearHistory() {
    _history.clear();
    
    _eventController.add(NotificationEvent(
      type: NotificationEventType.history_cleared,
      message: 'Notification history cleared',
      data: {},
    ));
  }
  
  // Helper methods
  String _getNotificationIcon(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return '@mipmap/ic_notification_success';
      case NotificationType.error:
        return '@mipmap/ic_notification_error';
      case NotificationType.warning:
        return '@mipmap/ic_notification_warning';
      case NotificationType.info:
      default:
        return '@mipmap/ic_notification_info';
    }
  }
  
  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return const Color(0xFF4CAF50);
      case NotificationType.error:
        return const Color(0xFFF44336);
      case NotificationType.warning:
        return const Color(0xFFFF9800);
      case NotificationType.info:
      default:
        return const Color(0xFF2196F3);
    }
  }
  
  Importance _getImportance(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return Importance.low;
      case NotificationPriority.normal:
        return Importance.defaultImportance;
      case NotificationPriority.high:
        return Importance.high;
      case NotificationPriority.critical:
        return Importance.high;
    }
  }
  
  Priority _getAndroidPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return Priority.low;
      case NotificationPriority.normal:
        return Priority.defaultPriority;
      case NotificationPriority.high:
        return Priority.high;
      case NotificationPriority.critical:
        return Priority.high;
    }
  }
  
  String? _getBadgeNumber(NotificationType type) {
    switch (type) {
      case NotificationType.error:
        return '1';
      case NotificationType.warning:
        return '2';
      default:
        return null;
    }
  }
  
  Int64List _getVibrationPattern(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return Int64List.fromList([0, 50]);
      case NotificationPriority.normal:
        return Int64List.fromList([0, 100]);
      case NotificationPriority.high:
        return Int64List.fromList([0, 200, 100, 200]);
      case NotificationPriority.critical:
        return Int64List.fromList([0, 500, 200, 500, 200, 500]);
    }
  }
  
  String _getGroupKey(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return 'success_notifications';
      case NotificationType.error:
        return 'error_notifications';
      case NotificationType.warning:
        return 'warning_notifications';
      case NotificationType.info:
      default:
        return 'info_notifications';
    }
  }
  
  String _getCategory(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return 'status';
      case NotificationType.error:
        return 'alarm';
      case NotificationType.warning:
        return 'reminder';
      case NotificationType.info:
      default:
        return 'service';
    }
  }
  
  int _getTimeout(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return 5000;
      case NotificationPriority.normal:
        return 4000;
      case NotificationPriority.high:
        return 6000;
      case NotificationPriority.critical:
        return 10000;
    }
  }
  
  String _getInterruptLevel(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return 'passive';
      case NotificationPriority.normal:
        return 'active';
      case NotificationPriority.high:
        return 'timeSensitive';
      case NotificationPriority.critical:
        return 'critical';
    }
  }
  
  /// Dispose
  Future<void> dispose() async {
    await _notificationsPlugin?.cancelAll();
    _eventController.close();
    _isInitialized = false;
  }
}

/// Notification types
enum NotificationType {
  success,
  error,
  warning,
  info,
}

/// Notification priority levels
enum NotificationPriority {
  low,
  normal,
  high,
  critical,
}

/// Notification event types
enum NotificationEventType {
  initialized,
  notification_shown,
  progress_shown,
  notification_cancelled,
  all_notifications_cancelled,
  permissions_requested,
  history_cleared,
  error,
}

/// Notification event
class NotificationEvent {
  final NotificationEventType type;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  NotificationEvent({
    required this.type,
    required this.message,
    required this.data,
  }) : timestamp = DateTime.now();
}

/// Notification record
class NotificationRecord {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final NotificationPriority priority;
  final DateTime timestamp;
  final String? payload;
  
  NotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.priority,
    required this.timestamp,
    this.payload,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'type': type.toString(),
    'priority': priority.toString(),
    'timestamp': timestamp.toIso8601String(),
    'payload': payload,
  };
}
