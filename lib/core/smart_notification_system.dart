import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Smart Notification System for House-wide Events
/// 
/// Implements intelligent notification management:
/// - Cross-device notification synchronization
/// - Context-aware notifications
/// - Notification rules and filters
/// - House-wide event broadcasting
/// - Notification history and analytics
/// - Smart notification prioritization
/// - Integration with GNOME and system notifications
class SmartNotificationSystem {
  bool _isInitialized = false;
  
  // Notification storage
  String _notificationsPath = '';
  final List<SmartNotification> _notifications = [];
  final Map<String, NotificationRule> _rules = {};
  final Map<String, Set<String>> _subscriptions = {};
  
  // Notification channels
  final Map<String, NotificationChannel> _channels = {};
  final StreamController<SmartNotification> _notificationController = StreamController.broadcast();
  Timer? _cleanupTimer;
  
  // Configuration
  bool _gnomeIntegration = true;
  bool _systemNotifications = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = false; // Desktop doesn't need vibration
  int _maxNotifications = 100;
  Duration _defaultDuration = const Duration(seconds: 5);
  
  // Event handlers
  final List<Function(SmartNotification)> _onNotificationAdded = [];
  final List<Function(SmartNotification)> _onNotificationRead = [];
  final List<Function(SmartNotification)> _onNotificationDismissed = [];
  final List<Function(NotificationRule)> _onRuleAdded = [];
  final List<Function(String)> _onRuleTriggered = [];
  
  SmartNotificationSystem();
  
  bool get isInitialized => _isInitialized;
  List<SmartNotification> get notifications => List.unmodifiable(_notifications);
  Map<String, NotificationRule> get rules => Map.unmodifiable(_rules);
  Stream<SmartNotification> get notificationStream => _notificationController.stream;
  
  /// Initialize notification system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup paths
      _setupPaths();
      
      // Load existing notifications and rules
      await _loadNotifications();
      await _loadRules();
      
      // Setup notification channels
      await _setupChannels();
      
      // Start cleanup timer
      _startCleanupTimer();
      
      _isInitialized = true;
      debugPrint('🔔 Smart Notification System initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Smart Notification System: $e');
      rethrow;
    }
  }
  
  /// Setup file paths
  void _setupPaths() {
    final homeDir = Platform.environment['HOME'] ?? '';
    _notificationsPath = path.join(homeDir, '.termisol', 'notifications');
  }
  
  /// Load existing notifications
  Future<void> _loadNotifications() async {
    try {
      final notificationsFile = File(path.join(_notificationsPath, 'notifications.json'));
      if (await notificationsFile.exists()) {
        final content = await notificationsFile.readAsString();
        final data = jsonDecode(content);
        
        final notificationsData = data['notifications'] as List? ?? [];
        for (final notificationData in notificationsData) {
          final notification = SmartNotification.fromJson(notificationData);
          _notifications.add(notification);
        }
        
        debugPrint('🔔 Loaded ${_notifications.length} notifications');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load notifications: $e');
    }
  }
  
  /// Load notification rules
  Future<void> _loadRules() async {
    try {
      final rulesFile = File(path.join(_notificationsPath, 'rules.json'));
      if (await rulesFile.exists()) {
        final content = await rulesFile.readAsString();
        final data = jsonDecode(content);
        
        final rulesData = data['rules'] as Map? ?? {};
        for (final entry in rulesData.entries) {
          final rule = NotificationRule.fromJson(entry.value);
          _rules[entry.key] = rule;
        }
        
        debugPrint('🔔 Loaded ${_rules.length} notification rules');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load notification rules: $e');
    }
  }
  
  /// Setup notification channels
  Future<void> _setupChannels() async {
    // House-wide channel
    _channels['house'] = NotificationChannel(
      id: 'house',
      name: 'House Events',
      description: 'House-wide terminal events and notifications',
      type: NotificationChannelType.broadcast,
      priority: NotificationPriority.normal,
    );
    
    // Terminal events channel
    _channels['terminal'] = NotificationChannel(
      id: 'terminal',
      name: 'Terminal Events',
      description: 'Terminal-specific events and commands',
      type: NotificationChannelType.terminal,
      priority: NotificationPriority.high,
    );
    
    // Collaboration channel
    _channels['collaboration'] = NotificationChannel(
      id: 'collaboration',
      name: 'Collaboration',
      description: 'Terminal sharing and collaboration events',
      type: NotificationChannelType.collaboration,
      priority: NotificationPriority.high,
    );
    
    // System channel
    _channels['system'] = NotificationChannel(
      id: 'system',
      name: 'System',
      description: 'System and maintenance notifications',
      type: NotificationChannelType.system,
      priority: NotificationPriority.low,
    );
  }
  
  /// Start cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _cleanupOldNotifications();
    });
  }
  
  /// Create notification
  Future<String> createNotification({
    required String title,
    required String message,
    String? channelId = 'house',
    NotificationType type = NotificationType.info,
    NotificationPriority priority = NotificationPriority.normal,
    Duration? duration,
    Map<String, dynamic>? metadata,
    String? icon,
    String? sound,
    bool? persistent,
    List<String>? actions,
  }) async {
    try {
      final notificationId = 'notif_${DateTime.now().millisecondsSinceEpoch}';
      
      final notification = SmartNotification(
        id: notificationId,
        title: title,
        message: message,
        channelId: channelId,
        type: type,
        priority: priority,
        createdAt: DateTime.now(),
        expiresAt: duration != null 
            ? DateTime.now().add(duration!)
            : null,
        metadata: metadata ?? {},
        icon: icon,
        sound: sound,
        persistent: persistent ?? false,
        actions: actions ?? [],
        isRead: false,
        isDismissed: false,
      );
      
      // Check notification rules
      final shouldShow = _evaluateNotificationRules(notification);
      if (!shouldShow) {
        debugPrint('🔔 Notification blocked by rules: $title');
        return notificationId;
      }
      
      // Add to notifications list
      _notifications.insert(0, notification);
      
      // Trim notifications if needed
      if (_notifications.length > _maxNotifications) {
        _notifications.removeRange(_maxNotifications, _notifications.length);
      }
      
      // Send to channel
      await _sendToChannel(channelId, notification);
      
      // Show system notification if enabled
      if (_systemNotifications) {
        await _showSystemNotification(notification);
      }
      
      // Notify listeners
      _onNotificationAdded.forEach((callback) => callback(notification));
      
      debugPrint('🔔 Created notification: $title');
      return notificationId;
    } catch (e) {
      debugPrint('❌ Failed to create notification: $e');
      rethrow;
    }
  }
  
  /// Evaluate notification rules
  bool _evaluateNotificationRules(SmartNotification notification) {
    for (final rule in _rules.values) {
      if (_matchesRule(notification, rule)) {
        // Trigger rule action
        _triggerRule(rule, notification);
        
        // Check if rule blocks notification
        if (rule.action == NotificationRuleAction.block) {
          return false;
        }
      }
    }
    return true;
  }
  
  /// Check if notification matches rule
  bool _matchesRule(SmartNotification notification, NotificationRule rule) {
    // Check channel filter
    if (rule.channelId != null && notification.channelId != rule.channelId) {
      return false;
    }
    
    // Check type filter
    if (rule.types.isNotEmpty && !rule.types.contains(notification.type)) {
      return false;
    }
    
    // Check priority filter
    if (rule.minPriority != null && 
        notification.priority.index < rule.minPriority!.index) {
      return false;
    }
    
    // Check content filter
    if (rule.contentFilter != null) {
      final content = '${notification.title} ${notification.message}'.toLowerCase();
      if (!content.contains(rule.contentFilter!.toLowerCase())) {
        return false;
      }
    }
    
    // Check time filter
    if (rule.timeFilter != null) {
      final now = DateTime.now();
      final hour = now.hour;
      
      if (rule.timeFilter == TimeFilter.workHours && 
          (hour < 9 || hour > 17)) {
        return false;
      }
      
      if (rule.timeFilter == TimeFilter.quietHours && 
          (hour >= 22 || hour < 7)) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Trigger notification rule action
  void _triggerRule(NotificationRule rule, SmartNotification notification) {
    switch (rule.action) {
      case NotificationRuleAction.forward:
        _forwardNotification(notification, rule.targetChannelId!);
        break;
        
      case NotificationRuleAction.transform:
        _transformNotification(notification, rule);
        break;
        
      case NotificationRuleAction.delay:
        _delayNotification(notification, rule.delayDuration!);
        break;
        
      case NotificationRuleAction.block:
        // Notification already blocked in _evaluateNotificationRules
        break;
    }
    
    _onRuleTriggered.forEach((callback) => callback(rule.id));
    debugPrint('🔔 Triggered rule: ${rule.name}');
  }
  
  /// Forward notification
  Future<void> _forwardNotification(SmartNotification notification, String targetChannelId) async {
    final forwardedNotification = notification.copyWith(
      id: 'forwarded_${notification.id}',
      channelId: targetChannelId,
      metadata: {
        ...notification.metadata,
        'original_channel': notification.channelId,
        'forwarded_by': rule.id,
        'forwarded_at': DateTime.now().toIso8601String(),
      },
    );
    
    await _sendToChannel(targetChannelId, forwardedNotification);
  }
  
  /// Transform notification
  Future<void> _transformNotification(SmartNotification notification, NotificationRule rule) async {
    String transformedTitle = notification.title;
    String transformedMessage = notification.message;
    
    if (rule.transformPattern != null) {
      final pattern = RegExp(rule.transformPattern!);
      transformedTitle = pattern.hasMatch(notification.title)
          ? pattern.firstMatch(notification.title)!.group(1)
          : notification.title;
      transformedMessage = pattern.hasMatch(notification.message)
          ? pattern.firstMatch(notification.message)!.group(1)
          : notification.message;
    }
    
    final transformedNotification = notification.copyWith(
      id: 'transformed_${notification.id}',
      title: transformedTitle,
      message: transformedMessage,
      metadata: {
        ...notification.metadata,
        'original_title': notification.title,
        'original_message': notification.message,
        'transformed_by': rule.id,
        'transformed_at': DateTime.now().toIso8601String(),
      },
    );
    
    await _sendToChannel(notification.channelId, transformedNotification);
  }
  
  /// Delay notification
  Future<void> _delayNotification(SmartNotification notification, Duration delay) async {
    await Future.delayed(delay);
    
    final delayedNotification = notification.copyWith(
      id: 'delayed_${notification.id}',
      metadata: {
        ...notification.metadata,
        'delayed_by': delay.inMilliseconds,
        'delayed_until': DateTime.now().add(delay).toIso8601String(),
      },
    );
    
    await _sendToChannel(notification.channelId, delayedNotification);
  }
  
  /// Send notification to channel
  Future<void> _sendToChannel(String channelId, SmartNotification notification) async {
    final channel = _channels[channelId];
    if (channel == null) return;
    
    switch (channel.type) {
      case NotificationChannelType.broadcast:
        await _sendBroadcastNotification(channel, notification);
        break;
        
      case NotificationChannelType.terminal:
        await _sendTerminalNotification(channel, notification);
        break;
        
      case NotificationChannelType.collaboration:
        await _sendCollaborationNotification(channel, notification);
        break;
        
      case NotificationChannelType.system:
        await _sendSystemNotification(channel, notification);
        break;
    }
  }
  
  /// Send broadcast notification
  Future<void> _sendBroadcastNotification(NotificationChannel channel, SmartNotification notification) async {
    // In a real implementation, this would send to all connected devices
    debugPrint('🔔 Broadcast notification: ${notification.title}');
  }
  
  /// Send terminal notification
  Future<void> _sendTerminalNotification(NotificationChannel channel, SmartNotification notification) async {
    // In a real implementation, this would send to specific terminal session
    debugPrint('🔔 Terminal notification: ${notification.title}');
  }
  
  /// Send collaboration notification
  Future<void> _sendCollaborationNotification(NotificationChannel channel, SmartNotification notification) async {
    // In a real implementation, this would send to collaboration system
    debugPrint('🔔 Collaboration notification: ${notification.title}');
  }
  
  /// Send system notification
  Future<void> _sendSystemNotification(NotificationChannel channel, SmartNotification notification) async {
    // In a real implementation, this would send to system notification service
    debugPrint('🔔 System notification: ${notification.title}');
  }
  
  /// Show system notification
  Future<void> _showSystemNotification(SmartNotification notification) async {
    if (!_gnomeIntegration) return;
    
    try {
      // Use notify-send for Linux
      if (Platform.isLinux) {
        final result = await Process.run('notify-send', [
          '--app-name=Termisol',
          '--icon=${notification.icon ?? 'dialog-information'}',
          '--urgency=${_getUrgencyLevel(notification.priority)}',
          '--expire-time=${notification.expiresAt?.difference(DateTime.now()).inMilliseconds ?? 5000}',
          notification.title,
          notification.message,
        ]);
        
        if (result.exitCode != 0) {
          debugPrint('⚠️ Failed to send system notification: ${result.stderr}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to show system notification: $e');
    }
  }
  
  /// Get urgency level for notify-send
  String _getUrgencyLevel(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.low:
        return 'low';
      case NotificationPriority.normal:
        return 'normal';
      case NotificationPriority.high:
        return 'critical';
      case NotificationPriority.urgent:
        return 'critical';
    }
  }
  
  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    final notificationIndex = _notifications.indexWhere((n) => n.id == notificationId);
    if (notificationIndex != -1) {
      final notification = _notifications[notificationIndex];
      final updatedNotification = notification.copyWith(
        isRead: true,
        readAt: DateTime.now(),
      );
      
      _notifications[notificationIndex] = updatedNotification;
      
      _onNotificationRead.forEach((callback) => callback(updatedNotification));
      
      debugPrint('🔔 Marked notification as read: $notificationId');
    }
  }
  
  /// Dismiss notification
  Future<void> dismissNotification(String notificationId) async {
    final notificationIndex = _notifications.indexWhere((n) => n.id == notificationId);
    if (notificationIndex != -1) {
      final notification = _notifications[notificationIndex];
      final updatedNotification = notification.copyWith(
        isDismissed: true,
        dismissedAt: DateTime.now(),
      );
      
      _notifications[notificationIndex] = updatedNotification;
      
      _onNotificationDismissed.forEach((callback) => callback(updatedNotification));
      
      debugPrint('🔔 Dismissed notification: $notificationId');
    }
  }
  
  /// Subscribe to channel
  void subscribeToChannel(String channelId, {String? deviceId}) {
    final subscriptionId = deviceId ?? 'default';
    
    if (!_subscriptions.containsKey(channelId)) {
      _subscriptions[channelId] = <String>{};
    }
    
    _subscriptions[channelId]!.add(subscriptionId);
    debugPrint('🔔 Subscribed to channel: $channelId');
  }
  
  /// Unsubscribe from channel
  void unsubscribeFromChannel(String channelId, {String? deviceId}) {
    final subscriptionId = deviceId ?? 'default';
    
    if (_subscriptions.containsKey(channelId)) {
      _subscriptions[channelId]!.remove(subscriptionId);
      
      if (_subscriptions[channelId]!.isEmpty) {
        _subscriptions.remove(channelId);
      }
    }
    
    debugPrint('🔔 Unsubscribed from channel: $channelId');
  }
  
  /// Create notification rule
  Future<String> createRule({
    required String name,
    required NotificationRuleAction action,
    String? description,
    String? channelId,
    List<NotificationType>? types,
    NotificationPriority? minPriority,
    String? contentFilter,
    TimeFilter? timeFilter,
    String? transformPattern,
    Duration? delayDuration,
    String? targetChannelId,
    bool? enabled = true,
  }) async {
    try {
      final ruleId = 'rule_${DateTime.now().millisecondsSinceEpoch}';
      
      final rule = NotificationRule(
        id: ruleId,
        name: name,
        description: description,
        action: action,
        channelId: channelId,
        types: types ?? [],
        minPriority: minPriority,
        contentFilter: contentFilter,
        timeFilter: timeFilter,
        transformPattern: transformPattern,
        delayDuration: delayDuration,
        targetChannelId: targetChannelId,
        enabled: enabled,
        createdAt: DateTime.now(),
      );
      
      _rules[ruleId] = rule;
      await _saveRules();
      
      _onRuleAdded.forEach((callback) => callback(rule));
      
      debugPrint('🔔 Created notification rule: $name');
      return ruleId;
    } catch (e) {
      debugPrint('❌ Failed to create notification rule: $e');
      rethrow;
    }
  }
  
  /// Update rule
  Future<void> updateRule(String ruleId, {
    String? name,
    String? description,
    NotificationRuleAction? action,
    bool? enabled,
  }) async {
    final rule = _rules[ruleId];
    if (rule == null) return;
    
    final updatedRule = rule.copyWith(
      name: name,
      description: description,
      action: action,
      enabled: enabled,
    );
    
    _rules[ruleId] = updatedRule;
    await _saveRules();
    
    debugPrint('🔔 Updated notification rule: $ruleId');
  }
  
  /// Delete rule
  Future<void> deleteRule(String ruleId) async {
    final rule = _rules.remove(ruleId);
    if (rule != null) {
      await _saveRules();
      
      debugPrint('🗑️ Deleted notification rule: $ruleId');
    }
  }
  
  /// Get notifications by channel
  List<SmartNotification> getNotificationsByChannel(String channelId) {
    return _notifications.where((n) => n.channelId == channelId).toList();
  }
  
  /// Get notifications by type
  List<SmartNotification> getNotificationsByType(NotificationType type) {
    return _notifications.where((n) => n.type == type).toList();
  }
  
  /// Get notifications by priority
  List<SmartNotification> getNotificationsByPriority(NotificationPriority priority) {
    return _notifications.where((n) => n.priority == priority).toList();
  }
  
  /// Search notifications
  List<SmartNotification> searchNotifications(String query) {
    final lowerQuery = query.toLowerCase();
    
    return _notifications.where((notification) {
      return notification.title.toLowerCase().contains(lowerQuery) ||
             notification.message.toLowerCase().contains(lowerQuery) ||
             notification.metadata.values.any((value) => 
                 value.toString().toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Get unread notifications
  List<SmartNotification> getUnreadNotifications() {
    return _notifications.where((n) => !n.isRead).toList();
  }
  
  /// Get unread count
  int getUnreadCount() {
    return _notifications.where((n) => !n.isRead).length;
  }
  
  /// Mark all as read
  Future<void> markAllAsRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        final updatedNotification = _notifications[i].copyWith(
          isRead: true,
          readAt: DateTime.now(),
        );
        _notifications[i] = updatedNotification;
      }
    }
    
    await _saveNotifications();
    debugPrint('🔔 Marked all notifications as read');
  }
  
  /// Clear all notifications
  Future<void> clearAllNotifications() async {
    _notifications.clear();
    await _saveNotifications();
    debugPrint('🗑️ Cleared all notifications');
  }
  
  /// Save notifications
  Future<void> _saveNotifications() async {
    try {
      final notificationsData = _notifications.map((n) => n.toJson()).toList();
      final data = {
        'version': '1.0',
        'notifications': notificationsData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final notificationsFile = File(path.join(_notificationsPath, 'notifications.json'));
      await notificationsFile.parent.create(recursive: true);
      await notificationsFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save notifications: $e');
    }
  }
  
  /// Save rules
  Future<void> _saveRules() async {
    try {
      final rulesData = _rules.map((k, v) => MapEntry(k, v.toJson())).toList();
      final data = {
        'version': '1.0',
        'rules': rulesData,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final rulesFile = File(path.join(_notificationsPath, 'rules.json'));
      await rulesFile.parent.create(recursive: true);
      await rulesFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save notification rules: $e');
    }
  }
  
  /// Get statistics
  Map<String, dynamic> getStatistics() {
    final unreadCount = _notifications.where((n) => !n.isRead).length;
    final dismissedCount = _notifications.where((n) => n.isDismissed).length;
    final byType = <String, int>{};
    final byChannel = <String, int>{};
    final byPriority = <String, int>{};
    
    for (final notification in _notifications) {
      byType[notification.type.toString()] = (byType[notification.type.toString()] ?? 0) + 1;
      byChannel[notification.channelId] = (byChannel[notification.channelId] ?? 0) + 1;
      byPriority[notification.priority.toString()] = (byPriority[notification.priority.toString()] ?? 0) + 1;
    }
    
    return {
      'total_notifications': _notifications.length,
      'unread_count': unreadCount,
      'dismissed_count': dismissedCount,
      'rules_count': _rules.length,
      'channels_count': _channels.length,
      'subscriptions_count': _subscriptions.values
          .map((subs) => subs.length)
          .reduce((a, b) => a + b, 0),
      'by_type': byType,
      'by_channel': byChannel,
      'by_priority': byPriority,
      'gnome_integration': _gnomeIntegration,
      'system_notifications': _systemNotifications,
      'sound_enabled': _soundEnabled,
      'max_notifications': _maxNotifications,
      'auto_cleanup_active': _cleanupTimer?.isActive ?? false,
    };
  }
  
  /// Set configuration
  void setConfiguration({
    bool? gnomeIntegration,
    bool? systemNotifications,
    bool? soundEnabled,
    int? maxNotifications,
    Duration? defaultDuration,
  }) {
    if (gnomeIntegration != null) _gnomeIntegration = gnomeIntegration!;
    if (systemNotifications != null) _systemNotifications = systemNotifications!;
    if (soundEnabled != null) _soundEnabled = soundEnabled!;
    if (maxNotifications != null) _maxNotifications = maxNotifications!;
    if (defaultDuration != null) _defaultDuration = defaultDuration!;
    
    debugPrint('⚙️ Smart Notification System configuration updated');
  }
  
  /// Add notification added listener
  void addNotificationAddedListener(Function(SmartNotification) listener) {
    _onNotificationAdded.add(listener);
  }
  
  /// Add notification read listener
  void addNotificationReadListener(Function(SmartNotification) listener {
    _onNotificationRead.add(listener);
  }
  
  /// Add notification dismissed listener
  void addNotificationDismissedListener(Function(SmartNotification) listener {
    _onNotificationDismissed.add(listener);
  }
  
  /// Add rule added listener
  void addRuleAddedListener(Function(NotificationRule) listener) {
    _onRuleAdded.add(listener);
  }
  
  /// Add rule triggered listener
  void addRuleTriggeredListener(Function(String) listener) {
    _onRuleTriggered.add(listener);
  }
  
  /// Remove notification added listener
  void removeNotificationAddedListener(Function(SmartNotification) listener) {
    _onNotificationAdded.remove(listener);
  }
  
  /// Remove notification read listener
  void removeNotificationReadListener(Function(SmartNotification) listener {
    _onNotificationRead.remove(listener);
  }
  
  /// Remove notification dismissed listener
  void removeNotificationDismissedListener(Function(SmartNotification) listener {
    _onNotificationDismissed.remove(listener);
  }
  
  /// Remove rule added listener
  void removeRuleAddedListener(Function(NotificationRule) listener) {
    _onRuleAdded.remove(listener);
  }
  
  /// Remove rule triggered listener
  void removeRuleTriggeredListener(Function(String) listener) {
    _onRuleTriggered.remove(listener);
  }
  
  /// Dispose notification system
  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    
    // Save final state
    await _saveNotifications();
    await _saveRules();
    
    // Clear listeners
    _onNotificationAdded.clear();
    _onNotificationRead.clear();
    _onNotificationDismissed.clear();
    _onRuleAdded.clear();
    _onRuleTriggered.clear();
    
    _isInitialized = false;
    debugPrint('🔔 Smart Notification System disposed');
  }
}

/// Smart notification model
class SmartNotification {
  final String id;
  final String title;
  final String message;
  final String channelId;
  final NotificationType type;
  final NotificationPriority priority;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? readAt;
  final DateTime? dismissedAt;
  final Map<String, dynamic> metadata;
  final String? icon;
  final String? sound;
  final bool persistent;
  final List<String> actions;
  final bool isRead;
  final bool isDismissed;
  
  SmartNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.channelId,
    required this.type,
    required this.priority,
    required this.createdAt,
    this.expiresAt,
    this.readAt,
    this.dismissedAt,
    this.metadata = const {},
    this.icon,
    this.sound,
    this.persistent = false,
    this.actions = const [],
    this.isRead = false,
    this.isDismissed = false,
  });
  
  SmartNotification copyWith({
    String? id,
    String? title,
    String? message,
    String? channelId,
    NotificationType? type,
    NotificationPriority? priority,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? readAt,
    DateTime? dismissedAt,
    Map<String, dynamic>? metadata,
    String? icon,
    String? sound,
    bool? persistent,
    List<String>? actions,
    bool? isRead,
    bool? isDismissed,
  }) {
    return SmartNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      channelId: channelId ?? this.channelId,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      readAt: readAt ?? this.readAt,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      metadata: metadata ?? this.metadata,
      icon: icon ?? this.icon,
      sound: sound ?? this.sound,
      persistent: persistent ?? this.persistent,
      actions: actions ?? this.actions,
      isRead: isRead ?? this.isRead,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }
  
  factory SmartNotification.fromJson(Map<String, dynamic> json) {
    return SmartNotification(
      id: json['id'],
      title: json['title'],
      message: json['message'],
      channelId: json['channel_id'],
      type: NotificationType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => NotificationType.info,
      ),
      priority: NotificationPriority.values.firstWhere(
        (p) => p.toString() == json['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null 
          ? DateTime.parse(json['expires_at'])
          : null,
      readAt: json['read_at'] != null 
          ? DateTime.parse(json['read_at'])
          : null,
      dismissedAt: json['dismissed_at'] != null 
          ? DateTime.parse(json['dismissed_at'])
          : null,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      icon: json['icon'],
      sound: json['sound'],
      persistent: json['persistent'] ?? false,
      actions: List<String>.from(json['actions'] ?? []),
      isRead: json['is_read'] ?? false,
      isDismissed: json['is_dismissed'] ?? false,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'channel_id': channelId,
      'type': type.toString(),
      'priority': priority.toString(),
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'read_at': readAt?.toIso8601String(),
      'dismissed_at': dismissedAt?.toIso8601String(),
      'metadata': metadata,
      'icon': icon,
      'sound': sound,
      'persistent': persistent,
      'actions': actions,
      'is_read': isRead,
      'is_dismissed': isDismissed,
    };
  }
}

/// Notification channel model
class NotificationChannel {
  final String id;
  final String name;
  final String description;
  final NotificationChannelType type;
  final NotificationPriority priority;
  
  NotificationChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.priority,
  });
}

/// Notification types
enum NotificationType {
  info,
  success,
  warning,
  error,
  terminal,
  collaboration,
  system,
}

/// Notification priorities
enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

/// Notification channel types
enum NotificationChannelType {
  broadcast,
  terminal,
  collaboration,
  system,
}

/// Notification rule model
class NotificationRule {
  final String id;
  final String name;
  final String? description;
  final NotificationRuleAction action;
  final String? channelId;
  final List<NotificationType> types;
  final NotificationPriority? minPriority;
  final String? contentFilter;
  final TimeFilter? timeFilter;
  final String? transformPattern;
  final Duration? delayDuration;
  final String? targetChannelId;
  final bool enabled;
  final DateTime createdAt;
  
  NotificationRule({
    required this.id,
    required this.name,
    this.description,
    required this.action,
    this.channelId,
    this.types = const [],
    this.minPriority,
    this.contentFilter,
    this.timeFilter,
    this.transformPattern,
    this.delayDuration,
    this.targetChannelId,
    this.enabled = true,
    required this.createdAt,
  });
  
  factory NotificationRule.fromJson(Map<String, dynamic> json) {
    return NotificationRule(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      action: NotificationRuleAction.values.firstWhere(
        (a) => a.toString() == json['action'],
        orElse: () => NotificationRuleAction.block,
      ),
      channelId: json['channel_id'],
      types: (json['types'] as List?)
          ?.map((t) => NotificationType.values.firstWhere(
            (nt) => nt.toString() == t,
            orElse: () => NotificationType.info,
          ))
          .toList() ?? [],
      minPriority: json['min_priority'] != null 
          ? NotificationPriority.values.firstWhere(
            (p) => p.toString() == json['min_priority'],
            orElse: () => NotificationPriority.normal,
          )
          : null,
      contentFilter: json['content_filter'],
      timeFilter: json['time_filter'] != null 
          ? TimeFilter.values.firstWhere(
            (tf) => tf.toString() == json['time_filter'],
            orElse: () => TimeFilter.none,
          )
          : null,
      transformPattern: json['transform_pattern'],
      delayDuration: json['delay_duration'] != null 
          ? Duration(milliseconds: json['delay_duration'])
          : null,
      targetChannelId: json['target_channel_id'],
      enabled: json['enabled'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'action': action.toString(),
      'channel_id': channelId,
      'types': types.map((t) => t.toString()).toList(),
      'min_priority': minPriority?.toString(),
      'content_filter': contentFilter,
      'time_filter': timeFilter?.toString(),
      'transform_pattern': transformPattern,
      'delay_duration': delayDuration?.inMilliseconds,
      'target_channel_id': targetChannelId,
      'enabled': enabled,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Notification rule actions
enum NotificationRuleAction {
  block,
  forward,
  transform,
  delay,
}

/// Time filters
enum TimeFilter {
  none,
  workHours,
  quietHours,
}
