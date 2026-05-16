import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// lazy-loading service registry with health checks and feature flags.
///
/// reduces main.dart from 35 eager initializations to on-demand service
/// creation. services that fail to start are flagged but don't crash the app.
class ServiceRegistry {
  static ServiceRegistry? _instance;
  static ServiceRegistry get instance {
    _instance ??= ServiceRegistry._();
    return _instance!;
  }

  ServiceRegistry._();

  final Map<String, _ServiceEntry> _services = {};
  final Map<String, bool> _featureFlags = {};
  final Map<String, ServiceHealth> _health = {};
  final Queue<String> _initQueue = Queue();

  /// Register a service factory without creating it yet.
  void register<T>(
    String name,
    FutureOr<T> Function() factory, {
    bool enabled = true,
    List<String> dependsOn = const [],
    Duration timeout = const Duration(seconds: 10),
  }) {
    _services[name] = _ServiceEntry<T>(
      name: name,
      factory: factory,
      enabled: enabled,
      dependsOn: dependsOn,
      timeout: timeout,
    );
    _featureFlags[name] = enabled;
    _health[name] = ServiceHealth.unknown;
  }

  /// Get a service, creating it on first access if enabled.
  /// Returns null if disabled or failed.
  T? get<T>(String name) {
    final entry = _services[name];
    if (entry == null) return null;
    if (!_featureFlags[name]!) {
      _health[name] = ServiceHealth.disabled;
      return null;
    }

    if (entry.instance != null) return entry.instance as T;

    // Check dependencies first
    for (final dep in entry.dependsOn) {
      if (_health[dep] == ServiceHealth.failed ||
          _health[dep] == ServiceHealth.disabled) {
        _health[name] = ServiceHealth.dependencyFailed;
        debugPrint('⚠️ $name skipped: dependency $dep unavailable');
        return null;
      }
    }

    try {
      _health[name] = ServiceHealth.initializing;
      final result = entry.factory();

      if (result is Future) {
        // Async initialization - return null for now, queue for completion
        _initQueue.add(name);
        _completeAsyncInit(name, result);
        return null;
      }

      entry.instance = result;
      _health[name] = ServiceHealth.healthy;
      debugPrint('✅ $name initialized');
      return result as T;
    } catch (e, stack) {
      _health[name] = ServiceHealth.failed;
      debugPrint('service $name failed: $e\n$stack');
      return null;
    }
  }

  /// Async version for services that must be awaited.
  Future<T?> getAsync<T>(String name) async {
    final entry = _services[name];
    if (entry == null) return null;
    if (!_featureFlags[name]!) return null;

    if (entry.instance != null) return entry.instance as T;
    if (entry._future != null) return await entry._future as T?;

    for (final dep in entry.dependsOn) {
      if (_health[dep] == ServiceHealth.failed ||
          _health[dep] == ServiceHealth.disabled) {
        _health[name] = ServiceHealth.dependencyFailed;
        return null;
      }
    }

    try {
      _health[name] = ServiceHealth.initializing;
      final future = Future<dynamic>.sync(entry.factory).timeout(entry.timeout);
      entry._future = future;
      final result = await future;
      entry.instance = result;
      entry._future = null;
      _health[name] = ServiceHealth.healthy;
      debugPrint('✅ $name initialized (async)');
      return result as T;
    } catch (e, stack) {
      _health[name] = ServiceHealth.failed;
      entry._future = null;
      debugPrint('service $name async failed: $e\n$stack');
      return null;
    }
  }

  Future<void> _completeAsyncInit(String name, Future<dynamic> future) async {
    try {
      final result = await future.timeout(_services[name]!.timeout);
      _services[name]!.instance = result;
      _health[name] = ServiceHealth.healthy;
      debugPrint('✅ $name async init complete');
    } catch (e, stack) {
      _health[name] = ServiceHealth.failed;
      debugPrint('service $name async init failed: $e\n$stack');
    }
  }

  /// Enable or disable a feature at runtime.
  void setFeature(String name, bool enabled) {
    _featureFlags[name] = enabled;
    if (!enabled) {
      // Dispose if it was created
      _services[name]?.instance = null;
      _health[name] = ServiceHealth.disabled;
    }
  }

  bool isEnabled(String name) => _featureFlags[name] ?? false;
  bool isHealthy(String name) => _health[name] == ServiceHealth.healthy;
  ServiceHealth? health(String name) => _health[name];

  /// Health report for all services.
  Map<String, dynamic> healthReport() {
    return {
      for (final entry in _services.entries)
        entry.key: {
          'enabled': _featureFlags[entry.key],
          'health': _health[entry.key]?.name,
          'initialized': entry.value.instance != null,
        },
    };
  }

  /// Initialize only critical services eagerly. Everything else is lazy.
  Future<void> initializeCritical() async {
    // Nothing is truly critical except the terminal itself.
    // All other services can fail gracefully.
    debugPrint('🚀 ServiceRegistry: critical path empty (lazy by design)');
  }

  /// Get AI Assistant service specifically
  dynamic getAIAssistant() => get<dynamic>(TermisolFeatures.aiAssistant);

  /// Wait for any queued async initializations to complete.
  Future<void> flushAsyncQueue() async {
    while (_initQueue.isNotEmpty) {
      final name = _initQueue.removeFirst();
      final entry = _services[name];
      if (entry?._future != null) {
        try {
          await entry!._future;
        } catch (e, stack) {
          debugPrint('failed to complete async init for $name: $e\n$stack');
        }
      }
    }
  }
}

enum ServiceHealth {
  unknown,
  disabled,
  initializing,
  healthy,
  failed,
  dependencyFailed,
}

class _ServiceEntry<T> {
  final String name;
  final FutureOr<T> Function() factory;
  final bool enabled;
  final List<String> dependsOn;
  final Duration timeout;
  dynamic instance;
  Future<dynamic>? _future;

  _ServiceEntry({
    required this.name,
    required this.factory,
    required this.enabled,
    required this.dependsOn,
    required this.timeout,
  });
}

/// feature flag definitions for termisol.
/// only features that are actually implemented and used.
class TermisolFeatures {
  static const String terminalCore = 'terminal_core';
  static const String aiAssistant = 'ai_assistant';
  static const String productionConfigSystem = 'production_config_system';
  static const String fileManager = 'file_manager';

  static List<String> get all => [
    terminalCore,
    aiAssistant,
    productionConfigSystem,
    fileManager,
  ];

  static List<String> get critical => [terminalCore];
}
