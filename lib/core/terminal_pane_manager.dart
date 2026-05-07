import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'terminal_session.dart';

/// Advanced terminal pane management system
///
/// Supports splitting, tiling, and complex layouts with drag-and-drop rearrangement
class TerminalPaneManager {
  final List<TerminalPane> _panes = [];
  final StreamController<TerminalPaneEvent> _eventController =
      StreamController<TerminalPaneEvent>.broadcast();

  Stream<TerminalPaneEvent> get events => _eventController.stream;

  bool _isInitialized = false;
  TerminalLayout _currentLayout = TerminalLayout.single;

  bool get isInitialized => _isInitialized;
  List<TerminalPane> get panes => List.unmodifiable(_panes);
  TerminalLayout get currentLayout => _currentLayout;

  /// Initialize the pane manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Create initial pane
    final initialPane = TerminalPane(
      id: 'pane_0',
      session: TerminalSession(id: 'session_0', name: 'Terminal 1'),
      bounds: const Rect.fromLTWH(0, 0, 1, 1), // Normalized coordinates
    );

    _panes.add(initialPane);
    await initialPane.session.start();

    _isInitialized = true;
    _eventController.add(TerminalPaneEvent(
      type: TerminalPaneEventType.initialized,
      pane: initialPane,
    ));

    debugPrint('🖥️ Terminal Pane Manager initialized');
  }

  /// Split a pane horizontally
  Future<TerminalPane?> splitPaneHorizontally(String paneId) async {
    final paneIndex = _panes.indexWhere((p) => p.id == paneId);
    if (paneIndex == -1) return null;

    final originalPane = _panes[paneIndex];

    // Calculate new bounds
    final leftBounds = Rect.fromLTRB(
      originalPane.bounds.left,
      originalPane.bounds.top,
      originalPane.bounds.left + originalPane.bounds.width / 2,
      originalPane.bounds.bottom,
    );

    final rightBounds = Rect.fromLTRB(
      originalPane.bounds.left + originalPane.bounds.width / 2,
      originalPane.bounds.top,
      originalPane.bounds.right,
      originalPane.bounds.bottom,
    );

    // Update original pane bounds
    originalPane.bounds = leftBounds;

    // Create new pane
    final newPane = TerminalPane(
      id: 'pane_${_panes.length}',
      session: TerminalSession(
        id: 'session_${_panes.length}',
        name: 'Terminal ${_panes.length + 1}'
      ),
      bounds: rightBounds,
    );

    _panes.insert(paneIndex + 1, newPane);
    await newPane.session.start();

    _currentLayout = TerminalLayout.split;
    _eventController.add(TerminalPaneEvent(
      type: TerminalPaneEventType.paneSplit,
      pane: newPane,
      data: {'direction': 'horizontal', 'parentPaneId': paneId},
    ));

    return newPane;
  }

  /// Split a pane vertically
  Future<TerminalPane?> splitPaneVertically(String paneId) async {
    final paneIndex = _panes.indexWhere((p) => p.id == paneId);
    if (paneIndex == -1) return null;

    final originalPane = _panes[paneIndex];

    // Calculate new bounds
    final topBounds = Rect.fromLTRB(
      originalPane.bounds.left,
      originalPane.bounds.top,
      originalPane.bounds.right,
      originalPane.bounds.top + originalPane.bounds.height / 2,
    );

    final bottomBounds = Rect.fromLTRB(
      originalPane.bounds.left,
      originalPane.bounds.top + originalPane.bounds.height / 2,
      originalPane.bounds.right,
      originalPane.bounds.bottom,
    );

    // Update original pane bounds
    originalPane.bounds = topBounds;

    // Create new pane
    final newPane = TerminalPane(
      id: 'pane_${_panes.length}',
      session: TerminalSession(
        id: 'session_${_panes.length}',
        name: 'Terminal ${_panes.length + 1}'
      ),
      bounds: bottomBounds,
    );

    _panes.insert(paneIndex + 1, newPane);
    await newPane.session.start();

    _currentLayout = TerminalLayout.split;
    _eventController.add(TerminalPaneEvent(
      type: TerminalPaneEventType.paneSplit,
      pane: newPane,
      data: {'direction': 'vertical', 'parentPaneId': paneId},
    ));

    return newPane;
  }

  /// Close a pane
  Future<bool> closePane(String paneId) async {
    final paneIndex = _panes.indexWhere((p) => p.id == paneId);
    if (paneIndex == -1) return false;

    // Don't allow closing the last pane
    if (_panes.length <= 1) return false;

    final pane = _panes[paneIndex];
    await pane.session.disposeSession();
    _panes.removeAt(paneIndex);

    // Redistribute space from closed pane
    _redistributeSpaceAfterClose(paneIndex);

    _eventController.add(TerminalPaneEvent(
      type: TerminalPaneEventType.paneClosed,
      pane: pane,
    ));

    return true;
  }

  /// Redistribute space after pane closure
  void _redistributeSpaceAfterClose(int closedIndex) {
    if (_panes.isEmpty) return;

    // Simple redistribution - expand adjacent panes
    final totalPanes = _panes.length;
    final equalWidth = 1.0 / math.sqrt(totalPanes).ceil();
    final equalHeight = 1.0 / (totalPanes / math.sqrt(totalPanes).ceil()).ceil();

    for (int i = 0; i < _panes.length; i++) {
      final row = i ~/ math.sqrt(totalPanes).ceil();
      final col = i % math.sqrt(totalPanes).ceil();

      _panes[i].bounds = Rect.fromLTRB(
        col * equalWidth,
        row * equalHeight,
        (col + 1) * equalWidth,
        (row + 1) * equalHeight,
      );
    }
  }

  /// Get the focused pane
  TerminalPane? get focusedPane => _panes.isNotEmpty ? _panes.last : null;

  /// Dispose all panes and cleanup
  Future<void> dispose() async {
    for (final pane in _panes) {
      await pane.session.disposeSession();
    }
    _panes.clear();
    await _eventController.close();
    _isInitialized = false;
  }
}

/// Terminal pane with session and layout information
class TerminalPane {
  final String id;
  final TerminalSession session;
  Rect bounds; // Normalized coordinates (0-1)

  TerminalPane({
    required this.id,
    required this.session,
    required this.bounds,
  });

  bool containsPosition(Offset position) {
    return bounds.contains(position);
  }

  void updateBounds(Rect newBounds) {
    bounds = newBounds;
  }

  @override
  String toString() => 'TerminalPane(id: $id, bounds: $bounds)';
}

/// Terminal layout types
enum TerminalLayout {
  single,
  split,
  grid,
  custom,
}

/// Terminal pane events
enum TerminalPaneEventType {
  initialized,
  paneSplit,
  paneClosed,
  paneResized,
  paneFocused,
  layoutChanged,
}

class TerminalPaneEvent {
  final TerminalPaneEventType type;
  final TerminalPane? pane;
  final Map<String, dynamic>? data;

  TerminalPaneEvent({
    required this.type,
    this.pane,
    this.data,
  });
}