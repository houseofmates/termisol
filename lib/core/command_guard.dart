import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Command Guard
///
/// Prevents execution of dangerous commands by matching against
/// configurable safety rules with confirmation prompts, allowlists,
/// and severity classification.
class CommandGuard {
  final List<SafetyRule> _rules = [];
  final Set<String> _allowlistedCommands = {};
  final Set<String> _blocklistedCommands = {};
  final Map<String, int> _warnCount = {};
  bool _enabled = true;
  bool _strictMode = false;
  GuardMode _mode = GuardMode.warn;
  final StreamController<GuardEvent> _eventController = StreamController<GuardEvent>.broadcast();

  Stream<GuardEvent> get events => _eventController.stream;
  bool get isEnabled => _enabled;
  GuardMode get mode => _mode;

  Future<void> initialize({GuardMode mode = GuardMode.warn, bool strict = false}) async {
    _mode = mode;
    _strictMode = strict;
    _registerDefaultRules();
    await _loadPersistedState();
    debugPrint('CommandGuard initialized (mode: ${mode.name}, strict: $strict)');
  }

  GuardResult evaluate(String command) {
    if (!_enabled) return GuardResult.allowed(command);

    final trimmed = command.trim();
    if (trimmed.isEmpty) return GuardResult.allowed(command);

    if (_allowlistedCommands.contains(trimmed) || _allowlistedCommands.any((a) => trimmed == a)) {
      return GuardResult.allowed(command);
    }

    if (_blocklistedCommands.contains(trimmed) || _blocklistedCommands.any((b) => trimmed == b)) {
      _emitEvent(command, GuardAction.blocked, 'Command is blocklisted');
      return GuardResult(safe: false, action: GuardAction.blocked, command: command, reason: 'Command is blocklisted');
    }

    for (final rule in _rules) {
      if (rule.matches(trimmed)) {
        switch (_mode) {
          case GuardMode.block:
            return _handleBlock(command, rule);
          case GuardMode.warn:
            return _handleWarn(command, rule);
          case GuardMode.confirm:
            return _handleConfirm(command, rule);
          case GuardMode.log_only:
            _emitEvent(command, GuardAction.logged, rule.description);
            return GuardResult.allowed(command);
        }
      }
    }

    return GuardResult.allowed(command);
  }

  GuardResult _handleBlock(String command, SafetyRule rule) {
    _emitEvent(command, GuardAction.blocked, rule.description);
    return GuardResult(safe: false, action: GuardAction.blocked, command: command, reason: rule.description, severity: rule.severity);
  }

  GuardResult _handleWarn(String command, SafetyRule rule) {
    _warnCount[command] = (_warnCount[command] ?? 0) + 1;
    _emitEvent(command, GuardAction.warned, rule.description);
    return GuardResult(safe: true, action: GuardAction.warned, command: command, reason: rule.description, severity: rule.severity);
  }

  GuardResult _handleConfirm(String command, SafetyRule rule) {
    _emitEvent(command, GuardAction.confirmation, rule.description);
    return GuardResult(safe: false, action: GuardAction.confirmation, command: command, reason: rule.description, severity: rule.severity);
  }

  void setEnabled(bool enabled) { _enabled = enabled; }
  void setMode(GuardMode mode) { _mode = mode; }
  void setStrict(bool strict) { _strictMode = strict; }

  void addAllowlisted(String command) { _allowlistedCommands.add(command.trim()); persist(); }
  void removeAllowlisted(String command) { _allowlistedCommands.remove(command.trim()); persist(); }

  void addBlocklisted(String command) { _blocklistedCommands.add(command.trim()); persist(); }
  void removeBlocklisted(String command) { _blocklistedCommands.remove(command.trim()); persist(); }

  void addRule(SafetyRule rule) { _rules.add(rule); }
  void removeRule(String name) { _rules.removeWhere((r) => r.name == name); }

  List<SafetyRule> getRules() => List.unmodifiable(_rules);
  Set<String> getAllowlist() => Set.unmodifiable(_allowlistedCommands);

  int getWarningCount(String command) => _warnCount[command] ?? 0;
  void resetWarningCount() { _warnCount.clear(); }

  String describeRisk(String command) {
    final result = evaluate(command);
    return result.safetyDescription;
  }

  void _emitEvent(String command, GuardAction action, String reason) {
    _eventController.add(GuardEvent(command: command, action: action, reason: reason));
  }

  void _registerDefaultRules() {
    _rules.addAll([
      SafetyRule(name: 'rm_rf_root', description: 'Deleting root filesystem',
          pattern: RegExp(r'\brm\s+-rf\s+(?:/|\*|\.\*)', caseSensitive: false), severity: GuardSeverity.critical),
      SafetyRule(name: 'rm_rf_home', description: 'Deleting home directory',
          pattern: RegExp(r'\brm\s+-rf\s+(?:~|/home|$HOME)', caseSensitive: false), severity: GuardSeverity.critical),
      SafetyRule(name: 'fork_bomb', description: 'Fork bomb pattern',
          pattern: RegExp(r'():\(\)\s*\{'),
          severity: GuardSeverity.critical),
      SafetyRule(name: 'dd_root', description: 'DD to root device',
          pattern: RegExp(r'\bdd\s+.*of=/dev/sd[a-z]\b', caseSensitive: false), severity: GuardSeverity.critical),
      SafetyRule(name: 'mkfs_unintended', description: 'Formatting a device',
          pattern: RegExp(r'\bmkfs\.\S+\s+/dev/(?!null|zero|random|urandom)', caseSensitive: false), severity: GuardSeverity.critical),
      SafetyRule(name: 'chmod_777_root', description: 'World-writable permissions on system',
          pattern: RegExp(r'\bchmod\s+.*777\s+/(?:etc|bin|sbin|usr|var|lib|boot|sys|proc)', caseSensitive: false), severity: GuardSeverity.high),
      SafetyRule(name: 'wget_pipe_exec', description: 'Piping wget/curl download to shell',
          pattern: RegExp(r'\b(?:wget|curl).*\|.*\b(?:sh|bash)', caseSensitive: false), severity: GuardSeverity.high),
      SafetyRule(name: 'eval_exec', description: 'Evaluating dynamic content in shell',
          pattern: RegExp(r'\beval\s+["\']\$', caseSensitive: false), severity: GuardSeverity.high),
      SafetyRule(name: 'force_push', description: 'Force push to protected branch',
          pattern: RegExp(r'git\s+push\s+.*(?:--force|-f).*\b(?:main|master|production)\b', caseSensitive: false), severity: GuardSeverity.medium),
      SafetyRule(name: 'drop_table', description: 'Dropping database table',
          pattern: RegExp(r'\bDROP\s+TABLE\b', caseSensitive: true), severity: GuardSeverity.medium),
      SafetyRule(name: 'shutdown_reboot', description: 'System shutdown',
          pattern: RegExp(r'\b(?:shutdown|reboot|halt|poweroff)\b', caseSensitive: false), severity: GuardSeverity.medium),
      SafetyRule(name: 'kill_signal', description: 'Kill process with signal',
          pattern: RegExp(r'\bkill\s+-9\b', caseSensitive: false), severity: GuardSeverity.low),
    ]);
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('command_guard_allowlist', json.encode(_allowlistedCommands.toList()));
      await prefs.setString('command_guard_blocklist', json.encode(_blocklistedCommands.toList()));
    } catch (_) {}
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allowStr = prefs.getString('command_guard_allowlist');
      if (allowStr != null) {
        final list = json.decode(allowStr) as List;
        _allowlistedCommands.addAll(list.cast<String>());
      }
      final blockStr = prefs.getString('command_guard_blocklist');
      if (blockStr != null) {
        final list = json.decode(blockStr) as List;
        _blocklistedCommands.addAll(list.cast<String>());
      }
    } catch (_) {}
  }

  void dispose() {
    _eventController.close();
    _rules.clear();
    _allowlistedCommands.clear();
    _blocklistedCommands.clear();
  }
}

enum GuardMode { block, warn, confirm, log_only }
enum GuardAction { allowed, blocked, warned, confirmation, logged }
enum GuardSeverity { low, medium, high, critical }

class SafetyRule {
  final String name;
  final String description;
  final RegExp pattern;
  final GuardSeverity severity;

  SafetyRule({
    required this.name,
    required this.description,
    required this.pattern,
    this.severity = GuardSeverity.medium,
  });

  bool matches(String command) => pattern.hasMatch(command);
}

class GuardResult {
  final bool safe;
  final GuardAction action;
  final String command;
  final String? reason;
  final GuardSeverity severity;

  GuardResult({
    required this.safe,
    this.action = GuardAction.allowed,
    required this.command,
    this.reason,
    this.severity = GuardSeverity.low,
  });

  bool get isExecutable => safe || action == GuardAction.warned;
  bool get needsApproval => action == GuardAction.confirmation;

  String get safetyDescription {
    if (safe && action == GuardAction.allowed) return 'Safe to execute';
    if (reason != null) return '${action.name}: $reason';
    return action.name;
  }

  factory GuardResult.allowed(String command) =>
      GuardResult(safe: true, action: GuardAction.allowed, command: command);
}

class GuardEvent {
  final String command;
  final GuardAction action;
  final String reason;
  final DateTime timestamp;

  GuardEvent({required this.command, required this.action, required this.reason})
      : timestamp = DateTime.now();
}