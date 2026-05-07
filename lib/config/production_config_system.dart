import 'dart:async';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Production Configuration System - Alacritty-inspired with PKM aesthetic
/// 
/// Features:
/// - YAML configuration with validation and error recovery
/// - Hot-reloading with file watching
/// - Hierarchical defaults with inheritance
/// - Performance-first settings
/// - Cross-platform portability
/// - Automatic config fixing for syntax errors
class ProductionConfigSystem {
  static const String _configFileName = 'termisol.yaml';
  static const String _configDirName = '.termisol';
  static const String _backupSuffix = '.backup';
  static const String _corruptSuffix = '.corrupt';
  
  late final File _configFile;
  late final StreamSubscription _configWatcher;
  
  TermisolConfig _config = TermisolConfig.defaultConfig();
  final _configController = StreamController<TermisolConfig>.broadcast();
  
  bool _isLoaded = false;
  bool _hotReloadEnabled = true;
  bool _hasErrors = false;
  String? _lastError;
  
  // Configuration sections
  PerformanceConfig get performance => _config.performance;
  ThemeConfig get theme => _config.theme;
  TerminalConfig get terminal => _config.terminal;
  KeybindingConfig get keybindings => _config.keybindings;
  AdvancedConfig get advanced => _config.advanced;
  
  // Event streams
  Stream<TermisolConfig> get configChanges => _configController.stream;
  bool get isLoaded => _isLoaded;
  bool get hotReloadEnabled => _hotReloadEnabled;
  bool get hasErrors => _hasErrors;
  String? get lastError => _lastError;
  
  ProductionConfigSystem._();
  
  /// Initialize production configuration system
  static Future<ProductionConfigSystem> initialize() async {
    final config = ProductionConfigSystem._();
    await config._loadConfiguration();
    await config._setupHotReload();
    return config;
  }
  
  /// Load configuration with full validation and error recovery
  Future<void> _loadConfiguration() async {
    try {
      await _ensureConfigDirectory();
      _configFile = await _getConfigFile();
      
      if (await _configFile.exists()) {
        await _loadAndValidateConfig();
      } else {
        await _saveDefaultConfiguration();
        debugPrint('✅ Default configuration created');
      }
      
      _isLoaded = true;
      
    } catch (e) {
      debugPrint('⚠️ Configuration load failed: $e - using defaults');
      await _handleConfigLoadFailure(e);
      _config = TermisolConfig.defaultConfig();
      _isLoaded = true;
    }
  }
  
  /// Load and validate configuration with automatic fixing
  Future<void> _loadAndValidateConfig() async {
    try {
      final content = await _configFile.readAsString();
      
      // Check for empty file
      if (content.trim().isEmpty) {
        debugPrint('⚠️ Configuration file is empty, recreating...');
        await _backupAndRecreateConfig('empty_file');
        return;
      }
      
      // Try to parse YAML
      YamlMap? yaml;
      try {
        yaml = loadYaml(content) as YamlMap?;
      } catch (e) {
        debugPrint('❌ YAML parsing failed: $e');
        await _attemptYamlRepair(content, e);
        return;
      }
      
      if (yaml == null) {
        debugPrint('⚠️ YAML parsed to null, recreating config...');
        await _backupAndRecreateConfig('null_yaml');
        return;
      }
      
      // Try to create config from YAML
      try {
        _config = TermisolConfig.fromYaml(yaml);
        await _validateConfiguration();
        debugPrint('✅ Configuration loaded from ${_configFile.path}');
      } catch (e) {
        debugPrint('❌ Config creation failed: $e');
        await _attemptConfigRepair(yaml, e);
      }
      
    } catch (e) {
      debugPrint('❌ Config file read failed: $e');
      await _backupAndRecreateConfig('read_error');
    }
  }
  
  /// Attempt to repair YAML syntax errors
  Future<void> _attemptYamlRepair(String content, dynamic error) async {
    debugPrint('🔧 Attempting YAML repair...');
    
    String repairedContent = content;
    
    // Common YAML fixes
    repairedContent = _fixYamlIndentation(repairedContent);
    repairedContent = _fixYamlQuotes(repairedContent);
    repairedContent = _fixYamlColons(repairedContent);
    repairedContent = _fixYamlLists(repairedContent);
    
    try {
      final yaml = loadYaml(repairedContent) as YamlMap?;
      if (yaml != null) {
        _config = TermisolConfig.fromYaml(yaml);
        await _validateConfiguration();
        await _saveRepairedConfig(repairedContent, 'yaml_repair');
        debugPrint('✅ YAML repair successful');
      }
    } catch (e) {
      debugPrint('❌ YAML repair failed: $e');
      await _backupAndRecreateConfig('yaml_repair_failed');
    }
  }
  
  /// Attempt to repair configuration structure errors
  Future<void> _attemptConfigRepair(YamlMap yaml, dynamic error) async {
    debugPrint('🔧 Attempting config repair...');
    
    try {
      // Create a repaired YAML map by merging with defaults
      final defaultYaml = loadYaml(_config.toYaml()) as YamlMap;
      final repairedYaml = _mergeYamlMaps(defaultYaml, yaml);
      
      _config = TermisolConfig.fromYaml(repairedYaml);
      await _validateConfiguration();
      await _saveRepairedConfig(_yamlMapToString(repairedYaml), 'config_repair');
      debugPrint('✅ Config repair successful');
      
    } catch (e) {
      debugPrint('❌ Config repair failed: $e');
      await _backupAndRecreateConfig('config_repair_failed');
    }
  }
  
  /// Backup current config and recreate with defaults
  Future<void> _backupAndRecreateConfig(String reason) async {
    try {
      // Backup current file
      if (await _configFile.exists()) {
        final backupFile = File('${_configFile.path}.$reason$_corruptSuffix');
        await _configFile.copy(backupFile.path);
        debugPrint('📋 Corrupt config backed up to ${backupFile.path}');
      }
      
      // Create new default config
      _config = TermisolConfig.defaultConfig();
      await _saveDefaultConfiguration();
      debugPrint('✅ New default configuration created');
      
    } catch (e) {
      debugPrint('❌ Backup and recreate failed: $e');
      rethrow;
    }
  }
  
  /// Save repaired configuration
  Future<void> _saveRepairedConfig(String content, String repairType) async {
    try {
      // Create backup
      final backupFile = File('${_configFile.path}.$repairType$_backupSuffix');
      await _configFile.copy(backupFile.path);
      
      // Save repaired content
      await _configFile.writeAsString(content);
      debugPrint('✅ Repaired configuration saved');
      
    } catch (e) {
      debugPrint('❌ Failed to save repaired config: $e');
    }
  }
  
  /// Handle critical config load failure
  Future<void> _handleConfigLoadFailure(dynamic error) async {
    _hasErrors = true;
    _lastError = error.toString();
    
    // Try to create a minimal working config
    try {
      await _ensureConfigDirectory();
      _configFile = await _getConfigFile();
      
      if (!await _configFile.exists()) {
        _config = TermisolConfig.defaultConfig();
        await _saveDefaultConfiguration();
        debugPrint('✅ Emergency default configuration created');
      }
    } catch (e) {
      debugPrint('❌ Emergency config creation failed: $e');
    }
  }
  
  /// Setup hot-reloading with file watching
  Future<void> _setupHotReload() async {
    if (!_hotReloadEnabled) return;
    
    try {
      _configWatcher = _configFile.watch().listen((event) {
        if (event.type == FileSystemEvent.modify) {
          debugPrint('🔄 Configuration file changed, reloading...');
          _reloadConfiguration();
        }
      });
      debugPrint('🔄 Hot-reload enabled for configuration');
    } catch (e) {
      debugPrint('⚠️ Failed to setup hot-reload: $e');
      _hotReloadEnabled = false;
    }
  }
  
  /// Reload configuration from file
  Future<void> _reloadConfiguration() async {
    try {
      if (!await _configFile.exists()) return;
      
      final content = await _configFile.readAsString();
      final yaml = loadYaml(content);
      final newConfig = TermisolConfig.fromYaml(yaml);
      
      await _validateConfiguration(newConfig);
      
      final oldConfig = _config;
      _config = newConfig;
      
      // Notify listeners of changes
      _configController.add(_config);
      
      debugPrint('✅ Configuration reloaded successfully');
      
      // Log significant changes
      _logConfigurationChanges(oldConfig, newConfig);
      
    } catch (e) {
      debugPrint('❌ Configuration reload failed: $e');
    }
  }
  
  /// Ensure configuration directory exists
  Future<void> _ensureConfigDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final configDir = Directory('${appDir.path}/$_configDirName');
    
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
  }
  
  /// Get configuration file path
  Future<File> _getConfigFile() async {
    final appDir = await getApplicationSupportDirectory();
    return File('${appDir.path}/$_configDirName/$_configFileName');
  }
  
  /// Save default configuration
  Future<void> _saveDefaultConfiguration() async {
    final defaultYaml = _config.toYaml();
    await _configFile.writeAsString(defaultYaml);
  }
  
  /// Validate configuration comprehensively
  Future<void> _validateConfiguration([TermisolConfig? config]) async {
    final cfg = config ?? _config;
    
    // Validate performance settings
    await _validatePerformanceConfig(cfg.performance);
    
    // Validate theme settings
    await _validateThemeConfig(cfg.theme);
    
    // Validate terminal settings
    await _validateTerminalConfig(cfg.terminal);
    
    // Validate keybindings
    await _validateKeybindingConfig(cfg.keybindings);
    
    // Validate advanced settings
    await _validateAdvancedConfig(cfg.advanced);
  }
  
  /// Validate performance configuration
  Future<void> _validatePerformanceConfig(PerformanceConfig config) async {
    if (config.targetFps <= 0 || config.targetFps > 240) {
      throw Exception('Invalid target FPS: ${config.targetFps}. Must be 1-240');
    }
    
    if (config.textureAtlasSize < 1024 || config.textureAtlasSize > 8192) {
      throw Exception('Invalid texture atlas size: ${config.textureAtlasSize}. Must be 1024-8192');
    }
    
    if (config.glyphCacheSize < 128 || config.glyphCacheSize > 2048) {
      throw Exception('Invalid glyph cache size: ${config.glyphCacheSize}. Must be 128-2048');
    }
  }
  
  /// Validate theme configuration
  Future<void> _validateThemeConfig(ThemeConfig config) async {
    final colors = [
      config.background,
      config.foreground,
      config.cursor,
      config.selection,
    ];
    
    for (final color in colors) {
      if (!_isValidColor(color)) {
        throw Exception('Invalid color format: $color');
      }
    }
    
    // Validate font size
    if (config.fontSize <= 4 || config.fontSize > 72) {
      throw Exception('Invalid font size: ${config.fontSize}. Must be 4-72');
    }
  }
  
  /// Validate terminal configuration
  Future<void> _validateTerminalConfig(TerminalConfig config) async {
    // Validate shell program exists
    if (config.shellProgram.isNotEmpty) {
      final shellFile = File(config.shellProgram);
      if (!await shellFile.exists()) {
        debugPrint('⚠️ Shell program not found: ${config.shellProgram}');
      }
    }
    
    // Validate PTY buffer size
    if (config.ptyBufferSize < 4096 || config.ptyBufferSize > 1048576) {
      throw Exception('Invalid PTY buffer size: ${config.ptyBufferSize}. Must be 4096-1048576');
    }
  }
  
  /// Validate keybinding configuration
  Future<void> _validateKeybindingConfig(KeybindingConfig config) async {
    // Check for duplicate keybindings
    final usedKeys = <String>{};
    for (final binding in config.bindings) {
      final key = '${binding.key}-${binding.mods}';
      if (usedKeys.contains(key)) {
        throw Exception('Duplicate keybinding: $key');
      }
      usedKeys.add(key);
    }
  }
  
  /// Validate advanced configuration
  Future<void> _validateAdvancedConfig(AdvancedConfig config) async {
    if (config.maxLogFileSize < 1024 || config.maxLogFileSize > 104857600) {
      throw Exception('Invalid max log file size: ${config.maxLogFileSize}. Must be 1024-104857600');
    }
  }
  
  /// Check if color string is valid
  bool _isValidColor(String color) {
    try {
      if (color.startsWith('#')) {
        Color(int.parse(color.substring(1), radix: 16));
      } else if (color.startsWith('0x')) {
        Color(int.parse(color.substring(2), radix: 16));
      } else {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Log significant configuration changes
  void _logConfigurationChanges(TermisolConfig oldConfig, TermisolConfig newConfig) {
    final changes = <String>[];
    
    if (oldConfig.performance.targetFps != newConfig.performance.targetFps) {
      changes.add('Target FPS: ${oldConfig.performance.targetFps} → ${newConfig.performance.targetFps}');
    }
    
    if (oldConfig.theme.fontSize != newConfig.theme.fontSize) {
      changes.add('Font size: ${oldConfig.theme.fontSize} → ${newConfig.theme.fontSize}');
    }
    
    if (oldConfig.terminal.shellProgram != newConfig.terminal.shellProgram) {
      changes.add('Shell: ${oldConfig.terminal.shellProgram} → ${newConfig.terminal.shellProgram}');
    }
    
    if (changes.isNotEmpty) {
      debugPrint('📝 Configuration changes: ${changes.join(', ')}');
    }
  }
  
  /// Update configuration programmatically
  Future<void> updateConfiguration(TermisolConfig newConfig) async {
    await _validateConfiguration(newConfig);
    
    final oldConfig = _config;
    _config = newConfig;
    
    await _saveConfiguration();
    _configController.add(_config);
    
    _logConfigurationChanges(oldConfig, newConfig);
  }
  
  /// Save current configuration
  Future<void> _saveConfiguration() async {
    try {
      final yaml = _config.toYaml();
      await _configFile.writeAsString(yaml);
      debugPrint('✅ Configuration saved');
    } catch (e) {
      debugPrint('❌ Configuration save failed: $e');
      rethrow;
    }
  }
  
  /// Get configuration as YAML string
  String getConfigYaml() => _config.toYaml();
  
  /// Reset to default configuration
  Future<void> resetToDefaults() async {
    _config = TermisolConfig.defaultConfig();
    await _saveConfiguration();
    _configController.add(_config);
    debugPrint('✅ Configuration reset to defaults');
  }
  
  /// Enable/disable hot reload
  void setHotReload(bool enabled) {
    if (enabled == _hotReloadEnabled) return;
    
    _hotReloadEnabled = enabled;
    
    if (enabled) {
      _setupHotReload();
    } else {
      _configWatcher.cancel();
    }
    
    debugPrint('🔄 Hot reload ${enabled ? "enabled" : "disabled"}');
  }
  
  /// Get performance-optimized configuration
  TermisolConfig getPerformanceOptimized() {
    return TermisolConfig(
      performance: PerformanceConfig(
        targetFps: 120,
        hardwareAcceleration: true,
        vsync: false,
        maxDrawCalls: 2,
        textureAtlasSize: 4096,
        glyphCacheSize: 1024,
        enableProfiling: false,
      ),
      theme: _config.theme,
      terminal: _config.terminal,
      keybindings: _config.keybindings,
      advanced: _config.advanced,
    );
  }
  
  /// Get battery-optimized configuration
  TermisolConfig getBatteryOptimized() {
    return TermisolConfig(
      performance: PerformanceConfig(
        targetFps: 30,
        hardwareAcceleration: true,
        vsync: true,
        maxDrawCalls: 1,
        textureAtlasSize: 2048,
        glyphCacheSize: 256,
        enableProfiling: false,
      ),
      theme: _config.theme,
      terminal: _config.terminal,
      keybindings: _config.keybindings,
      advanced: _config.advanced,
    );
  }
  
  /// Dispose resources
  void dispose() {
    _configWatcher.cancel();
    _configController.close();
    debugPrint('🗑️ Production configuration system disposed');
  }
}

// Configuration data classes

class TermisolConfig {
  final PerformanceConfig performance;
  final ThemeConfig theme;
  final TerminalConfig terminal;
  final KeybindingConfig keybindings;
  final AdvancedConfig advanced;
  
  const TermisolConfig({
    required this.performance,
    required this.theme,
    required this.terminal,
    required this.keybindings,
    required this.advanced,
  });
  
  factory TermisolConfig.defaultConfig() {
    return TermisolConfig(
      performance: PerformanceConfig.defaultConfig(),
      theme: ThemeConfig.defaultConfig(),
      terminal: TerminalConfig.defaultConfig(),
      keybindings: KeybindingConfig.defaultConfig(),
      advanced: AdvancedConfig.defaultConfig(),
    );
  }
  
  factory TermisolConfig.fromYaml(YamlMap yaml) {
    return TermisolConfig(
      performance: PerformanceConfig.fromYaml(yaml['performance'] ?? YamlMap()),
      theme: ThemeConfig.fromYaml(yaml['theme'] ?? YamlMap()),
      terminal: TerminalConfig.fromYaml(yaml['terminal'] ?? YamlMap()),
      keybindings: KeybindingConfig.fromYaml(yaml['keybindings'] ?? YamlMap()),
      advanced: AdvancedConfig.fromYaml(yaml['advanced'] ?? YamlMap()),
    );
  }
  
  String toYaml() {
    final buffer = StringBuffer();
    buffer.writeln('# termisol configuration');
    buffer.writeln('# Performance-focused terminal emulator with PKM aesthetic');
    buffer.writeln();
    
    buffer.writeln('performance:');
    buffer.writeln(performance.toYaml(indent: 2));
    buffer.writeln();
    
    buffer.writeln('theme:');
    buffer.writeln(theme.toYaml(indent: 2));
    buffer.writeln();
    
    buffer.writeln('terminal:');
    buffer.writeln(terminal.toYaml(indent: 2));
    buffer.writeln();
    
    buffer.writeln('keybindings:');
    buffer.writeln(keybindings.toYaml(indent: 2));
    buffer.writeln();
    
    buffer.writeln('advanced:');
    buffer.writeln(advanced.toYaml(indent: 2));
    
    return buffer.toString();
  }
}

class PerformanceConfig {
  final int targetFps;
  final bool hardwareAcceleration;
  final bool vsync;
  final int maxDrawCalls;
  final int textureAtlasSize;
  final int glyphCacheSize;
  final bool enableProfiling;
  
  const PerformanceConfig({
    required this.targetFps,
    required this.hardwareAcceleration,
    required this.vsync,
    required this.maxDrawCalls,
    required this.textureAtlasSize,
    required this.glyphCacheSize,
    required this.enableProfiling,
  });
  
  factory PerformanceConfig.defaultConfig() {
    return const PerformanceConfig(
      targetFps: 120,
      hardwareAcceleration: true,
      vsync: true,
      maxDrawCalls: 2,
      textureAtlasSize: 4096,
      glyphCacheSize: 1024,
      enableProfiling: false,
    );
  }
  
  factory PerformanceConfig.fromYaml(YamlMap yaml) {
    return PerformanceConfig(
      targetFps: yaml['target_fps'] ?? 120,
      hardwareAcceleration: yaml['hardware_acceleration'] ?? true,
      vsync: yaml['vsync'] ?? true,
      maxDrawCalls: yaml['max_draw_calls'] ?? 2,
      textureAtlasSize: yaml['texture_atlas_size'] ?? 4096,
      glyphCacheSize: yaml['glyph_cache_size'] ?? 1024,
      enableProfiling: yaml['enable_profiling'] ?? false,
    );
  }
  
  String toYaml({int indent = 0}) {
    final spaces = '  ' * indent;
    return '''
${spaces}  # Performance settings
${spaces}  target_fps: $targetFps
${spaces}  hardware_acceleration: $hardwareAcceleration
${spaces}  vsync: $vsync
${spaces}  max_draw_calls: $maxDrawCalls
${spaces}  texture_atlas_size: $textureAtlasSize
${spaces}  glyph_cache_size: $glyphCacheSize
${spaces}  enable_profiling: $enableProfiling''';
  }
}

class ThemeConfig {
  final String background;
  final String foreground;
  final String cursor;
  final String selection;
  final String fontFamily;
  final double fontSize;
  final bool fontLigatures;
  
  const ThemeConfig({
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.fontFamily,
    required this.fontSize,
    required this.fontLigatures,
  });
  
  factory ThemeConfig.defaultConfig() {
    return const ThemeConfig(
      background: '#1a1a1a',
      foreground: '#ffeb3b',
      cursor: '#ff5722',
      selection: '#000713',
      fontFamily: 'Droid Sans Mono',
      fontSize: 14.0,
      fontLigatures: true,
    );
  }
  
  factory ThemeConfig.fromYaml(YamlMap yaml) {
    return ThemeConfig(
      background: yaml['background'] ?? '#1a1a1a',
      foreground: yaml['foreground'] ?? '#ffeb3b',
      cursor: yaml['cursor'] ?? '#ff5722',
      selection: yaml['selection'] ?? '#000713',
      fontFamily: yaml['font_family'] ?? 'Droid Sans Mono',
      fontSize: (yaml['font_size'] ?? 14.0).toDouble(),
      fontLigatures: yaml['font_ligatures'] ?? true,
    );
  }
  
  String toYaml({int indent = 0}) {
    final spaces = '  ' * indent;
    return '''
${spaces}  # PKM-centered theme
${spaces}  background: $background
${spaces}  foreground: $foreground
${spaces}  cursor: $cursor
${spaces}  selection: $selection
${spaces}  font_family: $fontFamily
${spaces}  font_size: $fontSize
${spaces}  font_ligatures: $fontLigatures''';
  }
}

class TerminalConfig {
  final String shellProgram;
  final List<String> shellArgs;
  final String ptyBackend;
  final int ptyBufferSize;
  final int ptyTimeout;
  final bool altSendEsc;
  final bool multiInstance;
  final String workingDirectory;
  
  const TerminalConfig({
    required this.shellProgram,
    required this.shellArgs,
    required this.ptyBackend,
    required this.ptyBufferSize,
    required this.ptyTimeout,
    required this.altSendEsc,
    required this.multiInstance,
    required this.workingDirectory,
  });
  
  factory TerminalConfig.defaultConfig() {
    return const TerminalConfig(
      shellProgram: '/bin/bash',
      shellArgs: ['--login'],
      ptyBackend: 'native',
      ptyBufferSize: 65536,
      ptyTimeout: 100,
      altSendEsc: true,
      multiInstance: true,
      workingDirectory: '',
    );
  }
  
  factory TerminalConfig.fromYaml(YamlMap yaml) {
    final shellConfig = yaml['shell'] ?? YamlMap();
    final ptyConfig = yaml['pty'] ?? YamlMap();
    
    return TerminalConfig(
      shellProgram: shellConfig['program'] ?? '/bin/bash',
      shellArgs: List<String>.from(shellConfig['args'] ?? ['--login']),
      ptyBackend: ptyConfig['backend'] ?? 'native',
      ptyBufferSize: ptyConfig['buffer_size'] ?? 65536,
      ptyTimeout: ptyConfig['timeout'] ?? 100,
      altSendEsc: yaml['alt_send_esc'] ?? true,
      multiInstance: yaml['multi_instance'] ?? true,
      workingDirectory: yaml['working_directory'] ?? '',
    );
  }
  
  String toYaml({int indent = 0}) {
    final spaces = '  ' * indent;
    return '''
${spaces}  # Shell configuration
${spaces}  shell:
${spaces}    program: $shellProgram
${spaces}    args: ${shellArgs.toString()}
${spaces}  # PTY configuration
${spaces}  pty:
${spaces}    backend: $ptyBackend
${spaces}    buffer_size: $ptyBufferSize
${spaces}    timeout: $ptyTimeout
${spaces}  alt_send_esc: $altSendEsc
${spaces}  multi_instance: $multiInstance
${spaces}  working_directory: $workingDirectory''';
  }
}

class KeybindingConfig {
  final List<KeyBinding> bindings;
  
  const KeybindingConfig({
    required this.bindings,
  });
  
  factory KeybindingConfig.defaultConfig() {
    return const KeybindingConfig(
      bindings: [
        KeyBinding(key: 'V', mods: ['Control'], action: 'Paste'),
        KeyBinding(key: 'C', mods: ['Control', 'Shift'], action: 'Copy'),
        KeyBinding(key: 'T', mods: ['Control', 'Shift'], action: 'NewTab'),
        KeyBinding(key: 'W', mods: ['Control', 'Shift'], action: 'CloseTab'),
        KeyBinding(key: 'F11', mods: [], action: 'ToggleFullscreen'),
      ],
    );
  }
  
  factory KeybindingConfig.fromYaml(YamlMap yaml) {
    final bindings = <KeyBinding>[];
    final yamlBindings = yaml['bindings'] as List? ?? [];
    
    for (final binding in yamlBindings) {
      if (binding is YamlMap) {
        bindings.add(KeyBinding(
          key: binding['key'] ?? '',
          mods: List<String>.from(binding['mods'] ?? []),
          action: binding['action'] ?? '',
        ));
      }
    }
    
    return KeybindingConfig(bindings: bindings);
  }
  
  String toYaml({int indent = 0}) {
    final spaces = '  ' * indent;
    final buffer = StringBuffer();
    buffer.writeln('${spaces}  # Keybindings');
    buffer.writeln('${spaces}  bindings:');
    
    for (final binding in bindings) {
      buffer.writeln('${spaces}    - key: ${binding.key}');
      buffer.writeln('${spaces}      mods: ${binding.mods}');
      buffer.writeln('${spaces}      action: ${binding.action}');
    }
    
    return buffer.toString();
  }
}

class KeyBinding {
  final String key;
  final List<String> mods;
  final String action;
  
  const KeyBinding({
    required this.key,
    required this.mods,
    required this.action,
  });
}

class AdvancedConfig {
  final int maxLogFileSize;
  final bool enableTelemetry;
  final bool autoUpdate;
  final String updateChannel;
  
  const AdvancedConfig({
    required this.maxLogFileSize,
    required this.enableTelemetry,
    required this.autoUpdate,
    required this.updateChannel,
  });
  
  factory AdvancedConfig.defaultConfig() {
    return const AdvancedConfig(
      maxLogFileSize: 10485760, // 10MB
      enableTelemetry: false,
      autoUpdate: true,
      updateChannel: 'stable',
    );
  }
  
  factory AdvancedConfig.fromYaml(YamlMap yaml) {
    return AdvancedConfig(
      maxLogFileSize: yaml['max_log_file_size'] ?? 10485760,
      enableTelemetry: yaml['enable_telemetry'] ?? false,
      autoUpdate: yaml['auto_update'] ?? true,
      updateChannel: yaml['update_channel'] ?? 'stable',
    );
  }
  
  String toYaml({int indent = 0}) {
    final spaces = '  ' * indent;
    return '''
${spaces}  # Advanced settings
${spaces}  max_log_file_size: $maxLogFileSize
${spaces}  enable_telemetry: $enableTelemetry
${spaces}  auto_update: $autoUpdate
${spaces}  update_channel: $updateChannel''';
  }
}

/// Fix common YAML indentation issues
String _fixYamlIndentation(String content) {
  final lines = content.split('\n');
  final fixedLines = <String>[];
  
  for (final line in lines) {
    if (line.trim().isEmpty) {
      fixedLines.add(line);
      continue;
    }
    
    // Fix tabs to spaces
    String fixedLine = line.replaceAll('\t', '  ');
    
    // Fix inconsistent indentation (2 spaces standard)
    if (fixedLine.startsWith(' ') && !fixedLine.startsWith('  ')) {
      fixedLine = '  $fixedLine';
    }
    
    fixedLines.add(fixedLine);
  }
  
  return fixedLines.join('\n');
}

/// Fix common YAML quote issues
String _fixYamlQuotes(String content) {
  String fixed = content;
  
  // Fix unquoted values with special characters
  fixed = fixed.replaceAllMapped(RegExp(r'^(\s*)([^:\s]+):\s*([^#\s].*?)(\s*$|\s*#)'), (match) {
    final indent = match.group(1) ?? '';
    final key = match.group(2) ?? '';
    final value = match.group(3) ?? '';
    final rest = match.group(4) ?? '';
    
    // Quote values with special characters
    if (value.contains(RegExp(r'[:\[\]{}|>*&]')) || value.contains('#')) {
      return '$indent$key: "$value"$rest';
    }
    return match.group(0)!;
  });
  
  return fixed;
}

/// Fix common YAML colon issues
String _fixYamlColons(String content) {
  String fixed = content;
  
  // Fix missing colons
  fixed = fixed.replaceAllMapped(RegExp(r'^(\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s+(.+)$'), (match) {
    final indent = match.group(1) ?? '';
    final key = match.group(2) ?? '';
    final value = match.group(3) ?? '';
    return '$indent$key: $value';
  });
  
  return fixed;
}

/// Fix common YAML list issues
String _fixYamlLists(String content) {
  String fixed = content;
  
  // Fix inconsistent list markers
  fixed = fixed.replaceAllMapped(RegExp(r'^(\s*)-\s*\n\s*([^-\s])'), (match) {
    final indent = match.group(1) ?? '';
    final nextLine = match.group(2) ?? '';
    return '$indent- $nextLine';
  });
  
  return fixed;
}

/// Merge two YAML maps, preferring the second
YamlMap _mergeYamlMaps(YamlMap defaults, YamlMap user) {
  final merged = <String, dynamic>{};
  
  // Add defaults
  for (final entry in defaults.entries) {
    merged[entry.key] = entry.value;
  }
  
  // Override with user values
  for (final entry in user.entries) {
    if (entry.value is YamlMap && merged[entry.key] is YamlMap) {
      // Recursively merge nested maps
      merged[entry.key] = _mergeYamlMaps(
        merged[entry.key] as YamlMap,
        entry.value as YamlMap,
      );
    } else {
      merged[entry.key] = entry.value;
    }
  }
  
  return YamlMap.wrap(merged);
}

/// Convert YAML map to string
String _yamlMapToString(YamlMap yaml) {
  final buffer = StringBuffer();
  _yamlMapToStringHelper(yaml, buffer, 0);
  return buffer.toString();
}

void _yamlMapToStringHelper(YamlMap yaml, StringBuffer buffer, int indent) {
  final spaces = '  ' * indent;
  
  for (final entry in yaml.entries) {
    final key = entry.key;
    final value = entry.value;
    
    buffer.write('$spaces$key:');
    
    if (value is YamlMap) {
      buffer.writeln();
      _yamlMapToStringHelper(value, buffer, indent + 1);
    } else if (value is List) {
      buffer.writeln();
      for (final item in value) {
        buffer.writeln('$spaces  - $item');
      }
    } else if (value is String) {
      buffer.writeln(' $value');
    } else {
      buffer.writeln(' $value');
    }
  }
}
