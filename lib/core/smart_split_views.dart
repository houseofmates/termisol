import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

class SmartSplitViews {
  static const int _maxViews = 4;
  static const int _minViewSize = 200; // pixels
  static const int _defaultViewSize = 400; // pixels
  static const int _handleSize = 8; // pixels
  
  final List<SplitView> _views = [];
  final List<SplitLayout> _layoutHistory = [];
  final Map<String, ViewProfile> _viewProfiles = {};
  
  bool _isDragging = false;
  String? _activeViewId;
  String? _draggedHandleId;
  double _dragStartX = 0;
  double _dragStartY = 0;
  
  final StreamController<SplitViewEvent> _splitEventController = 
      StreamController<SplitViewEvent>.broadcast();

  void initialize() {
    _initializeDefaultLayout();
    developer.log('🪟 Smart Split Views initialized');
  }

  void _initializeDefaultLayout() {
    // Create default 2x2 layout
    _views.addAll([
      SplitView(
        id: 'view_1',
        x: 0,
        y: 0,
        width: _defaultViewSize,
        height: _defaultViewSize,
        content: 'terminal',
        isActive: true,
      ),
      SplitView(
        id: 'view_2',
        x: _defaultViewSize + _handleSize,
        y: 0,
        width: _defaultViewSize,
        height: _defaultViewSize,
        content: 'file_manager',
        isActive: false,
      ),
    ]);
    
    _activeViewId = 'view_1';
  }

  String createView({
    String? content,
    double? x,
    double? y,
    double? width,
    double? height,
    ViewLayout layout = ViewLayout.single,
  }) {
    if (_views.length >= _maxViews) {
      throw Exception('Maximum views reached');
    }
    
    final viewId = _generateViewId();
    
    // Calculate position if not specified
    final calculatedPosition = _calculateOptimalPosition(layout, x, y, width, height);
    
    final view = SplitView(
      id: viewId,
      x: calculatedPosition.x,
      y: calculatedPosition.y,
      width: calculatedPosition.width ?? _defaultViewSize,
      height: calculatedPosition.height ?? _defaultViewSize,
      content: content ?? 'terminal',
      isActive: false,
      layout: layout,
    );
    
    _views.add(view);
    _adjustOtherViews(view);
    
    developer.log('🪟 Created view $viewId with content ${view.content}');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.viewCreated,
      viewId: viewId,
      content: view.content,
    ));
    
    return viewId;
  }

  ViewPosition _calculateOptimalPosition(
    ViewLayout layout,
    double? x,
    double? y,
    double? width,
    double? height,
  ) {
    switch (layout) {
      case ViewLayout.single:
        return ViewPosition(
          x: x ?? 0,
          y: y ?? 0,
          width: width ?? _defaultViewSize * 2 + _handleSize,
          height: height ?? _defaultViewSize * 2 + _handleSize,
        );
      
      case ViewLayout.horizontal:
        return ViewPosition(
          x: x ?? 0,
          y: y ?? 0,
          width: width ?? _defaultViewSize * 2 + _handleSize,
          height: height ?? _defaultViewSize,
        );
      
      case ViewLayout.vertical:
        return ViewPosition(
          x: x ?? 0,
          y: y ?? 0,
          width: width ?? _defaultViewSize,
          height: height ?? _defaultViewSize * 2 + _handleSize,
        );
      
      case ViewLayout.grid:
        final gridSize = sqrt(_views.length + 1).ceil();
        final index = _views.length;
        final row = index ~/ gridSize;
        final col = index % gridSize;
        
        return ViewPosition(
          x: (col * (_defaultViewSize + _handleSize)).toDouble(),
          y: (row * (_defaultViewSize + _handleSize)).toDouble(),
          width: _defaultViewSize.toDouble(),
          height: _defaultViewSize.toDouble(),
        );
    }
  }

  void _adjustOtherViews(SplitView newView) {
    // Adjust existing views to accommodate new view
    for (final view in _views) {
      if (view.id == newView.id) continue;
      
      // Check for overlap and adjust
      if (_viewsOverlap(view, newView)) {
        _repositionView(view, newView);
      }
    }
  }

  bool _viewsOverlap(SplitView view1, SplitView view2) {
    return view1.x < view2.x + view2.width &&
           view1.x + view1.width > view2.x &&
           view1.y < view2.y + view2.height &&
           view1.y + view1.height > view2.y;
  }

  void _repositionView(SplitView view, SplitView newView) {
    // Simple repositioning - move to the right
    view.x = newView.x + newView.width + _handleSize;
    
    // Ensure view stays within bounds
    final maxX = _defaultViewSize * 2 + _handleSize;
    if (view.x + view.width > maxX) {
      view.x = maxX - view.width;
    }
  }

  void removeView(String viewId) {
    final view = _views.firstWhere((v) => v.id == viewId, orElse: () => null as SplitView);
    if (view == null) return;
    
    // Don't remove the last view
    if (_views.length <= 1) {
      developer.log('🪟 Cannot remove last view');
      return;
    }
    
    _views.remove(view);
    
    // If removing active view, activate another
    if (_activeViewId == viewId) {
      _activeViewId = _views.isNotEmpty ? _views.first.id : null;
    }
    
    // Redistribute remaining views
    _redistributeViews();
    
    developer.log('🪟 Removed view $viewId');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.viewRemoved,
      viewId: viewId,
    ));
  }

  void _redistributeViews() {
    if (_views.isEmpty) return;
    
    // Simple redistribution - arrange in grid
    final gridSize = sqrt(_views.length).ceil();
    
    for (int i = 0; i < _views.length; i++) {
      final view = _views[i];
      final row = i ~/ gridSize;
      final col = i % gridSize;
      
      view.x = col * (_defaultViewSize + _handleSize);
      view.y = row * (_defaultViewSize + _handleSize);
    }
  }

  void setActiveView(String viewId) {
    final view = _views.firstWhere((v) => v.id == viewId, orElse: () => null as SplitView);
    if (view == null) return;
    
    // Deactivate all views
    for (final v in _views) {
      v.isActive = false;
    }
    
    // Activate selected view
    view.isActive = true;
    _activeViewId = viewId;
    
    // Update view profile
    _updateViewProfile(viewId);
    
    developer.log('🪟 Activated view $viewId');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.viewActivated,
      viewId: viewId,
    ));
  }

  void _updateViewProfile(String viewId) {
    final profile = _viewProfiles.putIfAbsent(
      viewId,
      () => ViewProfile(viewId: viewId),
    );
    
    profile.recordActivation();
  }

  void resizeView(String viewId, double newWidth, double newHeight) {
    final view = _views.firstWhere((v) => v.id == viewId, orElse: () => null as SplitView);
    if (view == null) return;
    
    // Ensure minimum size
    final constrainedWidth = max(newWidth, _minViewSize.toDouble());
    final constrainedHeight = max(newHeight, _minViewSize.toDouble());
    
    // Resize view
    view.width = constrainedWidth;
    view.height = constrainedHeight;
    
    // Adjust other views if needed
    _adjustViewsForResize(view);
    
    // Save layout to history
    _saveLayoutToHistory();
    
    developer.log('🪟 Resized view $viewId to ${constrainedWidth}x${constrainedHeight}');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.viewResized,
      viewId: viewId,
      width: constrainedWidth,
      height: constrainedHeight,
    ));
  }

  void _adjustViewsForResize(SplitView resizedView) {
    // Adjust views to the right and bottom
    for (final view in _views) {
      if (view.id == resizedView.id) continue;
      
      // Check if view needs adjustment
      if (view.x >= resizedView.x) {
        // View is to the right or at same position
        if (view.x < resizedView.x + resizedView.width) {
          // Overlap in X direction
          view.x = resizedView.x + resizedView.width + _handleSize;
        }
      }
      
      if (view.y >= resizedView.y) {
        // View is below or at same position
        if (view.y < resizedView.y + resizedView.height) {
          // Overlap in Y direction
          view.y = resizedView.y + resizedView.height + _handleSize;
        }
      }
    }
  }

  void startDrag(String handleId, double startX, double startY) {
    _isDragging = true;
    _draggedHandleId = handleId;
    _dragStartX = startX;
    _dragStartY = startY;
    
    developer.log('🪟 Started dragging handle $handleId');
  }

  void updateDrag(double currentX, double currentY) {
    if (!_isDragging || _draggedHandleId == null) return;
    
    final deltaX = currentX - _dragStartX;
    final deltaY = currentY - _dragStartY;
    
    // Find views affected by this handle
    final affectedViews = _getAffectedViews(_draggedHandleId!);
    
    for (final viewId in affectedViews) {
      final view = _views.firstWhere((v) => v.id == viewId, orElse: () => null as SplitView);
      if (view == null) continue;
      
      // Update view size based on drag direction
      _updateViewFromDrag(view, deltaX, deltaY, _draggedHandleId!);
    }
    
    _dragStartX = currentX;
    _dragStartY = currentY;
  }

  List<String> _getAffectedViews(String handleId) {
    // Parse handle ID to determine which views are affected
    // Handle format: "h_view1_view2" for horizontal handle between view1 and view2
    if (handleId.startsWith('h_')) {
      final parts = handleId.substring(2).split('_');
      return parts;
    } else if (handleId.startsWith('v_')) {
      final parts = handleId.substring(2).split('_');
      return parts;
    }
    
    return [];
  }

  void _updateViewFromDrag(SplitView view, double deltaX, double deltaY, String handleId) {
    if (handleId.startsWith('h_')) {
      // Horizontal resize - adjust width
      view.width = max(view.width + deltaX, _minViewSize.toDouble());
    } else if (handleId.startsWith('v_')) {
      // Vertical resize - adjust height
      view.height = max(view.height + deltaY, _minViewSize.toDouble());
    }
  }

  void endDrag() {
    if (!_isDragging) return;
    
    _isDragging = false;
    _draggedHandleId = null;
    
    // Save layout to history
    _saveLayoutToHistory();
    
    developer.log('🪟 Ended dragging');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.dragEnded,
    ));
  }

  void _saveLayoutToHistory() {
    final layout = SplitLayout(
      views: _views.map((view) => ViewLayoutData(
        id: view.id,
        x: view.x,
        y: view.y,
        width: view.width,
        height: view.height,
        content: view.content,
      )).toList(),
      timestamp: DateTime.now(),
    );
    
    _layoutHistory.add(layout);
    
    // Keep only recent layouts
    if (_layoutHistory.length > 10) {
      _layoutHistory.removeAt(0);
    }
  }

  void applyLayout(String layoutName) {
    // Apply predefined layout
    switch (layoutName) {
      case 'single':
        _applySingleLayout();
        break;
      case 'horizontal':
        _applyHorizontalLayout();
        break;
      case 'vertical':
        _applyVerticalLayout();
        break;
      case 'grid':
        _applyGridLayout();
        break;
      default:
        developer.log('🪟 Unknown layout: $layoutName');
    }
  }

  void _applySingleLayout() {
    if (_views.isEmpty) return;
    
    final view = _views.first;
    view.x = 0;
    view.y = 0;
    view.width = _defaultViewSize * 2 + _handleSize;
    view.height = _defaultViewSize * 2 + _handleSize;
    view.layout = ViewLayout.single;
    
    // Remove other views
    final otherViews = _views.skip(1).toList();
    for (final otherView in otherViews) {
      _views.remove(otherView);
    }
  }

  void _applyHorizontalLayout() {
    final viewCount = _views.length;
    if (viewCount == 0) return;
    
    final viewWidth = (_defaultViewSize * 2 + _handleSize) / viewCount;
    
    for (int i = 0; i < viewCount; i++) {
      final view = _views[i];
      view.x = i * viewWidth;
      view.y = 0;
      view.width = viewWidth - _handleSize;
      view.height = _defaultViewSize * 2;
      view.layout = ViewLayout.horizontal;
    }
  }

  void _applyVerticalLayout() {
    final viewCount = _views.length;
    if (viewCount == 0) return;
    
    final viewHeight = (_defaultViewSize * 2 + _handleSize) / viewCount;
    
    for (int i = 0; i < viewCount; i++) {
      final view = _views[i];
      view.x = 0;
      view.y = i * viewHeight;
      view.width = _defaultViewSize * 2;
      view.height = viewHeight - _handleSize;
      view.layout = ViewLayout.vertical;
    }
  }

  void _applyGridLayout() {
    final viewCount = _views.length;
    if (viewCount == 0) return;
    
    final gridSize = sqrt(viewCount).ceil();
    final viewWidth = (_defaultViewSize * 2 + _handleSize) / gridSize;
    final viewHeight = (_defaultViewSize * 2 + _handleSize) / gridSize;
    
    for (int i = 0; i < viewCount; i++) {
      final view = _views[i];
      final row = i ~/ gridSize;
      final col = i % gridSize;
      
      view.x = col * viewWidth;
      view.y = row * viewHeight;
      view.width = viewWidth - _handleSize;
      view.height = viewHeight - _handleSize;
      view.layout = ViewLayout.grid;
    }
  }

  void maximizeView(String viewId) {
    final view = _views.firstWhere((v) => v.id == viewId, orElse: () => null as SplitView);
    if (view == null) return;
    
    // Save original size
    view.originalX = view.x;
    view.originalY = view.y;
    view.originalWidth = view.width;
    view.originalHeight = view.height;
    
    // Maximize
    view.x = 0;
    view.y = 0;
    view.width = _defaultViewSize * 2 + _handleSize;
    view.height = _defaultViewSize * 2 + _handleSize;
    view.isMaximized = true;
    
    // Bring to front
    setActiveView(viewId);
    
    developer.log('🪟 Maximized view $viewId');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.viewMaximized,
      viewId: viewId,
    ));
  }

  void restoreView(String viewId) {
    final view = _views.firstWhere((v) => v.id == viewId, orElse: () => null as SplitView);
    if (view == null || !view.isMaximized) return;
    
    // Restore original size
    view.x = view.originalX ?? 0;
    view.y = view.originalY ?? 0;
    view.width = view.originalWidth ?? _defaultViewSize;
    view.height = view.originalHeight ?? _defaultViewSize;
    view.isMaximized = false;
    
    developer.log('🪟 Restored view $viewId');
    
    _emitEvent(SplitViewEvent(
      type: SplitViewEventType.viewRestored,
      viewId: viewId,
    ));
  }

  List<SplitView> getViews() {
    return List.from(_views);
  }

  SplitView? getActiveView() {
    if (_activeViewId == null) return null;
    return _views.firstWhere((v) => v.id == _activeViewId, orElse: () => null as SplitView);
  }

  List<SplitLayout> getLayoutHistory() {
    return List.from(_layoutHistory);
  }

  Map<String, ViewProfile> getViewProfiles() {
    return Map.from(_viewProfiles);
  }

  String _generateViewId() {
    return 'view_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(SplitViewEvent event) {
    _splitEventController.add(event);
  }

  Stream<SplitViewEvent> get splitEventStream => _splitEventController.stream;

  SmartSplitViewsStats getStats() {
    return SmartSplitViewsStats(
      totalViews: _views.length,
      activeViewId: _activeViewId,
      isDragging: _isDragging,
      layoutHistorySize: _layoutHistory.length,
      viewProfilesCount: _viewProfiles.length,
    );
  }

  void dispose() {
    _views.clear();
    _layoutHistory.clear();
    _viewProfiles.clear();
    _splitEventController.close();
    developer.log('🪟 Smart Split Views disposed');
  }
}

class SplitView {
  final String id;
  double x;
  double y;
  double width;
  double height;
  String content;
  bool isActive;
  ViewLayout layout;
  
  // For maximize/restore
  double? originalX;
  double? originalY;
  double? originalWidth;
  double? originalHeight;
  bool isMaximized = false;

  SplitView({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.content,
    required this.isActive,
    required this.layout,
  });
}

class ViewPosition {
  final double x;
  final double y;
  final double? width;
  final double? height;

  ViewPosition({
    required this.x,
    required this.y,
    this.width,
    this.height,
  });
}

class ViewProfile {
  final String viewId;
  int activationCount = 0;
  DateTime lastActivated = DateTime.now();
  double totalActiveTime = 0;
  DateTime? sessionStart;

  ViewProfile({required this.viewId});

  void recordActivation() {
    activationCount++;
    lastActivated = DateTime.now();
    sessionStart = DateTime.now();
  }

  void recordDeactivation() {
    if (sessionStart != null) {
      totalActiveTime += DateTime.now().difference(sessionStart!).inMilliseconds;
      sessionStart = null;
    }
  }

  double getAverageActiveTime() {
    return activationCount > 0 ? totalActiveTime / activationCount : 0.0;
  }
}

class SplitLayout {
  final List<ViewLayoutData> views;
  final DateTime timestamp;

  SplitLayout({
    required this.views,
    required this.timestamp,
  });
}

class ViewLayoutData {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final String content;

  ViewLayoutData({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.content,
  });
}

enum ViewLayout {
  single,
  horizontal,
  vertical,
  grid,
}

enum SplitViewEventType {
  viewCreated,
  viewRemoved,
  viewActivated,
  viewResized,
  viewMaximized,
  viewRestored,
  dragStarted,
  dragEnded,
  layoutChanged,
}

class SplitViewEvent {
  final SplitViewEventType type;
  final String? viewId;
  final String? content;
  final double? width;
  final double? height;

  SplitViewEvent({
    required this.type,
    this.viewId,
    this.content,
    this.width,
    this.height,
  });
}

class SmartSplitViewsStats {
  final int totalViews;
  final String? activeViewId;
  final bool isDragging;
  final int layoutHistorySize;
  final int viewProfilesCount;

  SmartSplitViewsStats({
    required this.totalViews,
    this.activeViewId,
    required this.isDragging,
    required this.layoutHistorySize,
    required this.viewProfilesCount,
  });
}
