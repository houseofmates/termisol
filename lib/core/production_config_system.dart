import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Production-ready configuration system with validation, defaults, and runtime updates.
/// Supports hierarchical configuration with environment-specific overrides.
class ProductionConfigSystem {
  static const String configFileName = 'termisol_config.json';
  static const String backupFileName = 'termisol_config.backup.json';

  final StreamController<ConfigChangeEvent> _changeController = StreamController.broadcast();
  final Map<String, dynamic> _config = {};
  final Map<String, dynamic> _defaults = {};
  final Map<String, ConfigValidator> _validators = {};

  SharedPreferences? _prefs;
  File? _configFile;
  bool _initialized = false;
  bool _autoSave = true;
  DateTime? _lastSaveTime;
  int _saveAttempts = 0;

  /// Stream of configuration changes
  Stream<ConfigChangeEvent> get changes => _changeController.stream;

  /// Whether the system is initialized
  bool get initialized => _initialized;

  /// Whether auto-save is enabled
  bool get autoSave => _autoSave;

  ProductionConfigSystem() {
    _setupDefaults();
    _setupValidators();
  }

  void _setupDefaults() {
    _defaults.addAll({
      // Performance settings
      'performance': {
        'gpu_acceleration': true,
        'adaptive_frame_pacing': true,
        'target_fps': 60,
        'max_memory_mb': 512,
        'performance_monitoring': true,
      },

      // UI settings
      'ui': {
        'theme': 'dark',
        'font_family': 'Fira Code',
        'font_size': 14,
        'tab_position': 'top',
        'show_minimap': false,
        'animations_enabled': true,
      },

      // Terminal settings
      'terminal': {
        'shell': Platform.isWindows ? 'cmd.exe' : 'bash',
        'working_directory': null,
        'scrollback_lines': 10000,
        'enable_bracketed_paste': true,
        'enable_mouse_support': true,
        'true_color_support': true,
      },

      // AI settings
      'ai': {
        'enabled': true,
        'model': 'nvidia-ai',
        'max_tokens': 4096,
        'temperature': 0.7,
        'context_window': 8192,
      },

      // Network settings
      'network': {
        'connection_timeout': 30,
        'max_retries': 3,
        'compression_enabled': true,
        'proxy_url': null,
      },

      // Security settings
      'security': {
        'enable_ssh_key_management': true,
        'auto_lock_timeout': 30,
        'encrypt_sensitive_data': true,
        'allow_remote_connections': false,
      },

      // Device-specific settings
      'device': {
        'platform': defaultTargetPlatform.name,
        'is_mobile': defaultTargetPlatform == TargetPlatform.android ||
                     defaultTargetPlatform == TargetPlatform.iOS,
        'is_desktop': defaultTargetPlatform == TargetPlatform.linux ||
                      defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.macOS,
        'is_vr': false, // Will be set by VR detection
      },

      // Feature flags
      'features': {
        'vr_support': false,
        'ai_assistant': true,
        'session_sync': false,
        'plugins': true,
        'docker_integration': false,
        'git_integration': true,
      },
    });
  }

  void _setupValidators() {
    _validators['performance.target_fps'] = (value) {
      final fps = value as num?;
      if (fps == null || fps < 30 || fps > 120) {
        throw ConfigValidationError('FPS must be between 30 and 120');
      }
    };

    _validators['performance.max_memory_mb'] = (value) {
      final memory = value as num?;
      if (memory == null || memory < 64 || memory > 4096) {
        throw ConfigValidationError('Memory limit must be between 64MB and 4GB');
      }
    };

    _validators['terminal.scrollback_lines'] = (value) {
      final lines = value as num?;
      if (lines == null || lines < 100 || lines > 100000) {
        throw ConfigValidationError('Scrollback lines must be between 100 and 100,000');
      }
    };

    _validators['ai.max_tokens'] = (value) {
      final tokens = value as num?;
      if (tokens == null || tokens < 128 || tokens > 32768) {
        throw ConfigValidationError('Max tokens must be between 128 and 32,768');
      }
    };
  }

  /// Initialize the configuration system
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      final configDir = await getApplicationDocumentsDirectory();
      _configFile = File('${configDir.path}/$configFileName');

      // Load configuration
      await _loadConfiguration();

      _initialized = true;
      debugPrint('ProductionConfigSystem initialized');
    } catch (e) {
      debugPrint('Failed to initialize config system: $e');
      // Continue with defaults
      _config.addAll(Map.from(_defaults));
      _initialized = true;
    }
  }

  Future<void> _loadConfiguration() async {
    // Start with defaults
    _config.addAll(Map.from(_defaults));

    // Load from file if exists
    if (_configFile != null && await _configFile!.exists()) {
      try {
        final content = await _configFile!.readAsString();
        final loadedConfig = jsonDecode(content) as Map<String, dynamic>;

        // Deep merge loaded config with defaults
        _deepMerge(_config, loadedConfig);
        debugPrint('Configuration loaded from file');
      } catch (e) {
        debugPrint('Failed to load config file: $e');
        // Try backup
        await _loadBackupConfiguration();
      }
    }

    // Apply platform-specific overrides
    _applyPlatformOverrides();
  }

  Future<void> _loadBackupConfiguration() async {
    if (_configFile == null) return;

    final backupFile = File('${_configFile!.parent.path}/$backupFileName');
    if (await backupFile.exists()) {
      try {
        final content = await backupFile.readAsString();
        final backupConfig = jsonDecode(content) as Map<String, dynamic>;
        _deepMerge(_config, backupConfig);
        debugPrint('Configuration loaded from backup');
      } catch (e) {
        debugPrint('Failed to load backup config: $e');
      }
    }
  }

  void _applyPlatformOverrides() {
    // Ubuntu optimizations
    if (Platform.isLinux) {
      _config['performance'] ??= {};
      _config['performance']['gpu_acceleration'] = true;
      _config['performance']['target_fps'] = 60;
      _config['performance']['max_memory_mb'] = 1024;
    }

    // Android optimizations
    else if (Platform.isAndroid) {
      _config['performance'] ??= {};
      _config['performance']['gpu_acceleration'] = true;
      _config['performance']['target_fps'] = 60;
      _config['performance']['max_memory_mb'] = 256;
      _config['performance']['adaptive_frame_pacing'] = true;
    }

    // Oculus Quest 2 optimizations
    else if (_isVrPlatform()) {
      _config['performance'] ??= {};
      _config['performance']['gpu_acceleration'] = true;
      _config['performance']['target_fps'] = 72;
      _config['performance']['max_memory_mb'] = 512;
      _config['device'] ??= {};
      _config['device']['is_vr'] = true;
      _config['features'] ??= {};
      _config['features']['vr_support'] = true;
    }

    // Windows optimizations
    else if (Platform.isWindows) {
      _config['performance'] ??= {};
      _config['performance']['gpu_acceleration'] = true;
      _config['performance']['target_fps'] = 60;
      _config['performance']['max_memory_mb'] = 1024;
    }
  }

  bool _isVrPlatform() {
    // Simple VR detection - in real implementation, this would check for VR headset
    return false; // Placeholder
  }

  void _deepMerge(Map<String, dynamic> target, Map<String, dynamic> source) {
    for (final entry in source.entries) {
      if (target[entry.key] is Map && entry.value is Map) {
        _deepMerge(target[entry.key] as Map<String, dynamic>, entry.value as Map<String, dynamic>);
      } else {
        target[entry.key] = entry.value;
      }
    }
  }

  /// Get a configuration value
  T? get<T>(String key, [T? defaultValue]) {
    final keys = key.split('.');
    dynamic current = _config;

    for (final k in keys) {
      if (current is Map && current.containsKey(k)) {
        current = current[k];
      } else {
        return defaultValue ?? _getDefault<T>(key);
      }
    }

    return current as T?;
  }

  T? _getDefault<T>(String key) {
    final keys = key.split('.');
    dynamic current = _defaults;

    for (final k in keys) {
      if (current is Map && current.containsKey(k)) {
        current = current[k];
      } else {
        return null;
      }
    }

    return current as T?;
  }

  /// Set a configuration value
  Future<void> set(String key, dynamic value) async {
    final oldValue = get(key);

    // Validate if validator exists
    final validator = _validators[key];
    if (validator != null) {
      validator(value);
    }

    // Set the value
    final keys = key.split('.');
    _setNestedValue(_config, keys, value);

    // Emit change event
    _changeController.add(ConfigChangeEvent(
      key: key,
      oldValue: oldValue,
      newValue: value,
      timestamp: DateTime.now(),
    ));

    // Auto-save if enabled
    if (_autoSave) {
      await save();
    }

    debugPrint('Config updated: $key = $value');
  }

  void _setNestedValue(Map<String, dynamic> map, List<String> keys, dynamic value) {
    if (keys.length == 1) {
      map[keys[0]] = value;
      return;
    }

    final key = keys[0];
    final remaining = keys.sublist(1);

    if (!map.containsKey(key) || !(map[key] is Map)) {
      map[key] = <String, dynamic>{};
    }

    _setNestedValue(map[key] as Map<String, dynamic>, remaining, value);
  }

  /// Save configuration to persistent storage
  Future<void> save() async {
    if (_configFile == null) return;

    try {
      _saveAttempts++;

      // Create backup of current config
      if (await _configFile!.exists()) {
        final backupFile = File('${_configFile!.parent.path}/$backupFileName');
        await _configFile!.copy(backupFile.path);
      }

      // Save new config
      final jsonString = JsonEncoder.withIndent('  ').convert(_config);
      await _configFile!.writeAsString(jsonString);

      _lastSaveTime = DateTime.now();
      debugPrint('Configuration saved successfully');

    } catch (e) {
      debugPrint('Failed to save configuration: $e');
      // Could implement retry logic here
    }
  }

  /// Reset configuration to defaults
  Future<void> reset() async {
    _config.clear();
    _config.addAll(Map.from(_defaults));
    _applyPlatformOverrides();

    // Emit reset event
    _changeController.add(ConfigChangeEvent(
      key: '*',
      oldValue: null,
      newValue: null,
      timestamp: DateTime.now(),
      isReset: true,
    ));

    if (_autoSave) {
      await save();
    }

    debugPrint('Configuration reset to defaults');
  }

  /// Export configuration for backup/sharing
  Future<String> export() async {
    return JsonEncoder.withIndent('  ').convert(_config);
  }

  /// Import configuration from string
  Future<void> import(String configJson) async {
    try {
      final imported = jsonDecode(configJson) as Map<String, dynamic>;

      // Validate imported config
      _validateImportedConfig(imported);

      // Apply imported config
      _config.clear();
      _config.addAll(Map.from(_defaults));
      _deepMerge(_config, imported);
      _applyPlatformOverrides();

      // Emit import event
      _changeController.add(ConfigChangeEvent(
        key: '*',
        oldValue: null,
        newValue: null,
        timestamp: DateTime.now(),
        isImport: true,
      ));

      if (_autoSave) {
        await save();
      }

      debugPrint('Configuration imported successfully');

    } catch (e) {
      throw ConfigImportError('Failed to import configuration: $e');
    }
  }

  void _validateImportedConfig(Map<String, dynamic> config) {
    // Basic validation - could be more comprehensive
    final requiredSections = ['performance', 'ui', 'terminal'];
    for (final section in requiredSections) {
      if (!config.containsKey(section)) {
        throw ConfigValidationError('Missing required section: $section');
      }
    }
  }

  /// Enable or disable auto-save
  void setAutoSave(bool enabled) {
    _autoSave = enabled;
    debugPrint('Auto-save ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Get configuration info for debugging
  Map<String, dynamic> getConfigInfo() {
    return {
      'initialized': _initialized,
      'autoSave': _autoSave,
      'lastSaveTime': _lastSaveTime?.toIso8601String(),
      'saveAttempts': _saveAttempts,
      'configKeys': _config.keys.length,
      'validatorCount': _validators.length,
    };
  }

  /// Dispose resources
  void dispose() {
    _changeController.close();
    debugPrint('ProductionConfigSystem disposed');
  }
}

/// Configuration change event
class ConfigChangeEvent {
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime timestamp;
  final bool isReset;
  final bool isImport;

  const ConfigChangeEvent({
    required this.key,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
    this.isReset = false,
    this.isImport = false,
  });

  bool get isGlobalChange => key == '*' || isReset || isImport;
}

/// Configuration validator function type
typedef ConfigValidator = void Function(dynamic value);

/// Configuration validation error
class ConfigValidationError implements Exception {
  final String message;
  const ConfigValidationError(this.message);
  @override
  String toString() => 'ConfigValidationError: $message';
}

/// Configuration import error
class ConfigImportError implements Exception {
  final String message;
  const ConfigImportError(this.message);
  @override
  String toString() => 'ConfigImportError: $message';
}