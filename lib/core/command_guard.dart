import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:termisol/core/logging_system.dart';

class CommandGuard {
  static const String _rulesFile = '/home/house/.termisol_command_guard.json';
  static const int _maxRules = 200;
  static const int _maxHistory = 500;

  final List<GuardRule> _rules = [];
  final List<GuardAction> _actionHistory = [];
  bool _isEnabled = true;
  bool _isInitialized = false;

  final StreamController<GuardEvent> _eventController =
      StreamController<GuardEvent>.broadcast();

  Stream<GuardEvent> get events => _eventController.stream;
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  List<GuardRule> get rules => List.unmodifiable(_rules);

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadRules();
    _isInitialized = true;
  }

  Future<void> _loadRules() async {
    try {
      final file = File(_rulesFile);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _isEnabled = data['enabled'] ?? true;
      final rulesData = data['rules'] as List<dynamic>? ?? [];
      for (final item in rulesData) {
        _rules.add(GuardRule.fromJson(item));
      }
    } catch (e) {
      TermisolLogger().error('CommandGuard: failed to load rules', error: e);
    }
  }

  Future<void> _saveRules() async {
    final data = {
      'enabled': _isEnabled,
      'rules': _rules.map((r) => r.toJson()).toList(),
      'savedAt': DateTime.now().toIso8601String(),
    };
    await File(_rulesFile).writeAsString(jsonEncode(data));
  }

  void toggleEnabled() {
    _isEnabled = !_isEnabled;
    _saveRules();
    _eventController.add(GuardEvent(
      type: GuardEventType.toggled,
      message: _isEnabled ? 'Command guard enabled' : 'Command guard disabled',
    ));
  }

  Future<GuardRule> addRule({
    required String pattern,
    String? description,
    GuardActionType action = GuardActionType.confirm,
    bool isRegex = false,
  }) async {
    if (_rules.length >= _maxRules) {
      throw Exception('Maximum rules limit ($_maxRules) reached');
    }

    if (_rules.any((r) => r.pattern == pattern)) {
      throw Exception('Rule with pattern "$pattern" already exists');
    }

    final rule = GuardRule(
      id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
      pattern: pattern,
      description: description ?? '',
      action: action,
      isRegex: isRegex,
      enabled: true,
      createdAt: DateTime.now(),
      matchCount: 0,
    );

    _rules.add(rule);
    await _saveRules();

    _eventController.add(GuardEvent(
      type: GuardEventType.ruleAdded,
      message: 'Rule added: "$pattern"',
      ruleId: rule.id,
    ));

    return rule;
  }

  Future<void> removeRule(String id) async {
    final idx = _rules.indexWhere((r) => r.id == id);
    if (idx == -1) return;

    final removed = _rules.removeAt(idx);
    await _saveRules();

    _eventController.add(GuardEvent(
      type: GuardEventType.ruleRemoved,
      message: 'Rule removed: "${removed.pattern}"',
      ruleId: id,
    ));
  }

  Future<void> updateRule(String id, {
    String? pattern,
    String? description,
    GuardActionType? action,
    bool? isRegex,
    bool? enabled,
  }) async {
    final rule = _rules.firstWhere((r) => r.id == id);
    if (pattern != null) rule.pattern = pattern;
    if (description != null) rule.description = description;
    if (action != null) rule.action = action;
    if (isRegex != null) rule.isRegex = isRegex;
    if (enabled != null) rule.enabled = enabled;
    await _saveRules();
    _eventController.add(GuardEvent(
      type: GuardEventType.ruleUpdated,
      message: 'Rule updated: "$id"',
      ruleId: id,
    ));
  }

  Future<void> toggleRule(String id) async {
    final rule = _rules.firstWhere((r) => r.id == id);
    rule.enabled = !rule.enabled;
    await _saveRules();
    _eventController.add(GuardEvent(
      type: GuardEventType.ruleToggled,
      message: 'Rule "${rule.pattern}" ${rule.enabled ? "enabled" : "disabled"}',
      ruleId: id,
    ));
  }

  GuardCheckResult checkCommand(String command) {
    if (!_isEnabled) {
      return GuardCheckResult(allowed: true, matchedRule: null);
    }

    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return GuardCheckResult(allowed: true, matchedRule: null);
    }

    for (final rule in _rules) {
      if (!rule.enabled) continue;

      bool matches = false;
      if (rule.isRegex) {
        try {
          matches = RegExp(rule.pattern).hasMatch(trimmed);
        } catch (_) {
          continue;
        }
      } else {
        matches = trimmed.toLowerCase().contains(rule.pattern.toLowerCase());
      }

      if (matches) {
        rule.matchCount++;
        rule.lastMatchAt = DateTime.now();

        _actionHistory.add(GuardAction(
          command: trimmed,
          ruleId: rule.id,
          rulePattern: rule.pattern,
          action: rule.action,
          timestamp: DateTime.now(),
        ));
        if (_actionHistory.length > _maxHistory) _actionHistory.removeAt(0);

        _eventController.add(GuardEvent(
          type: GuardEventType.commandBlocked,
          message: 'Command matched rule: "${rule.pattern}"',
          ruleId: rule.id,
        ));

        return GuardCheckResult(allowed: false, matchedRule: rule);
      }
    }

    return GuardCheckResult(allowed: true, matchedRule: null);
  }

  void confirmBlockedCommand(String commandId) {
    final idx = _actionHistory.indexWhere((a) =>
        a.command == commandId && a.action == GuardActionType.confirm);
    if (idx >= 0) {
      _actionHistory[idx].confirmed = true;
    }
  }

  String exportRules() {
    return jsonEncode({
      'enabled': _isEnabled,
      'rules': _rules.map((r) => r.toJson()).toList(),
    });
  }

  Future<void> importRules(String jsonData) async {
    final data = jsonDecode(jsonData) as Map<String, dynamic>;
    final imported = (data['rules'] as List<dynamic>)
        .map((r) => GuardRule.fromJson(r))
        .toList();

    for (final rule in imported) {
      if (_rules.any((r) => r.pattern == rule.pattern)) continue;
      if (_rules.length >= _maxRules) break;
      _rules.add(rule);
    }

    await _saveRules();
    _eventController.add(GuardEvent(
      type: GuardEventType.rulesImported,
      message: 'Imported ${imported.length} rules',
    ));
  }

  List<GuardAction> getHistory() => List.unmodifiable(_actionHistory);

  void dispose() {
    _eventController.close();
    _isInitialized = false;
  }
}

class GuardRule {
  final String id;
  String pattern;
  String description;
  GuardActionType action;
  bool isRegex;
  bool enabled;
  final DateTime createdAt;
  int matchCount;
  DateTime? lastMatchAt;

  GuardRule({
    required this.id,
    required this.pattern,
    required this.description,
    required this.action,
    required this.isRegex,
    required this.enabled,
    required this.createdAt,
    this.matchCount = 0,
    this.lastMatchAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'pattern': pattern,
    'description': description,
    'action': action.name,
    'isRegex': isRegex,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'matchCount': matchCount,
    'lastMatchAt': lastMatchAt?.toIso8601String(),
  };

  factory GuardRule.fromJson(Map<String, dynamic> json) => GuardRule(
    id: json['id'] ?? 'rule_${DateTime.now().millisecondsSinceEpoch}',
    pattern: json['pattern'] ?? '',
    description: json['description'] ?? '',
    action: GuardActionType.values.firstWhere(
      (a) => a.name == json['action'],
      orElse: () => GuardActionType.confirm,
    ),
    isRegex: json['isRegex'] ?? false,
    enabled: json['enabled'] ?? true,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
    matchCount: json['matchCount'] ?? 0,
    lastMatchAt: json['lastMatchAt'] != null
        ? DateTime.parse(json['lastMatchAt'])
        : null,
  );
}

enum GuardActionType { confirm, block, warn }

class GuardCheckResult {
  final bool allowed;
  final GuardRule? matchedRule;

  GuardCheckResult({required this.allowed, this.matchedRule});
}

class GuardAction {
  final String command;
  final String ruleId;
  final String rulePattern;
  final GuardActionType action;
  final DateTime timestamp;
  bool confirmed;

  GuardAction({
    required this.command,
    required this.ruleId,
    required this.rulePattern,
    required this.action,
    required this.timestamp,
    this.confirmed = false,
  });
}

enum GuardEventType {
  toggled,
  ruleAdded,
  ruleRemoved,
  ruleUpdated,
  ruleToggled,
  rulesImported,
  commandBlocked,
}

class GuardEvent {
  final GuardEventType type;
  final String message;
  final String? ruleId;
  final DateTime timestamp;

  GuardEvent({
    required this.type,
    required this.message,
    this.ruleId,
  }) : timestamp = DateTime.now();
}