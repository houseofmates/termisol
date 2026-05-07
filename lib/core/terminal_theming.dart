import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:xterm/xterm.dart';

/// Terminal Theming with Workspace Context
/// 
/// Implements intelligent theming system:
/// - Workspace-aware color schemes
/// - Dynamic theme switching
/// - Custom color palettes
/// - Syntax highlighting themes
/// - Font management
/// - Background and transparency
/// - Theme synchronization
class TerminalTheming {
  bool _isInitialized = false;
  
  // Current theme state
  TerminalTheme _currentTheme = TerminalTheme();
  String _currentWorkspace = '';
  String _currentLanguage = '';
  final Map<String, TerminalTheme> _workspaceThemes = {};
  final Map<String, TerminalTheme> _languageThemes = {};
  final Map<String, TerminalTheme> _customThemes = {};
  
  // Theme storage
  String _themesPath = '';
  Timer? _autoSaveTimer;
  
  // Event handlers
  final List<Function(TerminalTheme)> _onThemeChanged = [];
  final List<Function(String)> _onWorkspaceThemeChanged = [];
  final List<Function(String)> _onLanguageThemeChanged = [];
  final List<Function(TerminalTheme)> _onCustomThemeAdded = [];
  final List<Function(String)> _onCustomThemeRemoved = [];
  
  TerminalTheming();
  
  bool get isInitialized => _isInitialized;
  TerminalTheme get currentTheme => _currentTheme;
  String get currentWorkspace => _currentWorkspace;
  String get currentLanguage => _currentLanguage;
  Map<String, TerminalTheme> get workspaceThemes => Map.unmodifiable(_workspaceThemes);
  Map<String, TerminalTheme> get languageThemes => Map.unmodifiable(_languageThemes);
  Map<String, TerminalTheme> get customThemes => Map.unmodifiable(_customThemes);
  
  /// Initialize theming system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup paths
      _setupPaths();
      
      // Load themes
      await _loadThemes();
      
      // Detect current context
      await _detectContext();
      
      // Start auto-save
      _startAutoSave();
      
      _isInitialized = true;
      debugPrint('🎨 Terminal Theming initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Terminal Theming: $e');
      rethrow;
    }
  }
  
  /// Setup file paths
  void _setupPaths() {
    final homeDir = Platform.environment['HOME'] ?? '';
    _themesPath = path.join(homeDir, '.termisol', 'themes');
  }
  
  /// Load existing themes
  Future<void> _loadThemes() async {
    try {
      final themesFile = File(path.join(_themesPath, 'themes.json'));
      if (await themesFile.exists()) {
        final content = await themesFile.readAsString();
        final data = jsonDecode(content);
        
        // Load workspace themes
        final workspaceThemesData = data['workspace_themes'] as Map? ?? {};
        for (final entry in workspaceThemesData.entries) {
          final theme = TerminalTheme.fromJson(entry.value);
          _workspaceThemes[entry.key] = theme;
        }
        
        // Load language themes
        final languageThemesData = data['language_themes'] as Map? ?? {};
        for (final entry in languageThemesData.entries) {
          final theme = TerminalTheme.fromJson(entry.value);
          _languageThemes[entry.key] = theme;
        }
        
        // Load custom themes
        final customThemesData = data['custom_themes'] as Map? ?? {};
        for (final entry in customThemesData.entries) {
          final theme = TerminalTheme.fromJson(entry.value);
          _customThemes[entry.key] = theme;
        }
        
        debugPrint('🎨 Loaded ${_workspaceThemes.length} workspace themes, ${_languageThemes.length} language themes, ${_customThemes.length} custom themes');
      } else {
        // Create default themes
        await _createDefaultThemes();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load themes: $e');
      await _createDefaultThemes();
    }
  }
  
  /// Create default themes
  Future<void> _createDefaultThemes() async {
    // Default workspace themes
    final defaultWorkspaceThemes = {
      'vibecode': TerminalTheme(
        name: 'Vibecode',
        description: 'Dark theme optimized for vibecode development',
        backgroundColor: Color(0xFF0A0A0A),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFF00FF00),
        selectionColor: Color(0xFF404040),
        borderColor: Color(0xFF333333),
        scrollbarColor: Color(0xFF555555),
        syntaxColors: {
          'keyword': Color(0xFFC586C0),
          'string': Color(0xFF98C379),
          'comment': Color(0xFF6A9955),
          'number': Color(0xFFD19A66),
          'operator': Color(0xFF56B6C2),
          'function': Color(0xFF61AFEF),
          'variable': Color(0xFFC678DD),
          'type': Color(0xFFE06C75),
          'error': Color(0xFFE06C75),
          'warning': Color(0xFFD19A66),
          'success': Color(0xFF98C379),
        },
        fontFamily: 'Varela Round',
        fontSize: 14.0,
        transparency: 0.95,
      ),
      'termisol': TerminalTheme(
        name: 'Termisol',
        description: 'Default theme for Termisol terminal',
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFF00FFFF),
        selectionColor: Color(0xFF4A90E2),
        borderColor: Color(0xFF444444),
        scrollbarColor: Color(0xFF666666),
        syntaxColors: {
          'keyword': Color(0xFFFF79C6),
          'string': Color(0xFFA6E22E),
          'comment': Color(0xFF6272A4),
          'number': Color(0xFFFD97F5),
          'operator': Color(0xFF56B6C2),
          'function': Color(0xFF61AFEF),
          'variable': Color(0xFFC678DD),
          'type': Color(0xFFE06C75),
          'error': Color(0xFFFF5F56),
          'warning': Color(0xFFFFB86C),
          'success': Color(0xFF50FA7B),
        },
        fontFamily: 'JetBrains Mono',
        fontSize: 14.0,
        transparency: 0.98,
      ),
      'house': TerminalTheme(
        name: 'House',
        description: 'Warm theme for house development',
        backgroundColor: Color(0xFF2B1B2B),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFF00FF7F),
        selectionColor: Color(0xFF4A5568),
        borderColor: Color(0xFF3C3C3C),
        scrollbarColor: Color(0xFF5A5A5A),
        syntaxColors: {
          'keyword': Color(0xFF8AB4F8),
          'string': Color(0xFFA8DADC),
          'comment': Color(0xFF6C7C7C),
          'number': Color(0xFFF39C12),
          'operator': Color(0xFF56B6C2),
          'function': Color(0xFF61AFEF),
          'variable': Color(0xFFC678DD),
          'type': Color(0xFFE06C75),
          'error': Color(0xFFFF5F56),
          'warning': Color(0xFFFFB86C),
          'success': Color(0xFF50FA7B),
        },
        fontFamily: 'Source Code Pro',
        fontSize: 13.0,
        transparency: 0.97,
      ),
    };
    
    // Default language themes
    final defaultLanguageThemes = {
      'dart': TerminalTheme(
        name: 'Dart',
        description: 'Optimized for Dart development',
        backgroundColor: Color(0xFF0A1929),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFF00D4FF),
        selectionColor: Color(0xFF00D4FF),
        borderColor: Color(0xFF333333),
        scrollbarColor: Color(0xFF555555),
        syntaxColors: {
          'keyword': Color(0xFF42A5F5),
          'string': Color(0xFF0A9FD6),
          'comment': Color(0xFF6A9955),
          'number': Color(0xFFD19A66),
          'operator': Color(0xFF56B6C2),
          'function': Color(0xFF61AFEF),
          'variable': Color(0xFFC678DD),
          'type': Color(0xFFE06C75),
          'error': Color(0xFFFF5F56),
          'warning': Color(0xFFFFB86C),
          'success': Color(0xFF50FA7B),
        },
        fontFamily: 'JetBrains Mono',
        fontSize: 14.0,
        transparency: 0.98,
      ),
      'python': TerminalTheme(
        name: 'Python',
        description: 'Optimized for Python development',
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFF00FF00),
        selectionColor: Color(0xFF4CAF50),
        borderColor: Color(0xFF444444),
        scrollbarColor: Color(0xFF666666),
        syntaxColors: {
          'keyword': Color(0xFFFF9500),
          'string': Color(0xFF81A1C1),
          'comment': Color(0xFF6A9955),
          'number': Color(0xFFAE81FF),
          'operator': Color(0xFF56B6C2),
          'function': Color(0xFF61AFEF),
          'variable': Color(0xFFC678DD),
          'type': Color(0xFFE06C75),
          'error': Color(0xFFFF5F56),
          'warning': Color(0xFFFFB86C),
          'success': Color(0xFF50FA7B),
        },
        fontFamily: 'Source Code Pro',
        fontSize: 13.0,
        transparency: 0.98,
      ),
      'javascript': TerminalTheme(
        name: 'JavaScript',
        description: 'Optimized for JavaScript development',
        backgroundColor: Color(0xFF2C3E50),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFFFFEB3B),
        selectionColor: Color(0xFFFFEB3B),
        borderColor: Color(0xFF444444),
        scrollbarColor: Color(0xFF666666),
        syntaxColors: {
          'keyword': Color(0FFF7C00),
          'string': Color(0xFF00BCD4),
          'comment': Color(0xFF6A9955),
          'number': Color(0FFFA8D00),
          'operator': Color(0FF56B6C2),
          'function': Color(0FF61AFEF),
          'variable': Color(0FFC678DD),
          'type': Color(0FFE06C75),
          'error': Color(0FFFF5F56),
          'warning': Color(0FFFFB86C),
          'success': Color(0FF50FA7B),
        },
        fontFamily: 'Source Code Pro',
        fontSize: 13.0,
        transparency: 0.98,
      ),
      'rust': TerminalTheme(
        name: 'Rust',
        description: 'Optimized for Rust development',
        backgroundColor: Color(0xFF1A1B1A),
        foregroundColor: Color(0xFFE0E0E0),
        cursorColor: Color(0xFFFF6B00),
        selectionColor: Color(0xFFFF6B00),
        borderColor: Color(0xFF444444),
        scrollbarColor: Color(0xFF666666),
        syntaxColors: {
          'keyword': Color(0FFBA0917),
          'string': Color(0FFA8DADC),
          'comment': Color(0FF6A9955),
          'number': Color(0FFAE81FF),
          'operator': Color(0FF56B6C2),
          'function': Color(0FF61AFEF),
          'variable': Color(0FFC678DD),
          'type': Color(0FFE06C75),
          'error': Color(0FFFF5F56),
          'warning': Color(0FFFFB86C),
          'success': Color(0FF50FA7B),
        },
        fontFamily: 'Source Code Pro',
        fontSize: 13.0,
        transparency: 0.98,
      ),
    };
    
    _workspaceThemes.addAll(defaultWorkspaceThemes);
    _languageThemes.addAll(defaultLanguageThemes);
    
    await _saveThemes();
  }
  
  /// Detect current context
  Future<void> _detectContext() async {
    try {
      // Detect current workspace
      final currentDir = Directory.current;
      
      // Check for workspace-specific theme
      if (currentDir.path.contains('vibecode')) {
        _currentWorkspace = 'vibecode';
        _applyTheme(_workspaceThemes['vibecode']!);
      } else if (currentDir.path.contains('termisol')) {
        _currentWorkspace = 'termisol';
        _applyTheme(_workspaceThemes['termisol']!);
      } else if (currentDir.path.contains('workspace')) {
        _currentWorkspace = 'workspace';
        _applyTheme(_workspaceThemes['house']!);
      } else {
        _currentWorkspace = 'default';
        _applyTheme(_workspaceThemes['termisol']!);
      }
      
      debugPrint('🎨 Detected workspace: $_currentWorkspace');
    } catch (e) {
      debugPrint('⚠️ Failed to detect context: $e');
    }
  }
  
  /// Apply theme
  void _applyTheme(TerminalTheme theme) {
    _currentTheme = theme;
    _onThemeChanged.forEach((callback) => callback(theme));
    debugPrint('🎨 Applied theme: ${theme.name}');
  }
  
  /// Start auto-save
  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _saveThemes();
    });
  }
  
  /// Switch to workspace theme
  Future<void> switchToWorkspaceTheme(String workspaceId) async {
    final theme = _workspaceThemes[workspaceId];
    if (theme != null) {
      _currentWorkspace = workspaceId;
      _applyTheme(theme);
      await _saveThemes();
      
      _onWorkspaceThemeChanged.forEach((callback) => callback(workspaceId));
      debugPrint('🎨 Switched to workspace theme: ${theme.name}');
    }
  }
  
  /// Switch to language theme
  Future<void> switchToLanguageTheme(String language) async {
    final theme = _languageThemes[language];
    if (theme != null) {
      _currentLanguage = language;
      _applyTheme(theme);
      await _saveThemes();
      
      _onLanguageThemeChanged.forEach((callback) => callback(language));
      debugPrint('🎨 Switched to language theme: ${theme.name}');
    }
  }
  
  /// Create custom theme
  Future<String> createCustomTheme({
    required String name,
    required String description,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? cursorColor,
    Color? selectionColor,
    Map<String, Color>? syntaxColors,
    String? fontFamily,
    double? fontSize,
    double? transparency,
  }) async {
    final themeId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    
    final customTheme = TerminalTheme(
      name: name,
      description: description,
      backgroundColor: backgroundColor ?? Color(0xFF1E1E1E),
      foregroundColor: foregroundColor ?? Color(0xFFE0E0E0),
      cursorColor: cursorColor ?? Color(0xFF00FFFF),
      selectionColor: selectionColor ?? Color(0xFF4A90E2),
      borderColor: Color(0xFF444444),
      scrollbarColor: Color(0xFF666666),
      syntaxColors: syntaxColors ?? {},
      fontFamily: fontFamily ?? 'JetBrains Mono',
      fontSize: fontSize ?? 14.0,
      transparency: transparency ?? 0.98,
      isCustom: true,
      createdAt: DateTime.now(),
    );
    
    _customThemes[themeId] = customTheme;
    await _saveThemes();
    
    _onCustomThemeAdded.forEach((callback) => callback(customTheme));
    debugPrint('🎨 Created custom theme: $name');
    
    return themeId;
  }
  
  /// Update custom theme
  Future<void> updateCustomTheme(String themeId, {
    String? name,
    String? description,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? cursorColor,
    Color? selectionColor,
    Map<String, Color>? syntaxColors,
    String? fontFamily,
    double? fontSize,
    double? transparency,
  }) async {
    final theme = _customThemes[themeId];
    if (theme == null) return;
    
    final updatedTheme = theme.copyWith(
      name: name,
      description: description,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      syntaxColors: syntaxColors,
      fontFamily: fontFamily,
      fontSize: fontSize,
      transparency: transparency,
    );
    
    _customThemes[themeId] = updatedTheme;
    await _saveThemes();
    
    debugPrint('🎨 Updated custom theme: $themeId');
  }
  
  /// Delete custom theme
  Future<void> deleteCustomTheme(String themeId) async {
    final theme = _customThemes.remove(themeId);
    if (theme != null) {
      await _saveThemes();
      
      _onCustomThemeRemoved.forEach((callback) => callback(themeId));
      debugPrint('🗑️ Deleted custom theme: $themeId');
    }
  }
  
  /// Get theme for syntax highlighting
  Color getSyntaxColor(String tokenType) {
    return _currentTheme.syntaxColors[tokenType] ?? 
           _currentTheme.foregroundColor;
  }
  
  /// Get available themes
  List<TerminalTheme> getAvailableThemes() {
    final themes = <TerminalTheme>[];
    
    // Add workspace themes
    themes.addAll(_workspaceThemes.values);
    
    // Add language themes
    themes.addAll(_languageThemes.values);
    
    // Add custom themes
    themes.addAll(_customThemes.values);
    
    return themes;
  }
  
  /// Search themes
  List<TerminalTheme> searchThemes(String query) {
    final lowerQuery = query.toLowerCase();
    
    return getAvailableThemes().where((theme) {
      return theme.name.toLowerCase().contains(lowerQuery) ||
             theme.description.toLowerCase().contains(lowerQuery) ||
             (theme.isCustom && theme.name.toLowerCase().contains(lowerQuery));
    }).toList();
  }
  
  /// Export theme
  Future<String> exportTheme(String themeId) async {
    final theme = _getThemeById(themeId);
    if (theme == null) return '';
    
    final exportData = {
      'name': theme.name,
      'description': theme.description,
      'background_color': theme.backgroundColor.value.toRadixString(16).padLeft(2, '0'),
      'foreground_color': theme.foregroundColor.value.toRadixString(16).padLeft(2, '0'),
      'cursor_color': theme.cursorColor.value.toRadixString(16).padLeft(2, '0'),
      'selection_color': theme.selectionColor.value.toRadixString(16).padLeft(2, '0'),
      'border_color': theme.borderColor.value.toRadixString(16).padLeft(2, '0'),
      'scrollbar_color': theme.scrollbarColor.value.toRadixString(16).padLeft(2, '0'),
      'syntax_colors': theme.syntaxColors.map((key, value) => MapEntry(key, value.value.toRadixString(16).padLeft(2, '0'))),
      'font_family': theme.fontFamily,
      'font_size': theme.fontSize,
      'transparency': theme.transparency,
      'is_custom': theme.isCustom,
      'exported_at': DateTime.now().toIso8601String(),
    };
    
    return jsonEncode(exportData);
  }
  
  /// Import theme
  Future<bool> importTheme(String themeData) async {
    try {
      final data = jsonDecode(themeData);
      final theme = TerminalTheme.fromJson(data);
      
      final themeId = 'imported_${DateTime.now().millisecondsSinceEpoch}';
      final importedTheme = theme.copyWith(
        id: themeId,
        isCustom: true,
        importedAt: DateTime.now(),
      );
      
      _customThemes[themeId] = importedTheme;
      await _saveThemes();
      
      _onCustomThemeAdded.forEach((callback) => callback(importedTheme));
      debugPrint('🎨 Imported theme: ${theme.name}');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to import theme: $e');
      return false;
    }
  }
  
  /// Get theme by ID
  TerminalTheme? _getThemeById(String themeId) {
    if (_workspaceThemes.containsKey(themeId)) {
      return _workspaceThemes[themeId];
    } else if (_languageThemes.containsKey(themeId)) {
      return _languageThemes[themeId];
    } else if (_customThemes.containsKey(themeId)) {
      return _customThemes[themeId];
    }
    return null;
  }
  
  /// Save themes
  Future<void> _saveThemes() async {
    try {
      final data = {
        'version': '1.0',
        'current_workspace': _currentWorkspace,
        'current_language': _currentLanguage,
        'workspace_themes': _workspaceThemes.map((k, v) => MapEntry(k, v.toJson())),
        'language_themes': _languageThemes.map((k, v) => MapEntry(k, v.toJson())),
        'custom_themes': _customThemes.map((k, v) => MapEntry(k, v.toJson())),
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      final themesFile = File(path.join(_themesPath, 'themes.json'));
      await themesFile.parent.create(recursive: true);
      await themesFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save themes: $e');
    }
  }
  
  /// Get theme statistics
  Map<String, dynamic> getStatistics() {
    return {
      'current_workspace': _currentWorkspace,
      'current_language': _currentLanguage,
      'current_theme': _currentTheme.name,
      'workspace_themes_count': _workspaceThemes.length,
      'language_themes_count': _languageThemes.length,
      'custom_themes_count': _customThemes.length,
      'total_themes_count': _workspaceThemes.length + _languageThemes.length + _customThemes.length,
      'auto_save_active': _autoSaveTimer?.isActive ?? false,
    };
  }
  
  /// Add theme changed listener
  void addThemeChangedListener(Function(TerminalTheme) listener) {
    _onThemeChanged.add(listener);
  }
  
  /// Add workspace theme changed listener
  void addWorkspaceThemeChangedListener(Function(String) listener) {
    _onWorkspaceThemeChanged.add(listener);
  }
  
  /// Add language theme changed listener
  void addLanguageThemeChangedListener(Function(String) listener) {
    _onLanguageThemeChanged.add(listener);
  }
  
  /// Add custom theme added listener
  void addCustomThemeAddedListener(Function(TerminalTheme) listener) {
    _onCustomThemeAdded.add(listener);
  }
  
  /// Add custom theme removed listener
  void addCustomThemeRemovedListener(Function(String) listener) {
    _onCustomThemeRemoved.add(listener);
  }
  
  /// Remove theme changed listener
  void removeThemeChangedListener(Function(TerminalTheme) listener) {
    _onThemeChanged.remove(listener);
  }
  
  /// Remove workspace theme changed listener
  void removeWorkspaceThemeChangedListener(Function(String) listener) {
    _onWorkspaceThemeChanged.remove(listener);
  }
  
  /// Remove language theme changed listener
  void removeLanguageThemeChangedListener(Function(String) listener {
    _onLanguageThemeChanged.remove(listener);
  }
  
  /// Remove custom theme added listener
  void removeCustomThemeAddedListener(Function(TerminalTheme) listener {
    _onCustomThemeAdded.remove(listener);
  }
  
  /// Remove custom theme removed listener
  void removeCustomThemeRemovedListener(Function(String) listener {
    _onCustomThemeRemoved.remove(listener);
  }
  
  /// Dispose theming system
  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    
    // Save final state
    await _saveThemes();
    
    // Clear listeners
    _onThemeChanged.clear();
    _onWorkspaceThemeChanged.clear();
    _onLanguageThemeChanged.clear();
    _onCustomThemeAdded.clear();
    _onCustomThemeRemoved.clear();
    
    _isInitialized = false;
    debugPrint('🎨 Terminal Theming disposed');
  }
}

/// Terminal theme model
class TerminalTheme {
  final String id;
  final String name;
  final String description;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color cursorColor;
  final Color selectionColor;
  final Color borderColor;
  final Color scrollbarColor;
  final Map<String, Color> syntaxColors;
  final String fontFamily;
  final double fontSize;
  final double transparency;
  final bool isCustom;
  final DateTime? createdAt;
  final DateTime? importedAt;
  final Map<String, dynamic>? metadata;
  
  TerminalTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.cursorColor,
    required this.selectionColor,
    required this.borderColor,
    required this.scrollbarColor,
    required this.syntaxColors,
    required this.fontFamily,
    required this.fontSize,
    required this.transparency,
    this.isCustom = false,
    this.createdAt,
    this.importedAt,
    this.metadata,
  });
  
  factory TerminalTheme.fromJson(Map<String, dynamic> json) {
    return TerminalTheme(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      backgroundColor: Color(int.parse(json['background_color'] ?? '0xFF1E1E1E')),
      foregroundColor: Color(int.parse(json['foreground_color'] ?? '0xFFE0E0E0')),
      cursorColor: Color(int.parse(json['cursor_color'] ?? '0xFF00FFFF')),
      selectionColor: Color(int.parse(json['selection_color'] ?? '0xFF4A90E2')),
      borderColor: Color(int.parse(json['border_color'] ?? '0xFF444444')),
      scrollbarColor: Color(int.parse(json['scrollbar_color'] ?? '0xFF666666')),
      syntaxColors: (json['syntax_colors'] as Map? ?? {})
          .map((k, v) => MapEntry(k, Color(int.parse(v)))),
      fontFamily: json['font_family'] ?? 'JetBrains Mono',
      fontSize: (json['font_size'] ?? 14.0).toDouble(),
      transparency: (json['transparency'] ?? 0.98).toDouble(),
      isCustom: json['is_custom'] ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : null,
      importedAt: json['imported_at'] != null 
          ? DateTime.parse(json['imported_at'])
          : null,
      metadata: json['metadata'],
    );
  }
  
  TerminalTheme copyWith({
    String? id,
    String? name,
    String? description,
    Color? backgroundColor,
    Color? foregroundColor,
    Color? cursorColor,
    Color? selectionColor,
    Color? borderColor,
    Color? scrollbarColor,
    Map<String, Color>? syntaxColors,
    String? fontFamily,
    double? fontSize,
    double? transparency,
    bool? isCustom,
    DateTime? createdAt,
    DateTime? importedAt,
    Map<String, dynamic>? metadata,
  }) {
    return TerminalTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      cursorColor: cursorColor ?? this.cursorColor,
      selectionColor: selectionColor ?? this.selectionColor,
      borderColor: borderColor ?? this.borderColor,
      scrollbarColor: scrollbarColor ?? this.scrollbarColor,
      syntaxColors: syntaxColors ?? this.syntaxColors,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      transparency: transparency ?? this.transparency,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
      importedAt: importedAt ?? this.importedAt,
      metadata: metadata ?? this.metadata,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'background_color': backgroundColor.value.toRadixString(16).padLeft(2, '0'),
      'foreground_color': foregroundColor.value.toRadixString(16).padLeft(2, '0'),
      'cursor_color': cursorColor.value.toRadixString(16).padLeft(2, '0'),
      'selection_color': selectionColor.value.toRadixString(16).padLeft(2, '0'),
      'border_color': borderColor.value.toRadixString(16).padLeft(2, '0'),
      'scrollbar_color': scrollbarColor.value.toRadixString(16).padLeft(2, '0'),
      'syntax_colors': syntaxColors.map((k, v) => MapEntry(k, v.value.toRadixString(16).padLeft(2, '0'))),
      'font_family': fontFamily,
      'font_size': fontSize,
      'transparency': transparency,
      'is_custom': isCustom,
      'created_at': createdAt?.toIso8601String(),
      'imported_at': importedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
}
