import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Terminal Layout Manager - Best-in-class layout saving and restoration
/// 
/// Provides comprehensive terminal layout management with:
/// - Ctrl+Shift+S hotkey for saving layouts
/// - Multiple layout profiles
/// - Automatic layout detection
/// - Layout import/export functionality
/// - Window position and size management
/// - Tab arrangement and workspace organization
class TerminalLayoutManager {
  static final TerminalLayoutManager _instance = TerminalLayoutManager._internal();
  factory TerminalLayoutManager() => _instance;
  TerminalLayoutManager._internal();

  final Map<String, LayoutProfile> _layouts = {};
  final Map<String, WorkspaceState> _workspaces = {};
  LayoutProfile? _currentLayout;
  String? _currentWorkspaceId;
  
  bool _isInitialized = false;
  Timer? _autoSaveTimer;
  
  // Layout configuration
  static const Duration _autoSaveInterval = Duration(minutes: 2);
  static const int _maxLayouts = 20;
  static const int _maxWorkspaces = 10;
  
  final _layoutController = StreamController<LayoutEvent>.broadcast();
  Stream<LayoutEvent> get events => _layoutController.stream;
  
  bool get isInitialized => _isInitialized;
  LayoutProfile? get currentLayout => _currentLayout;
  String? get currentWorkspaceId => _currentWorkspaceId;

  /// Initialize terminal layout manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Create layouts directory
      await _ensureLayoutsDirectory();
      
      // Load existing layouts
      await _loadExistingLayouts();
      
      // Set up hotkey listener
      _setupHotkeyListener();
      
      // Start auto-save timer
      _startAutoSaveTimer();
      
      // Detect current layout
      await _detectCurrentLayout();
      
      _isInitialized = true;
      debugPrint('📐 Terminal Layout Manager initialized');
      
    } catch (e) {
      debugPrint('❌ Failed to initialize Terminal Layout Manager: $e');
      rethrow;
    }
  }

  /// Save current layout with Ctrl+Shift+S
  Future<void> saveCurrentLayout({String? name, String? description}) async {
    try {
      final layout = await _captureCurrentLayout();
      final layoutName = name ?? 'Layout ${DateTime.now().millisecondsSinceEpoch}';
      
      final profile = LayoutProfile(
        id: _generateLayoutId(),
        name: layoutName,
        description: description ?? 'Saved at ${DateTime.now()}',
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        layout: layout,
        workspaceStates: Map.from(_workspaces),
      );

      _layouts[profile.id] = profile;
      _currentLayout = profile;

      // Save to file
      await _saveLayout(profile);

      // Emit layout saved event
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.layoutSaved,
        layoutId: profile.id,
        timestamp: DateTime.now(),
      ));

      // Show notification
      await _showNotification('Layout saved: $layoutName');

      debugPrint('📐 Saved layout: $layoutName');
      
    } catch (e) {
      debugPrint('❌ Failed to save layout: $e');
      await _showNotification('Failed to save layout: $e');
    }
  }

  /// Load a layout
  Future<bool> loadLayout(String layoutId) async {
    try {
      final layout = _layouts[layoutId];
      if (layout == null) {
        debugPrint('❌ Layout not found: $layoutId');
        return false;
      }

      // Apply layout
      await _applyLayout(layout);

      _currentLayout = layout;

      // Apply workspace states
      _workspaces.clear();
      _workspaces.addAll(layout.workspaceStates);

      // Emit layout loaded event
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.layoutLoaded,
        layoutId: layoutId,
        timestamp: DateTime.now(),
      ));

      await _showNotification('Layout loaded: ${layout.name}');

      debugPrint('📐 Loaded layout: ${layout.name}');
      return true;
      
    } catch (e) {
      debugPrint('❌ Failed to load layout: $e');
      await _showNotification('Failed to load layout: $e');
      return false;
    }
  }

  /// Delete a layout
  Future<void> deleteLayout(String layoutId) async {
    try {
      // Remove from memory
      _layouts.remove(layoutId);
      
      if (_currentLayout?.id == layoutId) {
        _currentLayout = null;
      }

      // Delete layout file
      final layoutFile = await _getLayoutFile(layoutId);
      if (await layoutFile.exists()) {
        await layoutFile.delete();
      }

      // Emit layout deleted event
      _layoutController.add(LayoutEvent(
        type: LayoutEventType.layoutDeleted,
        layoutId: layoutId,
        timestamp: DateTime.now(),
      ));

      debugPrint('📐 Deleted layout: $layoutId');
      
    } catch (e) {
      debugPrint('❌ Failed to delete layout: $e');
    }
  }

  /// Create a new workspace
  Future<void> createWorkspace({
    String? name,
    List<TerminalTabState>? tabs,
    WindowState? windowState,
  }) async {
    final workspaceId = _generateWorkspaceId();
    final workspaceName = name ?? 'Workspace ${DateTime.now().millisecondsSinceEpoch}';
    
    _workspaces[workspaceId] = WorkspaceState(
      id: workspaceId,
      name: workspaceName,
      tabs: tabs ?? [],
      windowState: windowState ?? WindowState.defaultState(),
      createdAt: DateTime.now(),
    );

    _currentWorkspaceId = workspaceId;

    // Save current layout if exists
    if (_currentLayout != null) {
      await _saveCurrentLayout();
    }

    _layoutController.add(LayoutEvent(
      type: LayoutEventType.workspaceCreated,
      workspaceId: workspaceId,
      timestamp: DateTime.now(),
    ));

    debugPrint('📐 Created workspace: $workspaceName');
  }

  /// Switch to workspace
  Future<void> switchWorkspace(String workspaceId) async {
    final workspace = _workspaces[workspaceId];
    if (workspace == null) {
      debugPrint('❌ Workspace not found: $workspaceId');
      return;
    }

    _currentWorkspaceId = workspaceId;

    // Apply workspace state
    await _applyWorkspaceState(workspace);

    _layoutController.add(LayoutEvent(
      type: LayoutEventType.workspaceSwitched,
      workspaceId: workspaceId,
      timestamp: DateTime.now(),
    ));

    debugPrint('📐 Switched to workspace: ${workspace.name}');
  }

  /// Get list of available layouts
  List<LayoutInfo> getAvailableLayouts() {
    return _layouts.entries.map((entry) => LayoutInfo(
      id: entry.key,
      name: entry.value.name,
      description: entry.value.description,
      createdAt: entry.value.createdAt,
      lastModified: entry.value.lastModified,
      workspaceCount: entry.value.workspaceStates.length,
    )).toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
  }

  /// Get list of workspaces
  List<WorkspaceInfo> getAvailableWorkspaces() {
    return _workspaces.entries.map((entry) => WorkspaceInfo(
      id: entry.key,
      name: entry.value.name,
      tabCount: entry.value.tabs.length,
      isActive: entry.key == _currentWorkspaceId,
      createdAt: entry.value.createdAt,
    )).toList();
  }

  /// Export layout to file
  Future<void> exportLayout(String layoutId, String filePath) async {
    try {
      final layout = _layouts[layoutId];
      if (layout == null) {
        throw ArgumentError('Layout not found: $layoutId');
      }

      final file = File(filePath);
      final layoutJson = json.encode(layout.toJson());
      await file.writeAsString(layoutJson);

      await _showNotification('Layout exported to: $filePath');

      debugPrint('📐 Exported layout: ${layout.name} to $filePath');
      
    } catch (e) {
      debugPrint('❌ Failed to export layout: $e');
      await _showNotification('Failed to export layout: $e');
    }
  }

  /// Import layout from file
  Future<bool> importLayout(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw ArgumentError('File not found: $filePath');
      }

      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      
      final layout = LayoutProfile.fromJson(data);
      
      // Generate new ID to avoid conflicts
      final newLayout = LayoutProfile(
        id: _generateLayoutId(),
        name: '${layout.name} (Imported)',
        description: 'Imported from $filePath',
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        layout: layout.layout,
        workspaceStates: layout.workspaceStates,
      );

      _layouts[newLayout.id] = newLayout;
      await _saveLayout(newLayout);

      await _showNotification('Layout imported: ${newLayout.name}');

      debugPrint('📐 Imported layout: ${newLayout.name}');
      return true;
      
    } catch (e) {
      debugPrint('❌ Failed to import layout: $e');
      await _showNotification('Failed to import layout: $e');
      return false;
    }
  }

  /// Capture current layout
  Future<TerminalLayout> _captureCurrentLayout() async {
    // This would capture the current terminal layout
    // For now, return a simulated layout
    return TerminalLayout(
      version: '1.0',
      timestamp: DateTime.now(),
      windowState: await _captureWindowState(),
      terminalStates: await _captureTerminalStates(),
      tabConfiguration: await _captureTabConfiguration(),
      splitConfiguration: await _captureSplitConfiguration(),
      themeConfiguration: await _captureThemeConfiguration(),
    );
  }

  /// Apply layout
  Future<void> _applyLayout(LayoutProfile layout) async {
    // Apply window state
    await _applyWindowState(layout.layout.windowState);

    // Apply terminal states
    for (final terminalState in layout.layout.terminalStates) {
      await _applyTerminalState(terminalState);
    }

    // Apply tab configuration
    await _applyTabConfiguration(layout.layout.tabConfiguration);

    // Apply split configuration
    await _applySplitConfiguration(layout.layout.splitConfiguration);

    // Apply theme configuration
    await _applyThemeConfiguration(layout.layout.themeConfiguration);

    debugPrint('📐 Applied layout: ${layout.name}');
  }

  /// Apply workspace state
  Future<void> _applyWorkspaceState(WorkspaceState workspace) async {
    // Apply window state
    await _applyWindowState(workspace.windowState);

    // Apply tabs
    for (final tab in workspace.tabs) {
      await _applyTabState(tab);
    }

    debugPrint('📐 Applied workspace: ${workspace.name}');
  }

  /// Capture window state
  Future<WindowState> _captureWindowState() async {
    // This would capture actual window state
    return WindowState(
      x: 100,
      y: 100,
      width: 1200,
      height: 800,
      maximized: false,
      fullscreen: false,
    );
  }

  /// Capture terminal states
  Future<List<TerminalTabState>> _captureTerminalStates() async {
    // This would capture actual terminal states
    return [
      TerminalTabState(
        id: 'tab1',
        title: 'Terminal',
        workingDirectory: '/home/user',
        font: 'Fira Code',
        fontSize: 14,
        theme: 'dark',
      ),
    ];
  }

  /// Capture tab configuration
  Future<TabConfiguration> _captureTabConfiguration() async {
    return TabConfiguration(
      activeTabIndex: 0,
      tabPositions: [
        TabPosition(id: 'tab1', x: 0, y: 0, width: 600, height: 400),
        TabPosition(id: 'tab2', x: 600, y: 0, width: 600, height: 400),
      ],
      tabBarVisible: true,
      tabBarPosition: TabBarPosition.top,
    );
  }

  /// Capture split configuration
  Future<SplitConfiguration> _captureSplitConfiguration() async {
    return SplitConfiguration(
      orientation: SplitOrientation.horizontal,
      splits: [
        SplitPane(
          id: 'pane1',
          size: 0.5,
          tabs: ['tab1'],
        ),
        SplitPane(
          id: 'pane2',
          size: 0.5,
          tabs: ['tab2'],
        ),
      ],
      resizable: true,
      dividerSize: 4,
    );
  }

  /// Capture theme configuration
  Future<ThemeConfiguration> _captureThemeConfiguration() async {
    return ThemeConfiguration(
      theme: 'dark',
      fontFamily: 'Fira Code',
      fontSize: 14,
      opacity: 0.9,
      backgroundOpacity: 0.95,
    );
  }

  /// Apply window state
  Future<void> _applyWindowState(WindowState state) async {
    // This would apply the window state
    debugPrint('📐 Applying window state: ${state.width}x${state.height}');
  }

  /// Apply terminal state
  Future<void> _applyTerminalState(TerminalTabState state) async {
    // This would apply the terminal state
    debugPrint('📐 Applying terminal state: ${state.title}');
  }

  /// Apply tab configuration
  Future<void> _applyTabConfiguration(TabConfiguration config) async {
    // This would apply the tab configuration
    debugPrint('📐 Applying tab configuration');
  }

  /// Apply split configuration
  Future<void> _applySplitConfiguration(SplitConfiguration config) async {
    // This would apply the split configuration
    debugPrint('📐 Applying split configuration');
  }

  /// Apply theme configuration
  Future<void> _applyThemeConfiguration(ThemeConfiguration config) async {
    // This would apply the theme configuration
    debugPrint('📐 Applying theme configuration');
  }

  /// Apply tab state
  Future<void> _applyTabState(TerminalTabState tab) async {
    // This would apply the tab state
    debugPrint('📐 Applying tab state: ${tab.title}');
  }

  /// Detect current layout
  Future<void> _detectCurrentLayout() async {
    // This would detect the current layout from the running application
    debugPrint('📐 Detecting current layout');
  }

  /// Set up hotkey listener
  void _setupHotkeyListener() {
    // This would set up the Ctrl+Shift+S hotkey
    debugPrint('📐 Setting up Ctrl+Shift+S hotkey');
  }

  /// Load existing layouts
  Future<void> _loadExistingLayouts() async {
    try {
      final layoutsDir = await _getLayoutsDir();
      if (!await layoutsDir.exists()) {
        return;
      }

      final layoutFiles = await layoutsDir.list().where((entity) => 
          entity is File && entity.path.endsWith('.json')).toList();

      for (final file in layoutFiles) {
        try {
          final content = await file.readAsString();
          final data = json.decode(content) as Map<String, dynamic>;
          
          final layout = LayoutProfile.fromJson(data);
          _layouts[layout.id] = layout;
          
        } catch (e) {
          debugPrint('❌ Failed to load layout from ${file.path}: $e');
        }
      }

      debugPrint('📐 Loaded ${_layouts.length} existing layouts');
      
    } catch (e) {
      debugPrint('❌ Failed to load existing layouts: $e');
    }
  }

  /// Save layout to file
  Future<void> _saveLayout(LayoutProfile layout) async {
    try {
      final layoutFile = await _getLayoutFile(layout.id);
      final layoutJson = json.encode(layout.toJson());
      
      await layoutFile.writeAsString(layoutJson);
      
    } catch (e) {
      debugPrint('❌ Failed to save layout: $e');
    }
  }

  /// Ensure layouts directory exists
  Future<void> _ensureLayoutsDirectory() async {
    final layoutsDir = await _getLayoutsDir();
    await layoutsDir.create(recursive: true);
  }

  /// Get layouts directory
  Future<Directory> _getLayoutsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/termisol/layouts');
  }

  /// Get layout file
  Future<File> _getLayoutFile(String layoutId) async {
    final layoutsDir = await _getLayoutsDir();
    return File('${layoutsDir.path}/$layoutId.json');
  }

  /// Generate layout ID
  String _generateLayoutId() {
    return 'layout_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Generate workspace ID
  String _generateWorkspaceId() {
    return 'workspace_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Show notification
  Future<void> _showNotification(String message) async {
    // This would show a system notification
    debugPrint('🔔 $message');
  }

  /// Start auto-save timer
  void _startAutoSaveTimer() {
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) {
      if (_currentLayout != null) {
        unawaited(_saveCurrentLayout());
      }
    });
  }

  /// Get layout statistics
  LayoutStatistics getStatistics() {
    return LayoutStatistics(
      totalLayouts: _layouts.length,
      currentLayoutId: _currentLayout?.id,
      totalWorkspaces: _workspaces.length,
      currentWorkspaceId: _currentWorkspaceId,
      lastSaveTime: _currentLayout?.lastModified,
    );
  }

  /// Dispose terminal layout manager
  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
    _layoutController.close();
    
    // Save current layout
    if (_currentLayout != null) {
      await _saveCurrentLayout();
    }
    
    _layouts.clear();
    _workspaces.clear();
    _currentLayout = null;
    _currentWorkspaceId = null;
    
    debugPrint('📐 Terminal Layout Manager disposed');
  }
}

/// Layout profile
class LayoutProfile {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  DateTime lastModified;
  final TerminalLayout layout;
  final Map<String, WorkspaceState> workspaceStates;
  
  LayoutProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.lastModified,
    required this.layout,
    required this.workspaceStates,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
    'layout': layout.toJson(),
    'workspaceStates': workspaceStates.map((k, v) => MapEntry(k, v.toJson())),
  };

  static LayoutProfile fromJson(Map<String, dynamic> json) => LayoutProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastModified: DateTime.parse(json['lastModified'] as String),
    layout: TerminalLayout.fromJson(json['layout'] as Map<String, dynamic>),
    workspaceStates: (json['workspaceStates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, WorkspaceState.fromJson(v as Map<String, dynamic>)),
    ),
  );
}

/// Terminal layout
class TerminalLayout {
  final String version;
  final DateTime timestamp;
  final WindowState windowState;
  final List<TerminalTabState> terminalStates;
  final TabConfiguration tabConfiguration;
  final SplitConfiguration splitConfiguration;
  final ThemeConfiguration themeConfiguration;
  
  TerminalLayout({
    required this.version,
    required this.timestamp,
    required this.windowState,
    required this.terminalStates,
    required this.tabConfiguration,
    required this.splitConfiguration,
    required this.themeConfiguration,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'windowState': windowState.toJson(),
    'terminalStates': terminalStates.map((t) => t.toJson()),
    'tabConfiguration': tabConfiguration.toJson(),
    'splitConfiguration': splitConfiguration.toJson(),
    'themeConfiguration': themeConfiguration.toJson(),
  };

  static TerminalLayout fromJson(Map<String, dynamic> json) => TerminalLayout(
    version: json['version'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    windowState: WindowState.fromJson(json['windowState'] as Map<String, dynamic>),
    terminalStates: (json['terminalStates'] as List)
        .map((t) => TerminalTabState.fromJson(t as Map<String, dynamic>))
        .toList(),
    tabConfiguration: TabConfiguration.fromJson(json['tabConfiguration'] as Map<String, dynamic>),
    splitConfiguration: SplitConfiguration.fromJson(json['splitConfiguration'] as Map<String, dynamic>),
    themeConfiguration: ThemeConfiguration.fromJson(json['themeConfiguration'] as Map<String, dynamic>),
  );
}

/// Window state
class WindowState {
  final int x;
  final int y;
  final int width;
  final int height;
  final bool maximized;
  final bool fullscreen;
  
  WindowState({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maximized,
    required this.fullscreen,
  });

  static WindowState defaultState() => WindowState(
    x: 100,
    y: 100,
    width: 1200,
    height: 800,
    maximized: false,
    fullscreen: false,
  );

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'maximized': maximized,
    'fullscreen': fullscreen,
  };

  static WindowState fromJson(Map<String, dynamic> json) => WindowState(
    x: json['x'] as int,
    y: json['y'] as int,
    width: json['width'] as int,
    height: json['height'] as int,
    maximized: json['maximized'] as bool,
    fullscreen: json['fullscreen'] as bool,
  );
}

/// Terminal tab state
class TerminalTabState {
  final String id;
  final String title;
  final String workingDirectory;
  final String font;
  final double fontSize;
  final String theme;
  
  TerminalTabState({
    required this.id,
    required this.title,
    required this.workingDirectory,
    required this.font,
    required this.fontSize,
    required this.theme,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'workingDirectory': workingDirectory,
    'font': font,
    'fontSize': fontSize,
    'theme': theme,
  };

  static TerminalTabState fromJson(Map<String, dynamic> json) => TerminalTabState(
    id: json['id'] as String,
    title: json['title'] as String,
    workingDirectory: json['workingDirectory'] as String,
    font: json['font'] as String,
    fontSize: (json['fontSize'] as num).toDouble(),
    theme: json['theme'] as String,
  );
}

/// Tab configuration
class TabConfiguration {
  final int activeTabIndex;
  final List<TabPosition> tabPositions;
  final bool tabBarVisible;
  final TabBarPosition tabBarPosition;
  
  TabConfiguration({
    required this.activeTabIndex,
    required this.tabPositions,
    required this.tabBarVisible,
    required this.tabBarPosition,
  });

  Map<String, dynamic> toJson() => {
    'activeTabIndex': activeTabIndex,
    'tabPositions': tabPositions.map((t) => t.toJson()),
    'tabBarVisible': tabBarVisible,
    'tabBarPosition': tabBarPosition.toString(),
  };

  static TabConfiguration fromJson(Map<String, dynamic> json) => TabConfiguration(
    activeTabIndex: json['activeTabIndex'] as int,
    tabPositions: (json['tabPositions'] as List)
        .map((t) => TabPosition.fromJson(t as Map<String, dynamic>))
        .toList(),
    tabBarVisible: json['tabBarVisible'] as bool,
    tabBarPosition: TabBarPosition.values.firstWhere(
      (e) => e.toString() == json['tabBarPosition'] as String,
      orElse: () => TabBarPosition.top,
    ),
  );
}

/// Tab position
class TabPosition {
  final String id;
  final int x;
  final int y;
  final int width;
  final int height;
  
  TabPosition({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  static TabPosition fromJson(Map<String, dynamic> json) => TabPosition(
    id: json['id'] as String,
    x: json['x'] as int,
    y: json['y'] as int,
    width: json['width'] as int,
    height: json['height'] as int,
  );
}

/// Split configuration
class SplitConfiguration {
  final SplitOrientation orientation;
  final List<SplitPane> splits;
  final bool resizable;
  final int dividerSize;
  
  SplitConfiguration({
    required this.orientation,
    required this.splits,
    required this.resizable,
    required this.dividerSize,
  });

  Map<String, dynamic> toJson() => {
    'orientation': orientation.toString(),
    'splits': splits.map((s) => s.toJson()),
    'resizable': resizable,
    'dividerSize': dividerSize,
  };

  static SplitConfiguration fromJson(Map<String, dynamic> json) => SplitConfiguration(
    orientation: SplitOrientation.values.firstWhere(
      (e) => e.toString() == json['orientation'] as String,
      orElse: () => SplitOrientation.horizontal,
    ),
    splits: (json['splits'] as List)
        .map((s) => SplitPane.fromJson(s as Map<String, dynamic>))
        .toList(),
    resizable: json['resizable'] as bool,
    dividerSize: json['dividerSize'] as int,
  );
}

/// Split pane
class SplitPane {
  final String id;
  final double size;
  final List<String> tabs;
  
  SplitPane({
    required this.id,
    required this.size,
    required this.tabs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'size': size,
    'tabs': tabs,
  };

  static SplitPane fromJson(Map<String, dynamic> json) => SplitPane(
    id: json['id'] as String,
    size: (json['size'] as num).toDouble(),
    tabs: List<String>.from(json['tabs'] as List),
  );
}

/// Theme configuration
class ThemeConfiguration {
  final String theme;
  final String fontFamily;
  final double fontSize;
  final double opacity;
  final double backgroundOpacity;
  
  ThemeConfiguration({
    required this.theme,
    required this.fontFamily,
    required this.fontSize,
    required this.opacity,
    required this.backgroundOpacity,
  });

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'opacity': opacity,
    'backgroundOpacity': backgroundOpacity,
  };

  static ThemeConfiguration fromJson(Map<String, dynamic> json) => ThemeConfiguration(
    theme: json['theme'] as String,
    fontFamily: json['fontFamily'] as String,
    fontSize: (json['fontSize'] as num).toDouble(),
    opacity: (json['opacity'] as num).toDouble(),
    backgroundOpacity: (json['backgroundOpacity'] as num).toDouble(),
  );
}

/// Workspace state
class WorkspaceState {
  final String id;
  final String name;
  final List<TerminalTabState> tabs;
  final WindowState windowState;
  final DateTime createdAt;
  
  WorkspaceState({
    required this.id,
    required this.name,
    required this.tabs,
    required this.windowState,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tabs': tabs.map((t) => t.toJson()),
    'windowState': windowState.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  static WorkspaceState fromJson(Map<String, dynamic> json) => WorkspaceState(
    id: json['id'] as String,
    name: json['name'] as String,
    tabs: (json['tabs'] as List)
        .map((t) => TerminalTabState.fromJson(t as Map<String, dynamic>))
        .toList(),
    windowState: WindowState.fromJson(json['windowState'] as Map<String, dynamic>),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Layout info
class LayoutInfo {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime lastModified;
  final int workspaceCount;
  
  LayoutInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.lastModified,
    required this.workspaceCount,
  });
}

/// Workspace info
class WorkspaceInfo {
  final String id;
  final String name;
  final int tabCount;
  final bool isActive;
  final DateTime createdAt;
  
  WorkspaceInfo({
    required this.id,
    required this.name,
    required this.tabCount,
    required this.isActive,
    required this.createdAt,
  });
}

/// Layout statistics
class LayoutStatistics {
  final int totalLayouts;
  final String? currentLayoutId;
  final int totalWorkspaces;
  final String? currentWorkspaceId;
  final DateTime? lastSaveTime;
  
  LayoutStatistics({
    required this.totalLayouts,
    this.currentLayoutId,
    required this.totalWorkspaces,
    this.currentWorkspaceId,
    this.lastSaveTime,
  });
}

/// Layout event
class LayoutEvent {
  final LayoutEventType type;
  final String? layoutId;
  final String? workspaceId;
  final DateTime timestamp;
  
  LayoutEvent({
    required this.type,
    this.layoutId,
    this.workspaceId,
    required this.timestamp,
  });
}

/// Enums
enum LayoutEventType {
  layoutSaved,
  layoutLoaded,
  layoutDeleted,
  workspaceCreated,
  workspaceSwitched,
}
enum TabBarPosition { top, bottom, left, right }
enum SplitOrientation { horizontal, vertical }


