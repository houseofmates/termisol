import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Lazy-loading service registry with health checks and feature flags.
///
/// Reduces main.dart from 35 eager initializations to on-demand service
/// creation. Services that fail to start are flagged but don't crash the app.
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
  void register<T>(String name, FutureOr<T> Function() factory, {
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
      if (_health[dep] == ServiceHealth.failed || _health[dep] == ServiceHealth.disabled) {
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
        _completeAsyncInit(name, result as Future<dynamic>);
        return null;
      }

      entry.instance = result;
      _health[name] = ServiceHealth.healthy;
      debugPrint('✅ $name initialized');
      return result as T;
    } catch (e) {
      _health[name] = ServiceHealth.failed;
      debugPrint('❌ $name failed: $e');
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
      if (_health[dep] == ServiceHealth.failed || _health[dep] == ServiceHealth.disabled) {
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
    } catch (e) {
      _health[name] = ServiceHealth.failed;
      entry._future = null;
      debugPrint('❌ $name failed: $e');
      return null;
    }
  }

  Future<void> _completeAsyncInit(String name, Future<dynamic> future) async {
    try {
      final result = await future.timeout(_services[name]!.timeout);
      _services[name]!.instance = result;
      _health[name] = ServiceHealth.healthy;
      debugPrint('✅ $name async init complete');
    } catch (e) {
      _health[name] = ServiceHealth.failed;
      debugPrint('❌ $name async init failed: $e');
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
        } catch (e) {
          debugPrint('Failed to complete async init for $name: $e');
        }
      }
    }
  }
}

enum ServiceHealth { unknown, disabled, initializing, healthy, failed, dependencyFailed }

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

/// Feature flag definitions for Termisol.
/// Core terminal features are always enabled. Extras are opt-in.
class TermisolFeatures {
  static const String terminalCore = 'terminal_core';
  static const String aiAssistant = 'ai_assistant';
  static const String performanceMonitoring = 'performance_monitoring';
  static const String gpuRenderer = 'gpu_renderer';
  static const String gitIntegration = 'git_integration';
  static const String dockerIntegration = 'docker_integration';
  static const String databaseClient = 'database_client';
  static const String fileManager = 'file_manager';
  static const String sessionSync = 'session_sync';
  static const String sshExtras = 'ssh_extras';
  static const String autoSshKeyManagement = 'auto_ssh_key_management';
  static const String multihopSsh = 'multihop_ssh';
  static const String tunnelManagement = 'tunnel_management';
  static const String sshConnectionPersistence = 'ssh_connection_persistence';
  static const String collaboration = 'collaboration';
  static const String plugins = 'plugins';
  static const String sub16msLatencyOptimizer = 'sub16ms_latency_optimizer';
  static const String adaptiveFramePacer = 'adaptive_frame_pacer';
  static const String productionConfigSystem = 'production_config_system';
  static const String backgroundProcessor = 'background_processor';
  static const String memoryOptimizer = 'memory_optimizer';
  static const String networkResilience = 'network_resilience';
  static const String llmPluginSystem = 'llm_plugin_system';
  static const String gnomeIntegration = 'gnome_integration';
  static const String smartCommandChaining = 'smart_command_chaining';
  static const String semanticSearchEngine = 'semantic_search_engine';
  static const String enhancedAISuggestions = 'enhanced_ai_suggestions';
  static const String conversationalAI = 'conversational_ai';
  static const String automatedWorkflows = 'automated_workflows';
  static const String neuralProcessing = 'neural_processing';
  static const String terminalPaneManager = 'terminal_pane_manager';
  static const String audioAlertService = 'audio_alert_service';
  static const String keyboardMacroReader = 'keyboard_macro_reader';
  static const String syncServices = 'sync_services';
  static const String integratedDebugger = 'integrated_debugger';
  static const String taskRunner = 'task_runner';
  static const String configurableHotkeys = 'configurable_hotkeys';
  static const String smoothAnimations = 'smooth_animations';
  static const String autoBackupSystem = 'auto_backup_system';
  static const String codeIntelligence = 'code_intelligence';
  static const String sessionRecovery = 'session_recovery';
  static const String commandGuard = 'command_guard';
  static const String asciicastRecorder = 'asciicast_recorder';
  static const String advancedTerminalProtocol = 'advanced_terminal_protocol';
  static const String adaptiveCompressionNetwork = 'adaptive_compression_network';

  static List<String> get all => [
    terminalCore, aiAssistant, performanceMonitoring, gpuRenderer,
    gitIntegration, dockerIntegration, databaseClient, fileManager,
    vrSupport, videoPlayback, audioVisualization, model3d,
    sessionSync, sshExtras, autoSshKeyManagement, multihopSsh,
    tunnelManagement, sshConnectionPersistence, collaboration, plugins,
  ];

  static List<String> get critical => [terminalCore, performanceMonitoring];
  static List<String> get heavy => [vrSupport, videoPlayback, audioVisualization, model3d, collaboration];
}
