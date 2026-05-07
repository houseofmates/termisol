import 'dart:async';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Production Configuration System - Alacritty-inspired with PKM aesthetic
/// 
/// Features:
/// - YAML configuration with validation
/// - Hot-reloading with file watching
/// - Hierarchical defaults with inheritance
/// - Performance-first settings
/// - Cross-platform portability
class ProductionConfigSystem {
  static const String _configFileName = 'termisol.yaml';
  static const String _configDirName = '.termisol';
  
  late final File _configFile;
  late final StreamSubscription _configWatcher;
  
  TermisolConfig _config = TermisolConfig.defaultConfig();
  final _configController = StreamController<TermisolConfig>.broadcast();
  
  bool _isLoaded = false;
  bool _hotReloadEnabled = true;
  
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
  
  ProductionConfigSystem._();
  
  /// Initialize production configuration system
  static Future<ProductionConfigSystem> initialize() async {
    final config = ProductionConfigSystem._();
    await config._loadConfiguration();
    await config._setupHotReload();
    return config;
  }
  
  /// Load configuration with full validation
  Future<void> _loadConfiguration() async {
    try {
      await _ensureConfigDirectory();
      _configFile = await _getConfigFile();
      
      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();
        final yaml = loadYaml(content);
        _config = TermisolConfig.fromYaml(yaml);
        debugPrint('✅ Configuration loaded from ${_configFile.path}');
      } else {
        await _saveDefaultConfiguration();
        debugPrint('✅ Default configuration created');
      }
      
      await _validateConfiguration();
      _isLoaded = true;
      
    } catch (e) {
      debugPrint('⚠️ Configuration load failed: $e - using defaults');
      _config = TermisolConfig.defaultConfig();
      _isLoaded = true;
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
