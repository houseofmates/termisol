import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

class AdvancedTerminalMultiplexing {
  static const String _layoutsFile = '/home/house/.termisol_multiplex_layouts.json';
  static const int _maxSessions = 50;
  static const int _maxPanes = 200;
  
  final Map<String, MultiplexSession> _sessions = {};
  final Map<String, Layout> _layouts = {};
  final Map<String, List<Pane>> _sessionPanes = {};
  final Map<String, FocusManager> _focusManagers = {};
  
  Timer? _layoutUpdateTimer;
  String? _currentSession;
  String? _currentLayout;
  int _totalSessions = 0;
  int _totalPanes = 0;
  
  final StreamController<MultiplexEvent> _multiplexController = 
      StreamController<MultiplexEvent>.broadcast();

  void initialize() {
    _loadLayouts();
    _initializeDefaultLayouts();
    _startLayoutUpdateTimer();
    developer.log('🪟 Advanced Terminal Multiplexing initialized');
  }

  void _loadLayouts() {
    try {
      final file = File(_layoutsFile);
      if (!file.existsSync()) {
        developer.log('🪟 No existing layouts file found');
        return;
      }
      
      final content = file.readAsStringSync();
      final data = jsonDecode(content);
      
      for (final entry in data['layouts']) {
        final layout = Layout.fromJson(entry);
        _layouts[layout.id] = layout;
      }
      
      developer.log('🪟 Loaded ${_layouts.length} layouts');
      
    } catch (e) {
      developer.log('🪟 Failed to load layouts: $e');
    }
  }

  void _initializeDefaultLayouts() {
    if (_layouts.isEmpty) {
      // Grid layout
      _layouts['grid_2x2'] = Layout(
        id: 'grid_2x2',
        name: '2x2 Grid',
        description: '2 rows x 2 columns grid layout',
        type: LayoutType.grid,
        config: {
          'rows': 2,
          'columns': 2,
          'gap': 1,
          'border_width': 1,
        },
        createdAt: DateTime.now(),
        isDefault: true,
      );
      
      // Grid 3x3 layout
      _layouts['grid_3x3'] = Layout(
        id: 'grid_3x3',
        name: '3x3 Grid',
        description: '3 rows x 3 columns grid layout',
        type: LayoutType.grid,
        config: {
          'rows': 3,
          'columns': 3,
          'gap': 1,
          'border_width': 1,
        },
        createdAt: DateTime.now(),
        isDefault: true,
      );
      
      // Horizontal stack layout
      _layouts['horizontal_stack'] = Layout(
        id: 'horizontal_stack',
        name: 'Horizontal Stack',
        description: 'Horizontal stacked panes',
        type: LayoutType.horizontal,
        config: {
          'orientation': 'horizontal',
          'equal_size': true,
          'gap': 1,
          'border_width': 1,
        },
        createdAt: DateTime.now(),
        isDefault: true,
      );
      
      // Vertical stack layout
      _layouts['vertical_stack'] = Layout(
        id: 'vertical_stack',
        name: 'Vertical Stack',
        description: 'Vertical stacked panes',
        type: LayoutType.vertical,
        config: {
          'orientation': 'vertical',
          'equal_size': true,
          'gap': 1,
          'border_width': 1,
        },
        createdAt: DateTime.now(),
        isDefault: true,
      );
      
      // Main + sidebar layout
      _layouts['main_sidebar'] = Layout(
        id: 'main_sidebar',
        name: 'Main + Sidebar',
        description: 'Main pane with sidebar',
        type: LayoutType.mainSidebar,
        config: {
          'main_ratio': 0.7,
          'sidebar_position': 'right',
          'gap': 1,
          'border_width': 1,
        },
        createdAt: DateTime.now(),
        isDefault: true,
      );
      
      // Tiled layout
      _layouts['tiled'] = Layout(
        id: 'tiled',
        name: 'Tiled',
        description: 'Automatic tiling layout',
        type: LayoutType.tiled,
        config: {
          'algorithm': 'spiral',
          'gap': 1,
          'border_width': 1,
          'min_pane_size': 10,
        },
        createdAt: DateTime.now(),
        isDefault: true,
      );
      
      _saveLayouts();
    }
  }

  void _startLayoutUpdateTimer() {
    _layoutUpdateTimer = Timer.periodic(
      Duration(milliseconds: 16), // ~60 FPS
      (_) => _updateLayouts(),
    );
  }

  Future<String> createSession({
    required String name,
    String? layoutId,
    Map<String, dynamic>? config,
  }) async {
    if (_sessions.length >= _maxSessions) {
      throw Exception('Maximum sessions reached: $_maxSessions');
    }
    
    final sessionId = _generateSessionId();
    final layout = _layouts[layoutId ?? 'grid_2x2'] ?? _layouts.values.first;
    
    final session = MultiplexSession(
      id: sessionId,
      name: name,
      layoutId: layout.id,
      config: config ?? {},
      panes: [],
      activePaneId: null,
      createdAt: DateTime.now(),
      lastModified: DateTime.now(),
      isActive: false,
    );
    
    _sessions[sessionId] = session;
    _sessionPanes[sessionId] = [];
    _focusManagers[sessionId] = FocusManager(sessionId: sessionId);
    _totalSessions++;
    
    developer.log('🪟 Created multiplex session: $name');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.sessionCreated,
      sessionId: sessionId,
      sessionName: name,
      layoutId: layout.id,
    ));
    
    await _saveSessions();
    
    return sessionId;
  }

  Future<String> addPane({
    required String sessionId,
    String? command,
    String? workingDirectory,
    PaneType? type,
    Map<String, dynamic>? config,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final panes = _sessionPanes[sessionId]!;
    if (panes.length >= _maxPanes) {
      throw Exception('Maximum panes reached: $_maxPanes');
    }
    
    final paneId = _generatePaneId();
    final pane = Pane(
      id: paneId,
      sessionId: sessionId,
      type: type ?? PaneType.terminal,
      command: command ?? 'bash',
      workingDirectory: workingDirectory ?? Directory.current.path,
      config: config ?? {},
      isActive: true,
      isVisible: true,
      position: PanePosition(
        x: 0,
        y: 0,
        width: 80,
        height: 24,
      ),
      process: null,
      buffer: '',
      scrollback: [],
      cursor: CursorPosition(x: 0, y: 0),
      createdAt: DateTime.now(),
      lastActivity: DateTime.now(),
    );
    
    panes.add(pane);
    _totalPanes++;
    
    // Update session
    session.panes = panes.map((p) => p.id).toList();
    session.lastModified = DateTime.now();
    
    if (session.activePaneId == null) {
      session.activePaneId = paneId;
    }
    
    // Recalculate layout
    await _recalculateLayout(sessionId);
    
    developer.log('🪟 Added pane to session: $sessionId');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.paneCreated,
      sessionId: sessionId,
      paneId: paneId,
      paneType: pane.type,
    ));
    
    await _saveSessions();
    
    return paneId;
  }

  Future<void> splitPane({
    required String sessionId,
    required String paneId,
    SplitDirection direction,
    double? ratio,
  }) async {
    final session = _sessions[sessionId];
    final panes = _sessionPanes[sessionId];
    
    if (session == null || panes == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final originalPane = panes.firstWhere((p) => p.id == paneId);
    if (originalPane == null) {
      throw Exception('Pane not found: $paneId');
    }
    
    final splitRatio = ratio ?? 0.5;
    
    // Create two new panes
    final newPane1Id = await addPane(
      sessionId: sessionId,
      command: originalPane.command,
      workingDirectory: originalPane.workingDirectory,
      type: originalPane.type,
      config: Map.from(originalPane.config),
    );
    
    final newPane2Id = await addPane(
      sessionId: sessionId,
      command: originalPane.command,
      workingDirectory: originalPane.workingDirectory,
      type: originalPane.type,
      config: Map.from(originalPane.config),
    );
    
    final newPane1 = panes.firstWhere((p) => p.id == newPane1Id);
    final newPane2 = panes.firstWhere((p) => p.id == newPane2Id);
    
    // Calculate new positions based on split direction
    final originalPos = originalPane.position;
    
    switch (direction) {
      case SplitDirection.horizontal:
        newPane1.position = PanePosition(
          x: originalPos.x,
          y: originalPos.y,
          width: (originalPos.width * splitRatio).round(),
          height: originalPos.height,
        );
        newPane2.position = PanePosition(
          x: originalPos.x + (originalPos.width * splitRatio).round(),
          y: originalPos.y,
          width: (originalPos.width * (1 - splitRatio)).round(),
          height: originalPos.height,
        );
        break;
        
      case SplitDirection.vertical:
        newPane1.position = PanePosition(
          x: originalPos.x,
          y: originalPos.y,
          width: originalPos.width,
          height: (originalPos.height * splitRatio).round(),
        );
        newPane2.position = PanePosition(
          x: originalPos.x,
          y: originalPos.y + (originalPos.height * splitRatio).round(),
          width: originalPos.width,
          height: (originalPos.height * (1 - splitRatio)).round(),
        );
        break;
    }
    
    // Remove original pane
    await removePane(sessionId: sessionId, paneId: paneId);
    
    // Update active pane if needed
    if (session.activePaneId == paneId) {
      session.activePaneId = newPane1Id;
    }
    
    developer.log('🪟 Split pane: $paneId -> $newPane1Id, $newPane2Id');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.paneSplit,
      sessionId: sessionId,
      originalPaneId: paneId,
      newPaneIds: [newPane1Id, newPane2Id],
      direction: direction,
    ));
    
    await _saveSessions();
  }

  Future<void> removePane({
    required String sessionId,
    required String paneId,
  }) async {
    final session = _sessions[sessionId];
    final panes = _sessionPanes[sessionId];
    
    if (session == null || panes == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final pane = panes.firstWhere((p) => p.id == paneId);
    if (pane == null) {
      throw Exception('Pane not found: $paneId');
    }
    
    // Terminate pane process if running
    if (pane.process != null) {
      pane.process!.kill();
    }
    
    panes.removeWhere((p) => p.id == paneId);
    _totalPanes--;
    
    // Update session
    session.panes = panes.map((p) => p.id).toList();
    session.lastModified = DateTime.now();
    
    // Update active pane if needed
    if (session.activePaneId == paneId) {
      session.activePaneId = panes.isNotEmpty ? panes.first.id : null;
    }
    
    // Recalculate layout
    await _recalculateLayout(sessionId);
    
    developer.log('🪟 Removed pane: $paneId from session: $sessionId');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.paneRemoved,
      sessionId: sessionId,
      paneId: paneId,
    ));
    
    await _saveSessions();
  }

  Future<void> switchLayout({
    required String sessionId,
    required String layoutId,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final layout = _layouts[layoutId];
    if (layout == null) {
      throw Exception('Layout not found: $layoutId');
    }
    
    session.layoutId = layoutId;
    session.lastModified = DateTime.now();
    
    await _recalculateLayout(sessionId);
    
    developer.log('🪟 Switched layout: $sessionId -> $layoutId');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.layoutSwitched,
      sessionId: sessionId,
      oldLayoutId: session.layoutId,
      newLayoutId: layoutId,
    ));
    
    await _saveSessions();
  }

  Future<void> focusPane({
    required String sessionId,
    required String paneId,
  }) async {
    final session = _sessions[sessionId];
    final focusManager = _focusManagers[sessionId];
    
    if (session == null || focusManager == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    session.activePaneId = paneId;
    session.lastModified = DateTime.now();
    
    focusManager!.setFocusedPane(paneId);
    
    developer.log('🪟 Focused pane: $paneId in session: $sessionId');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.paneFocused,
      sessionId: sessionId,
      paneId: paneId,
    ));
    
    await _saveSessions();
  }

  Future<void> resizePane({
    required String sessionId,
    required String paneId,
    required int width,
    required int height,
  }) async {
    final panes = _sessionPanes[sessionId];
    if (panes == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final pane = panes.firstWhere((p) => p.id == paneId);
    if (pane == null) {
      throw Exception('Pane not found: $paneId');
    }
    
    pane.position.width = width;
    pane.position.height = height;
    pane.lastActivity = DateTime.now();
    
    developer.log('🪟 Resized pane: $paneId to ${width}x$height');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.paneResized,
      sessionId: sessionId,
      paneId: paneId,
      width: width,
      height: height,
    ));
    
    await _saveSessions();
  }

  Future<void> movePane({
    required String sessionId,
    required String paneId,
    required int x,
    required int y,
  }) async {
    final panes = _sessionPanes[sessionId];
    if (panes == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final pane = panes.firstWhere((p) => p.id == paneId);
    if (pane == null) {
      throw Exception('Pane not found: $paneId');
    }
    
    pane.position.x = x;
    pane.position.y = y;
    pane.lastActivity = DateTime.now();
    
    developer.log('🪟 Moved pane: $paneId to ($x, $y)');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.paneMoved,
      sessionId: sessionId,
      paneId: paneId,
      x: x,
      y: y,
    ));
    
    await _saveSessions();
  }

  Future<void> swapPanes({
    required String sessionId,
    required String pane1Id,
    required String pane2Id,
  }) async {
    final panes = _sessionPanes[sessionId];
    if (panes == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    final pane1 = panes.firstWhere((p) => p.id == pane1Id);
    final pane2 = panes.firstWhere((p) => p.id == pane2Id);
    
    if (pane1 == null || pane2 == null) {
      throw Exception('Pane not found: $pane1Id or $pane2Id');
    }
    
    // Swap positions
    final tempPos = pane1.position;
    pane1.position = pane2.position;
    pane2.position = tempPos;
    
    pane1.lastActivity = DateTime.now();
    pane2.lastActivity = DateTime.now();
    
    developer.log('🪟 Swapped panes: $pane1Id <-> $pane2Id');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.panesSwapped,
      sessionId: sessionId,
      pane1Id: pane1Id,
      pane2Id: pane2Id,
    ));
    
    await _saveSessions();
  }

  Future<void> _recalculateLayout(String sessionId) async {
    final session = _sessions[sessionId];
    final panes = _sessionPanes[sessionId];
    final layout = _layouts[session!.layoutId];
    
    if (session == null || panes == null || layout == null) {
      return;
    }
    
    switch (layout.type) {
      case LayoutType.grid:
        _applyGridLayout(panes, layout.config);
        break;
      case LayoutType.horizontal:
        _applyHorizontalLayout(panes, layout.config);
        break;
      case LayoutType.vertical:
        _applyVerticalLayout(panes, layout.config);
        break;
      case LayoutType.mainSidebar:
        _applyMainSidebarLayout(panes, layout.config);
        break;
      case LayoutType.tiled:
        _applyTiledLayout(panes, layout.config);
        break;
    }
  }

  void _applyGridLayout(List<Pane> panes, Map<String, dynamic> config) {
    final rows = config['rows'] as int? ?? 2;
    final columns = config['columns'] as int? ?? 2;
    final gap = config['gap'] as int? ?? 1;
    final borderWidth = config['border_width'] as int? ?? 1;
    
    final totalWidth = 1920; // Assume full screen width
    final totalHeight = 1080; // Assume full screen height
    
    final paneWidth = (totalWidth - (columns - 1) * gap - 2 * borderWidth) ~/ columns;
    final paneHeight = (totalHeight - (rows - 1) * gap - 2 * borderWidth) ~/ rows;
    
    for (int i = 0; i < panes.length && i < rows * columns; i++) {
      final row = i ~/ columns;
      final col = i % columns;
      
      panes[i].position = PanePosition(
        x: col * (paneWidth + gap) + borderWidth,
        y: row * (paneHeight + gap) + borderWidth,
        width: paneWidth,
        height: paneHeight,
      );
    }
  }

  void _applyHorizontalLayout(List<Pane> panes, Map<String, dynamic> config) {
    final equalSize = config['equal_size'] as bool? ?? true;
    final gap = config['gap'] as int? ?? 1;
    final borderWidth = config['border_width'] as int? ?? 1;
    
    final totalWidth = 1920;
    final totalHeight = 1080;
    
    if (equalSize) {
      final paneWidth = (totalWidth - (panes.length - 1) * gap - 2 * borderWidth) ~/ panes.length;
      
      for (int i = 0; i < panes.length; i++) {
        panes[i].position = PanePosition(
          x: i * (paneWidth + gap) + borderWidth,
          y: borderWidth,
          width: paneWidth,
          height: totalHeight - 2 * borderWidth,
        );
      }
    } else {
      // Implement proportional sizing based on content
      final totalWeight = panes.fold(0.0, (sum, pane) => sum + (pane.config['weight'] as double? ?? 1.0));
      
      var currentX = borderWidth;
      for (int i = 0; i < panes.length; i++) {
        final weight = panes[i].config['weight'] as double? ?? 1.0;
        final paneWidth = ((totalWidth - (panes.length - 1) * gap - 2 * borderWidth) * weight / totalWeight).round();
        
        panes[i].position = PanePosition(
          x: currentX,
          y: borderWidth,
          width: paneWidth,
          height: totalHeight - 2 * borderWidth,
        );
        
        currentX += paneWidth + gap;
      }
    }
  }

  void _applyVerticalLayout(List<Pane> panes, Map<String, dynamic> config) {
    final equalSize = config['equal_size'] as bool? ?? true;
    final gap = config['gap'] as int? ?? 1;
    final borderWidth = config['border_width'] as int? ?? 1;
    
    final totalWidth = 1920;
    final totalHeight = 1080;
    
    if (equalSize) {
      final paneHeight = (totalHeight - (panes.length - 1) * gap - 2 * borderWidth) ~/ panes.length;
      
      for (int i = 0; i < panes.length; i++) {
        panes[i].position = PanePosition(
          x: borderWidth,
          y: i * (paneHeight + gap) + borderWidth,
          width: totalWidth - 2 * borderWidth,
          height: paneHeight,
        );
      }
    } else {
      // Implement proportional sizing
      final totalWeight = panes.fold(0.0, (sum, pane) => sum + (pane.config['weight'] as double? ?? 1.0));
      
      var currentY = borderWidth;
      for (int i = 0; i < panes.length; i++) {
        final weight = panes[i].config['weight'] as double? ?? 1.0;
        final paneHeight = ((totalHeight - (panes.length - 1) * gap - 2 * borderWidth) * weight / totalWeight).round();
        
        panes[i].position = PanePosition(
          x: borderWidth,
          y: currentY,
          width: totalWidth - 2 * borderWidth,
          height: paneHeight,
        );
        
        currentY += paneHeight + gap;
      }
    }
  }

  void _applyMainSidebarLayout(List<Pane> panes, Map<String, dynamic> config) {
    final mainRatio = config['main_ratio'] as double? ?? 0.7;
    final sidebarPosition = config['sidebar_position'] as String? ?? 'right';
    final gap = config['gap'] as int? ?? 1;
    final borderWidth = config['border_width'] as int? ?? 1;
    
    final totalWidth = 1920;
    final totalHeight = 1080;
    
    if (panes.isEmpty) return;
    
    // First pane is main, rest are sidebar
    final mainPane = panes[0];
    final sidebarPanes = panes.skip(1).toList();
    
    if (sidebarPosition == 'right') {
      final mainWidth = ((totalWidth - gap - 2 * borderWidth) * mainRatio).round();
      final sidebarWidth = totalWidth - mainWidth - gap - 2 * borderWidth;
      
      mainPane.position = PanePosition(
        x: borderWidth,
        y: borderWidth,
        width: mainWidth,
        height: totalHeight - 2 * borderWidth,
      );
      
      if (sidebarPanes.isNotEmpty) {
        final sidebarPaneHeight = (totalHeight - (sidebarPanes.length - 1) * gap - 2 * borderWidth) ~/ sidebarPanes.length;
        
        for (int i = 0; i < sidebarPanes.length; i++) {
          sidebarPanes[i].position = PanePosition(
            x: mainWidth + gap + borderWidth,
            y: i * (sidebarPaneHeight + gap) + borderWidth,
            width: sidebarWidth,
            height: sidebarPaneHeight,
          );
        }
      }
    } else {
      // Left sidebar
      final sidebarWidth = ((totalWidth - gap - 2 * borderWidth) * (1 - mainRatio)).round();
      final mainWidth = totalWidth - sidebarWidth - gap - 2 * borderWidth;
      
      if (sidebarPanes.isNotEmpty) {
        final sidebarPaneHeight = (totalHeight - (sidebarPanes.length - 1) * gap - 2 * borderWidth) ~/ sidebarPanes.length;
        
        for (int i = 0; i < sidebarPanes.length; i++) {
          sidebarPanes[i].position = PanePosition(
            x: borderWidth,
            y: i * (sidebarPaneHeight + gap) + borderWidth,
            width: sidebarWidth,
            height: sidebarPaneHeight,
          );
        }
      }
      
      mainPane.position = PanePosition(
        x: sidebarWidth + gap + borderWidth,
        y: borderWidth,
        width: mainWidth,
        height: totalHeight - 2 * borderWidth,
      );
    }
  }

  void _applyTiledLayout(List<Pane> panes, Map<String, dynamic> config) {
    final algorithm = config['algorithm'] as String? ?? 'spiral';
    final gap = config['gap'] as int? ?? 1;
    final borderWidth = config['border_width'] as int? ?? 1;
    final minPaneSize = config['min_pane_size'] as int? ?? 10;
    
    final totalWidth = 1920;
    final totalHeight = 1080;
    
    switch (algorithm) {
      case 'spiral':
        _applySpiralTiling(panes, gap, borderWidth, minPaneSize, totalWidth, totalHeight);
        break;
      case 'grid':
        _applyGridTiling(panes, gap, borderWidth, totalWidth, totalHeight);
        break;
      case 'binary':
        _applyBinaryTiling(panes, gap, borderWidth, totalWidth, totalHeight);
        break;
    }
  }

  void _applySpiralTiling(List<Pane> panes, int gap, int borderWidth, int minPaneSize, int totalWidth, int totalHeight) {
    final usableWidth = totalWidth - 2 * borderWidth;
    final usableHeight = totalHeight - 2 * borderWidth;
    
    int x = borderWidth;
    int y = borderWidth;
    int currentWidth = usableWidth;
    int currentHeight = usableHeight;
    
    for (int i = 0; i < panes.length; i++) {
      final paneWidth = math.max(minPaneSize, currentWidth ~/ (panes.length - i));
      final paneHeight = math.max(minPaneSize, currentHeight ~/ math.max(1, (panes.length - i) ~/ 2));
      
      panes[i].position = PanePosition(
        x: x,
        y: y,
        width: paneWidth,
        height: paneHeight,
      );
      
      // Spiral to next position
      if (i % 4 == 0) {
        x += paneWidth + gap;
        currentWidth -= paneWidth + gap;
      } else if (i % 4 == 1) {
        y += paneHeight + gap;
        currentHeight -= paneHeight + gap;
      } else if (i % 4 == 2) {
        x -= paneWidth + gap;
        currentWidth += paneWidth + gap;
      } else {
        y -= paneHeight + gap;
        currentHeight += paneHeight + gap;
      }
    }
  }

  void _applyGridTiling(List<Pane> panes, int gap, int borderWidth, int totalWidth, int totalHeight) {
    final columns = math.ceil(math.sqrt(panes.length));
    final rows = math.ceil(panes.length / columns);
    
    final paneWidth = (totalWidth - (columns - 1) * gap - 2 * borderWidth) ~/ columns;
    final paneHeight = (totalHeight - (rows - 1) * gap - 2 * borderWidth) ~/ rows;
    
    for (int i = 0; i < panes.length; i++) {
      final row = i ~/ columns;
      final col = i % columns;
      
      panes[i].position = PanePosition(
        x: col * (paneWidth + gap) + borderWidth,
        y: row * (paneHeight + gap) + borderWidth,
        width: paneWidth,
        height: paneHeight,
      );
    }
  }

  void _applyBinaryTiling(List<Pane> panes, int gap, int borderWidth, int totalWidth, int totalHeight) {
    // Simple binary tree tiling
    if (panes.isEmpty) return;
    
    _applyBinaryTilingRecursive(panes, 0, borderWidth, borderWidth, totalWidth - 2 * borderWidth, totalHeight - 2 * borderWidth, gap);
  }

  void _applyBinaryTilingRecursive(List<Pane> panes, int startIndex, int x, int y, int width, int height, int gap) {
    if (startIndex >= panes.length) return;
    
    if (startIndex == panes.length - 1) {
      // Last pane takes remaining space
      panes[startIndex].position = PanePosition(x: x, y: y, width: width, height: height);
      return;
    }
    
    // Split current space
    final midIndex = startIndex + (panes.length - startIndex) ~/ 2;
    
    if (width > height) {
      // Split vertically
      final leftWidth = width ~/ 2;
      _applyBinaryTilingRecursive(panes, startIndex, x, y, leftWidth, height, gap);
      _applyBinaryTilingRecursive(panes, midIndex, x + leftWidth + gap, y, width - leftWidth - gap, height, gap);
    } else {
      // Split horizontally
      final topHeight = height ~/ 2;
      _applyBinaryTilingRecursive(panes, startIndex, x, y, width, topHeight, gap);
      _applyBinaryTilingRecursive(panes, midIndex, x, y + topHeight + gap, width, height - topHeight - gap, gap);
    }
  }

  void _updateLayouts() {
    // Update all active sessions
    for (final session in _sessions.values) {
      if (session.isActive) {
        _recalculateLayout(session.id);
      }
    }
  }

  Future<String> createLayout({
    required String name,
    required LayoutType type,
    required Map<String, dynamic> config,
    String? description,
  }) async {
    final layoutId = _generateLayoutId();
    
    final layout = Layout(
      id: layoutId,
      name: name,
      description: description ?? '',
      type: type,
      config: config,
      createdAt: DateTime.now(),
      isDefault: false,
    );
    
    _layouts[layoutId] = layout;
    
    developer.log('🪟 Created layout: $name');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.layoutCreated,
      layoutId: layoutId,
      layoutName: name,
      layoutType: type,
    ));
    
    await _saveLayouts();
    
    return layoutId;
  }

  Future<void> deleteLayout(String layoutId) async {
    final layout = _layouts.remove(layoutId);
    if (layout == null) {
      throw Exception('Layout not found: $layoutId');
    }
    
    if (layout.isDefault) {
      throw Exception('Cannot delete default layout');
    }
    
    developer.log('🪟 Deleted layout: $layoutId');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.layoutDeleted,
      layoutId: layoutId,
    ));
    
    await _saveLayouts();
  }

  Future<void> setActiveSession(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }
    
    // Deactivate previous session
    if (_currentSession != null) {
      final prevSession = _sessions[_currentSession!];
      if (prevSession != null) {
        prevSession.isActive = false;
      }
    }
    
    // Activate new session
    session.isActive = true;
    _currentSession = sessionId;
    
    developer.log('🪟 Set active session: $sessionId');
    
    _emitEvent(MultiplexEvent(
      type: MultiplexEventType.sessionActivated,
      sessionId: sessionId,
    ));
    
    await _saveSessions();
  }

  Future<void> _saveSessions() async {
    try {
      final file = File('${_layoutsFile}.sessions');
      
      final sessionsData = _sessions.values.map((session) => session.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'sessions': sessionsData,
        'current_session': _currentSession,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🪟 Failed to save sessions: $e');
    }
  }

  Future<void> _saveLayouts() async {
    try {
      final file = File(_layoutsFile);
      
      final layoutsData = _layouts.values.map((layout) => layout.toJson()).toList();
      
      final data = {
        'version': '1.0',
        'saved_at': DateTime.now().toIso8601String(),
        'layouts': layoutsData,
      };
      
      await file.writeAsString(jsonEncode(data));
      
    } catch (e) {
      developer.log('🪟 Failed to save layouts: $e');
    }
  }

  MultiplexSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  List<MultiplexSession> getSessions() {
    return _sessions.values.toList();
  }

  List<Pane> getPanes(String sessionId) {
    return _sessionPanes[sessionId] ?? [];
  }

  Layout? getLayout(String layoutId) {
    return _layouts[layoutId];
  }

  List<Layout> getLayouts() {
    return _layouts.values.toList();
  }

  String? getCurrentSession() {
    return _currentSession;
  }

  String? getCurrentLayout() {
    return _currentLayout;
  }

  MultiplexStats getStats() {
    return MultiplexStats(
      totalSessions: _totalSessions,
      activeSessions: _sessions.values.where((s) => s.isActive).length,
      totalPanes: _totalPanes,
      totalLayouts: _layouts.length,
      defaultLayouts: _layouts.values.where((l) => l.isDefault).length,
      customLayouts: _layouts.values.where((l) => !l.isDefault).length,
    );
  }

  String _generateSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_$_totalSessions';
  }

  String _generatePaneId() {
    return 'pane_${DateTime.now().millisecondsSinceEpoch}_$_totalPanes';
  }

  String _generateLayoutId() {
    return 'layout_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(MultiplexEvent event) {
    _multiplexController.add(event);
  }

  Stream<MultiplexEvent> get multiplexEventStream => _multiplexController.stream;

  void dispose() {
    _layoutUpdateTimer?.cancel();
    
    // Terminate all pane processes
    for (final panes in _sessionPanes.values) {
      for (final pane in panes) {
        if (pane.process != null) {
          pane.process!.kill();
        }
      }
    }
    
    _sessions.clear();
    _layouts.clear();
    _sessionPanes.clear();
    _focusManagers.clear();
    _multiplexController.close();
    
    developer.log('🪟 Advanced Terminal Multiplexing disposed');
  }
}

class MultiplexSession {
  final String id;
  final String name;
  String layoutId;
  final Map<String, dynamic> config;
  List<String> panes;
  String? activePaneId;
  final DateTime createdAt;
  DateTime lastModified;
  bool isActive;

  MultiplexSession({
    required this.id,
    required this.name,
    required this.layoutId,
    required this.config,
    required this.panes,
    this.activePaneId,
    required this.createdAt,
    required this.lastModified,
    required this.isActive,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'layout_id': layoutId,
      'config': config,
      'panes': panes,
      'active_pane_id': activePaneId,
      'created_at': createdAt.toIso8601String(),
      'last_modified': lastModified.toIso8601String(),
      'is_active': isActive,
    };
  }

  factory MultiplexSession.fromJson(Map<String, dynamic> json) {
    return MultiplexSession(
      id: json['id'],
      name: json['name'],
      layoutId: json['layout_id'],
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      panes: List<String>.from(json['panes'] ?? []),
      activePaneId: json['active_pane_id'],
      createdAt: DateTime.parse(json['created_at']),
      lastModified: DateTime.parse(json['last_modified']),
      isActive: json['is_active'] ?? false,
    );
  }
}

class Layout {
  final String id;
  final String name;
  final String description;
  final LayoutType type;
  final Map<String, dynamic> config;
  final DateTime createdAt;
  final bool isDefault;

  Layout({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.config,
    required this.createdAt,
    required this.isDefault,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'config': config,
      'created_at': createdAt.toIso8601String(),
      'is_default': isDefault,
    };
  }

  factory Layout.fromJson(Map<String, dynamic> json) {
    return Layout(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: LayoutType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => LayoutType.grid,
      ),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
      isDefault: json['is_default'] ?? false,
    );
  }
}

class Pane {
  final String id;
  final String sessionId;
  final PaneType type;
  final String command;
  final String workingDirectory;
  final Map<String, dynamic> config;
  bool isActive;
  bool isVisible;
  PanePosition position;
  Process? process;
  String buffer;
  final List<String> scrollback;
  CursorPosition cursor;
  final DateTime createdAt;
  DateTime lastActivity;

  Pane({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.command,
    required this.workingDirectory,
    required this.config,
    required this.isActive,
    required this.isVisible,
    required this.position,
    this.process,
    required this.buffer,
    required this.scrollback,
    required this.cursor,
    required this.createdAt,
    required this.lastActivity,
  });
}

class PanePosition {
  final int x;
  final int y;
  final int width;
  final int height;

  PanePosition({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class CursorPosition {
  final int x;
  final int y;

  CursorPosition({
    required this.x,
    required this.y,
  });
}

class FocusManager {
  final String sessionId;
  String? focusedPaneId;
  final List<String> focusHistory = [];

  FocusManager({
    required this.sessionId,
  });

  void setFocusedPane(String paneId) {
    focusedPaneId = paneId;
    focusHistory.remove(paneId);
    focusHistory.add(paneId);
    
    // Keep history limited
    if (focusHistory.length > 50) {
      focusHistory.removeAt(0);
    }
  }

  String? getPreviousPane() {
    if (focusHistory.length < 2) return null;
    return focusHistory[focusHistory.length - 2];
  }

  List<String> getFocusHistory() {
    return List.from(focusHistory);
  }
}

enum LayoutType {
  grid,
  horizontal,
  vertical,
  mainSidebar,
  tiled,
}

enum PaneType {
  terminal,
  editor,
  browser,
  custom,
}

enum SplitDirection {
  horizontal,
  vertical,
}

enum MultiplexEventType {
  sessionCreated,
  sessionActivated,
  sessionDeleted,
  layoutCreated,
  layoutSwitched,
  layoutDeleted,
  paneCreated,
  paneFocused,
  paneSplit,
  paneRemoved,
  paneResized,
  paneMoved,
  panesSwapped,
}

class MultiplexEvent {
  final MultiplexEventType type;
  final String? sessionId;
  final String? sessionName;
  final String? layoutId;
  final String? layoutName;
  final LayoutType? layoutType;
  final String? oldLayoutId;
  final String? newLayoutId;
  final String? paneId;
  final PaneType? paneType;
  final List<String>? newPaneIds;
  final SplitDirection? direction;
  final int? width;
  final int? height;
  final int? x;
  final int? y;
  final String? pane1Id;
  final String? pane2Id;

  MultiplexEvent({
    required this.type,
    this.sessionId,
    this.sessionName,
    this.layoutId,
    this.layoutName,
    this.layoutType,
    this.oldLayoutId,
    this.newLayoutId,
    this.paneId,
    this.paneType,
    this.newPaneIds,
    this.direction,
    this.width,
    this.height,
    this.x,
    this.y,
    this.pane1Id,
    this.pane2Id,
  });
}

class MultiplexStats {
  final int totalSessions;
  final int activeSessions;
  final int totalPanes;
  final int totalLayouts;
  final int defaultLayouts;
  final int customLayouts;

  MultiplexStats({
    required this.totalSessions,
    required this.activeSessions,
    required this.totalPanes,
    required this.totalLayouts,
    required this.defaultLayouts,
    required this.customLayouts,
  });
}
