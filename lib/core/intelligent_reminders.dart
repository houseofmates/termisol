import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

class IntelligentReminders {
  static const int _maxReminders = 100;
  static const int _reminderHistorySize = 50;
  static const int _checkInterval = 60000; // 1 minute
  static const int _importanceThreshold = 0.7;
  
  final Map<String, Reminder> _reminders = {};
  final List<ReminderEvent> _eventHistory = [];
  final Map<String, ImportanceScore> _importanceScores = {};
  
  Timer? _checkTimer;
  int _totalReminders = 0;
  int _totalNotifications = 0;
  
  final StreamController<ReminderEvent> _reminderController = 
      StreamController<ReminderEvent>.broadcast();

  void initialize() {
    _startCheckTimer();
    _initializeImportanceModels();
    developer.log('🔔 intelligent reminders initialized');
  }

  void _startCheckTimer() {
    _checkTimer = Timer.periodic(
      Duration(milliseconds: _checkInterval),
      (_) => _checkReminders(),
    );
  }

  void _initializeImportanceModels() {
    // Initialize importance scoring models
    _importanceScores['urgent'] = ImportanceScore(
      category: 'urgent',
      baseScore: 0.9,
      factors: {
        'deadline': 0.3,
        'priority': 0.4,
        'impact': 0.3,
      },
    );
    
    _importanceScores['work'] = ImportanceScore(
      category: 'work',
      baseScore: 0.7,
      factors: {
        'deadline': 0.2,
        'priority': 0.3,
        'impact': 0.5,
      },
    );
    
    _importanceScores['personal'] = ImportanceScore(
      category: 'personal',
      baseScore: 0.5,
      factors: {
        'deadline': 0.1,
        'priority': 0.2,
        'impact': 0.7,
      },
    );
    
    _importanceScores['meeting'] = ImportanceScore(
      category: 'meeting',
      baseScore: 0.8,
      factors: {
        'deadline': 0.4,
        'priority': 0.3,
        'impact': 0.3,
      },
    );
    
    _importanceScores['task'] = ImportanceScore(
      category: 'task',
      baseScore: 0.6,
      factors: {
        'deadline': 0.3,
        'priority': 0.4,
        'impact': 0.3,
      },
    );
  }

  String createReminder({
    required String title,
    required String description,
    required DateTime scheduledTime,
    String? category,
    ReminderPriority priority = ReminderPriority.normal,
    bool recurring = false,
    RecurrencePattern? recurrence,
    Map<String, dynamic>? metadata,
  }) {
    if (_reminders.length >= _maxReminders) {
      throw Exception('Maximum reminders reached');
    }
    
    final reminderId = _generateReminderId();
    
    // Calculate importance score using AI-like analysis
    final importanceScore = _calculateImportanceScore(
      title,
      description,
      category ?? 'task',
      priority,
      scheduledTime,
      metadata ?? {},
    );
    
    final reminder = Reminder(
      id: reminderId,
      title: title,
      description: description,
      scheduledTime: scheduledTime,
      category: category ?? 'task',
      priority: priority,
      importanceScore: importanceScore,
      recurring: recurring,
      recurrence: recurrence,
      metadata: metadata ?? {},
      createdAt: DateTime.now(),
      status: ReminderStatus.active,
    );
    
    _reminders[reminderId] = reminder;
    _totalReminders++;
    
    developer.log('🔔 Created reminder: $title (importance: ${importanceScore.toStringAsFixed(2)})');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.created,
      reminderId: reminderId,
      reminder: reminder,
    ));
    
    return reminderId;
  }

  double _calculateImportanceScore(
    String title,
    String description,
    String category,
    ReminderPriority priority,
    DateTime scheduledTime,
    Map<String, dynamic> metadata,
  ) {
    // Get base importance score for category
    final categoryScore = _importanceScores[category];
    if (categoryScore == null) {
      return 0.5; // Default score
    }
    
    double score = categoryScore.baseScore;
    
    // Adjust based on priority
    score += _getPriorityAdjustment(priority);
    
    // Adjust based on urgency (time until scheduled)
    final timeUntilScheduled = scheduledTime.difference(DateTime.now());
    final urgencyAdjustment = _getUrgencyAdjustment(timeUntilScheduled);
    score += urgencyAdjustment;
    
    // Adjust based on content analysis
    final contentAdjustment = _analyzeContentImportance(title, description);
    score += contentAdjustment;
    
    // Adjust based on metadata
    final metadataAdjustment = _analyzeMetadataImportance(metadata);
    score += metadataAdjustment;
    
    // Apply AI-like weighting
    score = _applyAIWeighting(score, categoryScore.factors);
    
    // Normalize to 0-1 range
    return score.clamp(0.0, 1.0);
  }

  double _getPriorityAdjustment(ReminderPriority priority) {
    switch (priority) {
      case ReminderPriority.low:
        return -0.2;
      case ReminderPriority.normal:
        return 0.0;
      case ReminderPriority.high:
        return 0.2;
      case ReminderPriority.urgent:
        return 0.4;
    }
  }

  double _getUrgencyAdjustment(Duration timeUntilScheduled) {
    if (timeUntilScheduled.isNegative) {
      return 0.3; // Overdue - increase importance
    }
    
    final hoursUntil = timeUntilScheduled.inHours;
    
    if (hoursUntil <= 1) {
      return 0.3; // Very urgent
    } else if (hoursUntil <= 24) {
      return 0.2; // Urgent
    } else if (hoursUntil <= 168) { // 1 week
      return 0.1; // Somewhat urgent
    } else {
      return 0.0; // Not urgent
    }
  }

  double _analyzeContentImportance(String title, String description) {
    final combinedText = '$title $description'.toLowerCase();
    
    double importance = 0.0;
    
    // High importance keywords
    final highImportanceWords = [
      'urgent', 'critical', 'emergency', 'asap', 'immediately',
      'deadline', 'due', 'overdue', 'late', 'important',
      'meeting', 'appointment', 'interview', 'presentation',
      'payment', 'bill', 'invoice', 'contract', 'agreement',
    ];
    
    for (final word in highImportanceWords) {
      if (combinedText.contains(word)) {
        importance += 0.1;
      }
    }
    
    // Medium importance keywords
    final mediumImportanceWords = [
      'review', 'check', 'update', 'follow up', 'call',
      'email', 'message', 'report', 'document',
      'project', 'task', 'assignment', 'homework',
    ];
    
    for (final word in mediumImportanceWords) {
      if (combinedText.contains(word)) {
        importance += 0.05;
      }
    }
    
    // Negative indicators (reduce importance)
    final negativeWords = [
      'optional', 'suggestion', 'idea', 'maybe', 'consider',
      'later', 'someday', 'eventually', 'when possible',
    ];
    
    for (final word in negativeWords) {
      if (combinedText.contains(word)) {
        importance -= 0.05;
      }
    }
    
    return importance.clamp(-0.2, 0.3);
  }

  double _analyzeMetadataImportance(Map<String, dynamic> metadata) {
    double importance = 0.0;
    
    // Check for work-related metadata
    if (metadata.containsKey('project') || metadata.containsKey('client')) {
      importance += 0.1;
    }
    
    // Check for financial metadata
    if (metadata.containsKey('amount') || metadata.containsKey('cost')) {
      importance += 0.15;
    }
    
    // Check for people metadata
    if (metadata.containsKey('attendees') || metadata.containsKey('people')) {
      importance += 0.1;
    }
    
    // Check for location metadata
    if (metadata.containsKey('location') || metadata.containsKey('venue')) {
      importance += 0.05;
    }
    
    return importance.clamp(0.0, 0.3);
  }

  double _applyAIWeighting(double baseScore, Map<String, double> factors) {
    // Simulate AI-like weighting using learned factors
    double weightedScore = baseScore;
    
    // Apply deadline factor
    weightedScore *= (1.0 + factors['deadline'] ?? 0.0);
    
    // Apply priority factor
    weightedScore *= (1.0 + factors['priority'] ?? 0.0);
    
    // Apply impact factor
    weightedScore *= (1.0 + factors['impact'] ?? 0.0);
    
    // Apply some randomness to simulate AI uncertainty
    final randomFactor = 0.95 + (Random().nextDouble() * 0.1);
    weightedScore *= randomFactor;
    
    return weightedScore.clamp(0.0, 1.0);
  }

  void _checkReminders() {
    final now = DateTime.now();
    
    for (final reminder in _reminders.values) {
      if (reminder.status != ReminderStatus.active) continue;
      
      // Check if it's time to notify
      if (_shouldNotifyReminder(reminder, now)) {
        _notifyReminder(reminder);
      }
      
      // Check for overdue reminders
      if (_isOverdueReminder(reminder, now)) {
        _handleOverdueReminder(reminder);
      }
    }
  }

  bool _shouldNotifyReminder(Reminder reminder, DateTime now) {
    final timeDifference = reminder.scheduledTime.difference(now);
    
    // Notify 15 minutes before for high importance
    if (reminder.importanceScore >= _importanceThreshold &&
        timeDifference.inMinutes <= 15 &&
        timeDifference.inMinutes > 0) {
      return true;
    }
    
    // Notify 5 minutes before for normal importance
    if (reminder.importanceScore < _importanceThreshold &&
        timeDifference.inMinutes <= 5 &&
        timeDifference.inMinutes > 0) {
      return true;
    }
    
    // Notify if it's time
    if (timeDifference.inMinutes <= 0 && !reminder.notified) {
      return true;
    }
    
    return false;
  }

  bool _isOverdueReminder(Reminder reminder, DateTime now) {
    return now.isAfter(reminder.scheduledTime) && 
           reminder.status == ReminderStatus.active &&
           !reminder.notified;
  }

  void _notifyReminder(Reminder reminder) {
    reminder.notified = true;
    reminder.lastNotified = DateTime.now();
    _totalNotifications++;
    
    developer.log('🔔 Notifying: ${reminder.title} (importance: ${reminder.importanceScore.toStringAsFixed(2)})');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.notified,
      reminderId: reminder.id,
      reminder: reminder,
    ));
    
    // Add to event history
    _eventHistory.add(ReminderEvent(
      type: ReminderEventType.notified,
      reminderId: reminder.id,
      reminder: reminder,
    ));
    
    if (_eventHistory.length > _reminderHistorySize) {
      _eventHistory.removeAt(0);
    }
  }

  void _handleOverdueReminder(Reminder reminder) {
    reminder.status = ReminderStatus.overdue;
    
    developer.log('🔔 Overdue reminder: ${reminder.title}');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.overdue,
      reminderId: reminder.id,
      reminder: reminder,
    ));
  }

  void dismissReminder(String reminderId) {
    final reminder = _reminders[reminderId];
    if (reminder == null) return;
    
    reminder.status = ReminderStatus.dismissed;
    reminder.dismissedAt = DateTime.now();
    
    developer.log('🔔 Dismissed reminder: ${reminder.title}');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.dismissed,
      reminderId: reminderId,
      reminder: reminder,
    ));
  }

  void completeReminder(String reminderId) {
    final reminder = _reminders[reminderId];
    if (reminder == null) return;
    
    reminder.status = ReminderStatus.completed;
    reminder.completedAt = DateTime.now();
    
    // Handle recurring reminders
    if (reminder.recurring && reminder.recurrence != null) {
      _scheduleNextRecurrence(reminder);
    }
    
    developer.log('🔔 Completed reminder: ${reminder.title}');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.completed,
      reminderId: reminderId,
      reminder: reminder,
    ));
  }

  void _scheduleNextRecurrence(Reminder reminder) {
    if (reminder.recurrence == null) return;
    
    DateTime nextTime;
    
    switch (reminder.recurrence!.type) {
      case RecurrenceType.daily:
        nextTime = reminder.scheduledTime.add(Duration(days: 1));
        break;
      case RecurrenceType.weekly:
        nextTime = reminder.scheduledTime.add(Duration(days: 7));
        break;
      case RecurrenceType.monthly:
        nextTime = DateTime(
          reminder.scheduledTime.year,
          reminder.scheduledTime.month + 1,
          reminder.scheduledTime.day,
          reminder.scheduledTime.hour,
          reminder.scheduledTime.minute,
        );
        break;
      case RecurrenceType.yearly:
        nextTime = DateTime(
          reminder.scheduledTime.year + 1,
          reminder.scheduledTime.month,
          reminder.scheduledTime.day,
          reminder.scheduledTime.hour,
          reminder.scheduledTime.minute,
        );
        break;
    }
    
    // Reset reminder for next occurrence
    reminder.scheduledTime = nextTime;
    reminder.status = ReminderStatus.active;
    reminder.notified = false;
    reminder.dismissedAt = null;
    reminder.completedAt = null;
    
    developer.log('🔔 Scheduled next recurrence: ${reminder.title} at $nextTime');
  }

  void snoozeReminder(String reminderId, Duration snoozeDuration) {
    final reminder = _reminders[reminderId];
    if (reminder == null) return;
    
    reminder.scheduledTime = DateTime.now().add(snoozeDuration);
    reminder.status = ReminderStatus.active;
    reminder.notified = false;
    reminder.snoozeCount = (reminder.snoozeCount ?? 0) + 1;
    
    developer.log('🔔 Snoozed reminder: ${reminder.title} for ${snoozeDuration.inMinutes} minutes');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.snoozed,
      reminderId: reminderId,
      reminder: reminder,
      data: {'snoozeDuration': snoozeDuration.inMinutes},
    ));
  }

  void updateReminderImportance(String reminderId) {
    final reminder = _reminders[reminderId];
    if (reminder == null) return;
    
    // Recalculate importance score
    final newScore = _calculateImportanceScore(
      reminder.title,
      reminder.description,
      reminder.category,
      reminder.priority,
      reminder.scheduledTime,
      reminder.metadata,
    );
    
    reminder.importanceScore = newScore;
    
    developer.log('🔔 Updated importance for ${reminder.title}: ${newScore.toStringAsFixed(2)}');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.importanceUpdated,
      reminderId: reminderId,
      reminder: reminder,
    ));
  }

  List<Reminder> getReminders({ReminderStatus? status, String? category}) {
    var reminders = _reminders.values.toList();
    
    if (status != null) {
      reminders = reminders.where((r) => r.status == status).toList();
    }
    
    if (category != null) {
      reminders = reminders.where((r) => r.category == category).toList();
    }
    
    // Sort by importance and scheduled time
    reminders.sort((a, b) {
      if (a.importanceScore != b.importanceScore) {
        return b.importanceScore.compareTo(a.importanceScore);
      }
      return a.scheduledTime.compareTo(b.scheduledTime);
    });
    
    return reminders;
  }

  List<Reminder> getUpcomingReminders({int hours = 24}) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(hours: hours));
    
    return _reminders.values
        .where((r) => 
            r.status == ReminderStatus.active &&
            r.scheduledTime.isAfter(now) &&
            r.scheduledTime.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  }

  List<Reminder> getHighImportanceReminders() {
    return _reminders.values
        .where((r) => 
            r.status == ReminderStatus.active &&
            r.importanceScore >= _importanceThreshold)
        .toList()
      ..sort((a, b) => b.importanceScore.compareTo(a.importanceScore));
  }

  void deleteReminder(String reminderId) {
    final reminder = _reminders.remove(reminderId);
    if (reminder == null) return;
    
    developer.log('🔔 Deleted reminder: ${reminder.title}');
    
    _emitEvent(ReminderEvent(
      type: ReminderEventType.deleted,
      reminderId: reminderId,
      reminder: reminder,
    ));
  }

  String _generateReminderId() {
    return 'reminder_${DateTime.now().millisecondsSinceEpoch}_$_totalReminders';
  }

  void _emitEvent(ReminderEvent event) {
    _reminderController.add(event);
  }

  Stream<ReminderEvent> get reminderStream => _reminderController.stream;

  IntelligentRemindersStats getStats() {
    final activeReminders = _reminders.values
        .where((r) => r.status == ReminderStatus.active)
        .length;
    
    final overdueReminders = _reminders.values
        .where((r) => r.status == ReminderStatus.overdue)
        .length;
    
    final highImportanceReminders = _reminders.values
        .where((r) => r.importanceScore >= _importanceThreshold)
        .length;
    
    return IntelligentRemindersStats(
      totalReminders: _totalReminders,
      activeReminders: activeReminders,
      overdueReminders: overdueReminders,
      highImportanceReminders: highImportanceReminders,
      totalNotifications: _totalNotifications,
      eventHistorySize: _eventHistory.length,
    );
  }

  void dispose() {
    _checkTimer?.cancel();
    _reminders.clear();
    _eventHistory.clear();
    _importanceScores.clear();
    _reminderController.close();
    developer.log('🔔 Intelligent Reminders disposed');
  }
}

class Reminder {
  final String id;
  final String title;
  final String description;
  DateTime scheduledTime;
  final String category;
  final ReminderPriority priority;
  double importanceScore;
  final bool recurring;
  final RecurrencePattern? recurrence;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  
  ReminderStatus status = ReminderStatus.active;
  bool notified = false;
  DateTime? lastNotified;
  DateTime? dismissedAt;
  DateTime? completedAt;
  int? snoozeCount;

  Reminder({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledTime,
    required this.category,
    required this.priority,
    required this.importanceScore,
    required this.recurring,
    this.recurrence,
    required this.metadata,
    required this.createdAt,
  });
}

class ImportanceScore {
  final String category;
  final double baseScore;
  final Map<String, double> factors;

  ImportanceScore({
    required this.category,
    required this.baseScore,
    required this.factors,
  });
}

class RecurrencePattern {
  final RecurrenceType type;
  final int interval;
  final DateTime? endDate;

  RecurrencePattern({
    required this.type,
    required this.interval,
    this.endDate,
  });
}

enum ReminderPriority {
  low,
  normal,
  high,
  urgent,
}

enum ReminderStatus {
  active,
  notified,
  dismissed,
  completed,
  overdue,
}

enum RecurrenceType {
  daily,
  weekly,
  monthly,
  yearly,
}

enum ReminderEventType {
  created,
  notified,
  dismissed,
  completed,
  snoozed,
  overdue,
  deleted,
  importanceUpdated,
}

class ReminderEvent {
  final ReminderEventType type;
  final String reminderId;
  final Reminder? reminder;
  final Map<String, dynamic>? data;

  ReminderEvent({
    required this.type,
    required this.reminderId,
    this.reminder,
    this.data,
  });
}

class IntelligentRemindersStats {
  final int totalReminders;
  final int activeReminders;
  final int overdueReminders;
  final int highImportanceReminders;
  final int totalNotifications;
  final int eventHistorySize;

  IntelligentRemindersStats({
    required this.totalReminders,
    required this.activeReminders,
    required this.overdueReminders,
    required this.highImportanceReminders,
    required this.totalNotifications,
    required this.eventHistorySize,
  });
}
