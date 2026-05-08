import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Terminal Pane Manager
///
/// Manages split-screen terminal layouts with drag-to-resize,
/// nested splits, pane focusing, and layout persistence.
class TerminalPaneManager {
  final Map<String, TerminalPane> _panes = {};
  final List<PaneSplit> _splits = [];
  String? _activePaneId;
  String? _rootPaneId;
  PaneLayout _layout = PaneLayout.single;

  int get paneCount => _panes.length;
  String? get activePaneId => _activePaneId;
  PaneLayout get currentLayout => _layout;

  Future<void> initialize() async {
    debugPrint('TerminalPaneManager initialized');
  }

  TerminalPane createRootPane({
    String? id,
    String? title,
  }) {
    final paneId = id ?? 'pane_${DateTime.now().millisecondsSinceEpoch}';
    final pane = TerminalPane(
      id: paneId,
      title: title ?? 'Terminal 1',
      isActive: true,
      relativeX: 0.0,
      relativeY: 0.0,
      relativeWidth: 1.0,
      relativeHeight: 1.0,
    );
    _panes[paneId] = pane;
    _rootPaneId = paneId;
    _activePaneId = paneId;
    _layout = PaneLayout.single;
    return pane;
  }

  TerminalPane? splitPane({
    required String sourcePaneId,
    required PaneSplitDirection direction,
    double ratio = 0.5,
  }) {
    final source = _panes[sourcePaneId];
    if (source == null) return null;

    final newPane = TerminalPane(
      id: 'pane_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Terminal ${_panes.length + 1}',
      isActive: true,
    );

    final split = PaneSplit(
      sourceId: sourcePaneId,
      targetId: newPane.id,
      direction: direction,
      split: ratio.clamp(0.1, 0.9),
    );
    _splits.add(split);
    source.isActive = false;
    _activePaneId = newPane.id;

    _recalculatePositions();
    _panes[newPane.id] = newPane;

    if (direction.isHorizontal) {
      _layout = PaneLayout.horizontal;
    } else if (direction.isVertical) {
      _layout = PaneLayout.vertical;
    } else {
      _layout = PaneLayout.grid;
    }

    debugPrint('Split pane $sourcePaneId -> ${newPane.id} ($direction, $ratio)');
    return newPane;
  }

  bool resizeSplit(int splitIndex, double newSplit) {
    if (splitIndex < 0 || splitIndex >= _splits.length) return false;
    _splits[splitIndex].split = newSplit.clamp(0.1, 0.9);
    _recalculatePositions();
    return true;
  }

  bool focusPane(String paneId) {
    final pane = _panes[paneId];
    if (pane == null) return false;

    if (_activePaneId != null) {
      final oldActive = _panes[_activePaneId!];
      if (oldActive != null) oldActive.isActive = false;
    }

    pane.isActive = true;
    _activePaneId = paneId;
    return true;
  }

  bool closePane(String paneId) {
    if (_panes.length <= 1) return false;
    final removed = _panes.remove(paneId);
    if (removed == null) return false;

    _splits.removeWhere((s) => s.sourceId == paneId || s.targetId == paneId);

    if (_activePaneId == paneId) {
      _activePaneId = _panes.keys.where((k) => k != paneId).first;
      final newActive = _panes[_activePaneId!];
      if (newActive != null) newActive.isActive = true;
    }

    if (_panes.length == 1) {
      _rootPaneId = _panes.keys.first;
      _layout = PaneLayout.single;
    }

    _recalculatePositions();
    return true;
  }

  TerminalPane? getPane(String paneId) => _panes[paneId];
  TerminalPane? get activePane => _activePaneId != null ? _panes[_activePaneId!] : null;
  List<TerminalPane> getAllPanes() => _panes.values.toList();
  List<PaneSplit> getSplits() => List.unmodifiable(_splits);

  void _recalculatePositions() {
    if (_panes.isEmpty) return;

    if (_panes.length == 1) {
      final pane = _panes.values.first;
      pane.relativeX = 0.0;
      pane.relativeY = 0.0;
      pane.relativeWidth = 1.0;
      pane.relativeHeight = 1.0;
      return;
    }

    double currentX = 0.0;
    double currentY = 0.0;
    final paneList = _panes.values.toList();

    final hSplits = _splits.where((s) => s.direction.isHorizontal).length;
    final vSplits = _splits.where((s) => s.direction.isVertical).length;

    if (hSplits > 0) {
      final segmentWidth = 1.0 / (hSplits + 1);
      for (int i = 0; i < paneList.take(hSplits + 1).length; i++) {
        paneList[i].relativeX = currentX;
        paneList[i].relativeY = 0.0;
        paneList[i].relativeWidth = segmentWidth;
        paneList[i].relativeHeight = 1.0;
        currentX += segmentWidth;
      }
    } else if (vSplits > 0) {
      final segmentHeight = 1.0 / (vSplits + 1);
      for (int i = 0; i < paneList.take(vSplits + 1).length; i++) {
        paneList[i].relativeX = 0.0;
        paneList[i].relativeY = currentY;
        paneList[i].relativeWidth = 1.0;
        paneList[i].relativeHeight = segmentHeight;
        currentY += segmentHeight;
      }
    } else {
      final cols = (sqrt(_panes.length.toDouble())).ceil();
      final rows = (_panes.length / cols).ceil();
      final cellW = 1.0 / cols;
      final cellH = 1.0 / rows;

      for (int i = 0; i < paneList.length && i < cols * rows; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        paneList[i].relativeX = col * cellW;
        paneList[i].relativeY = row * cellH;
        paneList[i].relativeWidth = cellW;
        paneList[i].relativeHeight = cellH;
      }
    }
  }

  void dispose() {
    _panes.clear();
    _splits.clear();
    _activePaneId = null;
    _rootPaneId = null;
  }
}

enum PaneLayout { single, horizontal, vertical, grid }
enum PaneSplitDirection {
  horizontal, vertical, gridBottom, gridRight;

  bool get isHorizontal => this == PaneSplitDirection.horizontal || this == PaneSplitDirection.gridRight;
  bool get isVertical => this == PaneSplitDirection.vertical || this == PaneSplitDirection.gridBottom;
}

class TerminalPane {
  final String id;
  String title;
  bool isActive;
  double relativeX;
  double relativeY;
  double relativeWidth;
  double relativeHeight;

  TerminalPane({
    required this.id,
    required this.title,
    this.isActive = false,
    this.relativeX = 0.0,
    this.relativeY = 0.0,
    this.relativeWidth = 1.0,
    this.relativeHeight = 1.0,
  });
}

class PaneSplit {
  final String sourceId;
  final String targetId;
  final PaneSplitDirection direction;
  double split;

  PaneSplit({
    required this.sourceId,
    required this.targetId,
    required this.direction,
    required this.split,
  });
}