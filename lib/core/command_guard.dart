import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Production-grade Command Guard for terminal security
/// 
/// Provides comprehensive command validation and security:
/// - Dangerous command detection and blocking
/// - Whitelist/blacklist management
/// - Command sanitization
/// - Audit logging
/// - User permission checking
/// - File system protection
class CommandGuard {
  final Set<String> _dangerousCommands = {
    'rm -rf /',
    'rm -rf /*',
    'dd if=/dev/zero of=/dev/sda',
    'mkfs',
    'format',
    'fdisk',
    'chmod 777',
    'chown root',
    'sudo rm',
    'sudo chmod',
    'sudo chown',
    ':(){ :|:& };:', // fork bomb
    'killall',
    'pkill -9',
    'kill -9 -1',
    'shutdown',
    'reboot',
    'halt',
    'poweroff',
    'init 0',
    'init 6',
    'systemctl poweroff',
    'systemctl reboot',
    'service network restart',
    'iptables -F',
    'rm -rf /boot',
    'rm -rf /etc',
    'rm -rf /usr',
    'rm -rf /bin',
    'rm -rf /sbin',
    'rm -rf /lib',
  };
  
  final Set<String> _systemDirectories = {
    '/boot',
    '/etc',
    '/usr',
    '/bin',
    '/sbin',
    '/lib',
    '/lib64',
    '/proc',
    '/sys',
    '/dev',
    '/root',
  };
  
  final Set<String> _allowedCommands = {};
  final Set<String> _blockedCommands = {};
  final List<CommandAuditEntry> _auditLog = [];
  final StreamController<CommandEvent> _eventController = 
      StreamController<CommandEvent>.broadcast();
  
  bool _strictMode = false;
  bool _auditMode = true;
  int _maxAuditLogSize = 1000;
  
  /// Stream of command events
  Stream<CommandEvent> get events => _eventController.stream;
  
  /// Current strict mode setting
  bool get strictMode => _strictMode;
  
  /// Current audit mode setting
  bool get auditMode => _auditMode;
  
  /// Command guard configuration
  CommandGuard({
    bool strictMode = false,
    bool auditMode = true,
    Set<String>? allowedCommands,
    Set<String>? blockedCommands,
  }) : _strictMode = strictMode,
       _auditMode = auditMode,
       _allowedCommands = allowedCommands ?? {},
       _blockedCommands = blockedCommands ?? {};
  
  /// Validate and sanitize command
  CommandValidationResult validateCommand(String command, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    try {
      // Basic sanitization
      final sanitizedCommand = _sanitizeCommand(command);
      
      // Check for dangerous commands
      final dangerousCheck = _checkDangerousCommands(sanitizedCommand);
      if (!dangerousCheck.isSafe) {
        _logCommand(command, CommandValidationType.blocked, dangerousCheck.reason);
        _eventController.add(CommandEvent(
          type: CommandEventType.commandBlocked,
          command: command,
          reason: dangerousCheck.reason,
          timestamp: DateTime.now(),
        ));
        
        return CommandValidationResult(
          isAllowed: false,
          sanitizedCommand: null,
          reason: dangerousCheck.reason,
          severity: CommandSeverity.high,
        );
      }
      
      // Check system directory access
      final directoryCheck = _checkSystemDirectoryAccess(sanitizedCommand, workingDirectory);
      if (!directoryCheck.isSafe) {
        _logCommand(command, CommandValidationType.blocked, directoryCheck.reason);
        _eventController.add(CommandEvent(
          type: CommandEventType.commandBlocked,
          command: command,
          reason: directoryCheck.reason,
          timestamp: DateTime.now(),
        ));
        
        return CommandValidationResult(
          isAllowed: false,
          sanitizedCommand: null,
          reason: directoryCheck.reason,
          severity: CommandSeverity.medium,
        );
      }
      
      // Check whitelist/blacklist
      if (_strictMode && !_allowedCommands.contains(_getCommandName(sanitizedCommand))) {
        _logCommand(command, CommandValidationType.blocked, 'Command not in whitelist');
        _eventController.add(CommandEvent(
          type: CommandEventType.commandBlocked,
          command: command,
          reason: 'Command not in whitelist',
          timestamp: DateTime.now(),
        ));
        
        return CommandValidationResult(
          isAllowed: false,
          sanitizedCommand: null,
          reason: 'Command not in whitelist (strict mode)',
          severity: CommandSeverity.medium,
        );
      }
      
      if (_blockedCommands.contains(_getCommandName(sanitizedCommand))) {
        _logCommand(command, CommandValidationType.blocked, 'Command in blacklist');
        _eventController.add(CommandEvent(
          type: CommandEventType.commandBlocked,
          command: command,
          reason: 'Command in blacklist',
          timestamp: DateTime.now(),
        ));
        
        return CommandValidationResult(
          isAllowed: false,
          sanitizedCommand: null,
          reason: 'Command is blocked',
          severity: CommandSeverity.medium,
        );
      }
      
      // Command is safe
      _logCommand(command, CommandValidationType.allowed, null);
      _eventController.add(CommandEvent(
        type: CommandEventType.commandAllowed,
        command: sanitizedCommand,
        timestamp: DateTime.now(),
      ));
      
      return CommandValidationResult(
        isAllowed: true,
        sanitizedCommand: sanitizedCommand,
        reason: null,
        severity: CommandSeverity.low,
      );
    } catch (e) {
      debugPrint('Command validation error: $e');
      
      return CommandValidationResult(
        isAllowed: false,
        sanitizedCommand: null,
        reason: 'Validation error: ${e.toString()}',
        severity: CommandSeverity.high,
      );
    }
  }
  
  /// Sanitize command input
  String _sanitizeCommand(String command) {
    // Remove null bytes and control characters
    var sanitized = command.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    
    // Remove multiple spaces
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');
    
    // Trim whitespace
    sanitized = sanitized.trim();
    
    return sanitized;
  }
  
  /// Check for dangerous commands
  DangerousCommandCheck _checkDangerousCommands(String command) {
    final lowerCommand = command.toLowerCase();
    
    // Direct dangerous command matches
    for (final dangerousCmd in _dangerousCommands) {
      if (lowerCommand.contains(dangerousCmd.toLowerCase())) {
        return DangerousCommandCheck(
          isSafe: false,
          reason: 'Dangerous command detected: $dangerousCmd',
        );
      }
    }
    
    // Pattern-based dangerous command detection
    final dangerousPatterns = [
      RegExp(r'rm\s+-rf\s+/', caseSensitive: false),
      RegExp(r'dd\s+if=/dev/zero', caseSensitive: false),
      RegExp(r'chmod\s+777', caseSensitive: false),
      RegExp(r'fork\s*\(\s*\)\s*{\s*fork', caseSensitive: false),
      RegExp(r'kill\s+-9\s+-1', caseSensitive: false),
      RegExp(r'shutdown\s+.*now', caseSensitive: false),
      RegExp(r'reboot\s+.*now', caseSensitive: false),
    ];
    
    for (final pattern in dangerousPatterns) {
      if (pattern.hasMatch(command)) {
        return DangerousCommandCheck(
          isSafe: false,
          reason: 'Dangerous command pattern detected',
        );
      }
    }
    
    return DangerousCommandCheck(isSafe: true);
  }
  
  /// Check system directory access
  DangerousCommandCheck _checkSystemDirectoryAccess(String command, String? workingDirectory) {
    // Extract file paths from command
    final pathPattern = RegExp(r'(/[^\s\|"\'<>]+)');
    final matches = pathPattern.allMatches(command);
    
    for (final match in matches) {
      final filePath = match.group(1)!;
      final normalizedPath = path.normalize(filePath);
      
      for (final sysDir in _systemDirectories) {
        if (normalizedPath.startsWith(sysDir) && 
            (command.contains('rm') || command.contains('chmod') || command.contains('chown'))) {
          return DangerousCommandCheck(
            isSafe: false,
            reason: 'Attempted modification of system directory: $sysDir',
          );
        }
      }
    }
    
    return DangerousCommandCheck(isSafe: true);
  }
  
  /// Extract command name
  String _getCommandName(String command) {
    final parts = command.trim().split(' ');
    if (parts.isEmpty) return '';
    
    var cmdName = parts.first;
    
    // Remove path components
    cmdName = path.basenameWithoutExtension(cmdName);
    
    // Remove sudo prefix
    if (cmdName == 'sudo' && parts.length > 1) {
      cmdName = parts[1];
    }
    
    return cmdName;
  }
  
  /// Log command execution
  void _logCommand(String command, CommandValidationType type, String? reason) {
    if (!_auditMode) return;
    
    final entry = CommandAuditEntry(
      command: command,
      type: type,
      reason: reason,
      timestamp: DateTime.now(),
    );
    
    _auditLog.add(entry);
    
    // Maintain audit log size
    if (_auditLog.length > _maxAuditLogSize) {
      _auditLog.removeRange(0, _auditLog.length - _maxAuditLogSize);
    }
  }
  
  /// Add command to whitelist
  void addToWhitelist(String command) {
    _allowedCommands.add(command);
    debugPrint('Added to whitelist: $command');
  }
  
  /// Remove command from whitelist
  void removeFromWhitelist(String command) {
    _allowedCommands.remove(command);
    debugPrint('Removed from whitelist: $command');
  }
  
  /// Add command to blacklist
  void addToBlacklist(String command) {
    _blockedCommands.add(command);
    debugPrint('Added to blacklist: $command');
  }
  
  /// Remove command from blacklist
  void removeFromBlacklist(String command) {
    _blockedCommands.remove(command);
    debugPrint('Removed from blacklist: $command');
  }
  
  /// Enable/disable strict mode
  void setStrictMode(bool enabled) {
    _strictMode = enabled;
    debugPrint('Strict mode ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Enable/disable audit mode
  void setAuditMode(bool enabled) {
    _auditMode = enabled;
    debugPrint('Audit mode ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Get audit log
  List<CommandAuditEntry> getAuditLog() {
    return List.unmodifiable(_auditLog);
  }
  
  /// Get command statistics
  Map<String, dynamic> getStatistics() {
    final allowedCount = _auditLog.where((e) => e.type == CommandValidationType.allowed).length;
    final blockedCount = _auditLog.where((e) => e.type == CommandValidationType.blocked).length;
    
    return {
      'totalCommands': _auditLog.length,
      'allowedCommands': allowedCount,
      'blockedCommands': blockedCount,
      'strictMode': _strictMode,
      'auditMode': _auditMode,
      'whitelistedCommands': _allowedCommands.length,
      'blacklistedCommands': _blockedCommands.length,
    };
  }
  
  /// Clear audit log
  void clearAuditLog() {
    _auditLog.clear();
    debugPrint('Audit log cleared');
  }
  
  /// Export audit log
  Future<void> exportAuditLog(String filePath) async {
    try {
      final file = File(filePath);
      final logData = _auditLog.map((entry) => entry.toJson()).toList();
      
      await file.writeAsString(
        JsonEncoder.withIndent('  ').convert(logData),
      );
      
      debugPrint('Audit log exported to: $filePath');
    } catch (e) {
      debugPrint('Failed to export audit log: $e');
      rethrow;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _eventController.close();
  }
}

/// Command validation result
class CommandValidationResult {
  final bool isAllowed;
  final String? sanitizedCommand;
  final String? reason;
  final CommandSeverity severity;
  
  CommandValidationResult({
    required this.isAllowed,
    this.sanitizedCommand,
    this.reason,
    required this.severity,
  });
}

/// Dangerous command check result
class DangerousCommandCheck {
  final bool isSafe;
  final String? reason;
  
  DangerousCommandCheck({
    required this.isSafe,
    this.reason,
  });
}

/// Command audit entry
class CommandAuditEntry {
  final String command;
  final CommandValidationType type;
  final String? reason;
  final DateTime timestamp;
  
  CommandAuditEntry({
    required this.command,
    required this.type,
    this.reason,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'command': command,
    'type': type.toString(),
    'reason': reason,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Command event
class CommandEvent {
  final CommandEventType type;
  final String command;
  final String? reason;
  final DateTime timestamp;
  
  CommandEvent({
    required this.type,
    required this.command,
    this.reason,
    required this.timestamp,
  });
}

/// Command validation types
enum CommandValidationType {
  allowed,
  blocked,
  error,
}

/// Command event types
enum CommandEventType {
  commandAllowed,
  commandBlocked,
  validationError,
}

/// Command severity levels
enum CommandSeverity {
  low,
  medium,
  high,
  critical,
}