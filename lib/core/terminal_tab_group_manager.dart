import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Terminal Tab Group Manager
/// 
/// Implements advanced tab grouping with drag-over merging, colored indicators,
/// and group management features similar to browser tab groups.
/// 
/// Features:
/// - Drag-over tab merging (not just rearranging)
/// - Colored line indicators for groups
/// - Group collapse/expand functionality
/// - Group renaming and recoloring
/// - Context menu options for tabs and groups
/// - Visual feedback during drag operations
class TerminalTabGroupManager {
  static final TerminalTabGroupManager _instance = TerminalTabGroupManager._internal();
  factory TerminalTabGroupManager() => _instance;
  TerminalTabGroupManager._internal();

  bool _isInitialized = false;
  final Map<String, TerminalTab> _tabs = {};
  final Map<String, TabGroup> _groups = {};
  final List<TabGroup> _groupOrder = [];
  
  // Drag and drop state
  String? _draggedTabId;
  String? _hoveredGroupId;
  bool _isDraggingOver = false;
  
  // Available colors for groups
  static const List<Color> _groupColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
  ];
  
  final _groupController = StreamController<TabGroupEvent>.broadcast();
  Stream<TabGroupEvent> get events => _groupController.stream;
  
  bool get isInitialized => _isInitialized;
  String? get draggedTabId => _draggedTabId;
  String? get hoveredGroupId => _hoveredGroupId;
  bool get isDraggingOver => _isDraggingOver;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Create default group
    await _createDefaultGroup();
    
    _isInitialized = true;
    debugPrint('📑 Terminal Tab Group Manager initialized');
  }

  Future<TerminalTab> createTab({
    required String title,
    String? sessionId,
    String? groupId,
  }) async {
    final tab = TerminalTab(
      id: 'tab_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      sessionId: sessionId,
      groupId: groupId ?? _getDefaultGroupId(),
      createdAt: DateTime.now(),
    );
    
    _tabs[tab.id] = tab;
    
    // Add to group
    if (tab.groupId != null) {
      await _addTabToGroup(tab.id, tab.groupId!);
    }
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.tabCreated,
      data: {
        'tab_id': tab.id,
        'title': title,
        'group_id': tab.groupId,
      },
    ));
    
    return tab;
  }

  Future<TabGroup> createGroup({
    required String name,
    Color? color,
    List<String>? tabIds,
  }) async {
    final group = TabGroup(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      color: color ?? _getNextAvailableColor(),
      tabIds: tabIds ?? [],
      createdAt: DateTime.now(),
      isCollapsed: false,
    );
    
    _groups[group.id] = group;
    _groupOrder.add(group);
    
    // Update tab group references
    for (final tabId in group.tabIds) {
      final tab = _tabs[tabId];
      if (tab != null) {
        tab.groupId = group.id;
      }
    }
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.groupCreated,
      data: {
        'group_id': group.id,
        'name': name,
        'color': group.color.value.toString(),
        'tab_count': group.tabIds.length,
      },
    ));
    
    return group;
  }

  Future<void> startDragTab(String tabId) async {
    _draggedTabId = tabId;
    _isDraggingOver = false;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.dragStarted,
      data: {
        'tab_id': tabId,
      },
    ));
    
    debugPrint('📑 Started dragging tab: $tabId');
  }

  Future<void> updateDragHover(String? groupId) async {
    if (_hoveredGroupId == groupId) return;
    
    _hoveredGroupId = groupId;
    _isDraggingOver = groupId != null;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.dragHover,
      data: {
        'hovered_group_id': groupId,
        'is_dragging_over': _isDraggingOver,
      },
    ));
  }

  Future<void> endDragTab(String tabId, {String? targetGroupId}) async {
    try {
      if (targetGroupId != null && targetGroupId != _tabs[tabId]?.groupId) {
        // Move tab to target group (merge)
        await _moveTabToGroup(tabId, targetGroupId);
      }
      
      _draggedTabId = null;
      _hoveredGroupId = null;
      _isDraggingOver = false;
      
      _groupController.add(TabGroupEvent(
        type: TabGroupEventType.dragEnded,
        data: {
          'tab_id': tabId,
          'target_group_id': targetGroupId,
        },
      ));
      
      debugPrint('📑 Ended dragging tab: $tabId to group: $targetGroupId');
      
    } catch (e) {
      debugPrint('❌ Failed to end drag tab: $e');
    }
  }

  Future<void> collapseGroup(String groupId) async {
    final group = _groups[groupId];
    if (group == null || group.isCollapsed) return;
    
    group.isCollapsed = true;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.groupCollapsed,
      data: {
        'group_id': groupId,
        'group_name': group.name,
      },
    ));
    
    debugPrint('📑 Collapsed group: ${group.name}');
  }

  Future<void> expandGroup(String groupId) async {
    final group = _groups[groupId];
    if (group == null || !group.isCollapsed) return;
    
    group.isCollapsed = false;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.groupExpanded,
      data: {
        'group_id': groupId,
        'group_name': group.name,
      },
    ));
    
    debugPrint('📑 Expanded group: ${group.name}');
  }

  Future<void> renameGroup(String groupId, String newName) async {
    final group = _groups[groupId];
    if (group == null) return;
    
    final oldName = group.name;
    group.name = newName;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.groupRenamed,
      data: {
        'group_id': groupId,
        'old_name': oldName,
        'new_name': newName,
      },
    ));
    
    debugPrint('📑 Renamed group: $oldName → $newName');
  }

  Future<void> recolorGroup(String groupId, Color newColor) async {
    final group = _groups[groupId];
    if (group == null) return;
    
    final oldColor = group.color;
    group.color = newColor;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.groupRecolored,
      data: {
        'group_id': groupId,
        'old_color': oldColor.value.toString(),
        'new_color': newColor.value.toString(),
      },
    ));
    
    debugPrint('📑 Recolored group: ${group.name}');
  }

  Future<void> deleteGroup(String groupId, {bool moveTabsToDefault = true}) async {
    final group = _groups[groupId];
    if (group == null) return;
    
    // Move tabs to default group if requested
    if (moveTabsToDefault) {
      final defaultGroupId = _getDefaultGroupId();
      for (final tabId in group.tabIds) {
        await _moveTabToGroup(tabId, defaultGroupId);
      }
    }
    
    _groups.remove(groupId);
    _groupOrder.remove(group);
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.groupDeleted,
      data: {
        'group_id': groupId,
        'group_name': group.name,
        'tabs_moved': moveTabsToDefault,
      },
    ));
    
    debugPrint('📑 Deleted group: ${group.name}');
  }

  Future<void> renameTab(String tabId, String newTitle) async {
    final tab = _tabs[tabId];
    if (tab == null) return;
    
    final oldTitle = tab.title;
    tab.title = newTitle;
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.tabRenamed,
      data: {
        'tab_id': tabId,
        'old_title': oldTitle,
        'new_title': newTitle,
      },
    ));
    
    debugPrint('📑 Renamed tab: $oldTitle → $newTitle');
  }

  Future<void> deleteTab(String tabId) async {
    final tab = _tabs[tabId];
    if (tab == null) return;
    
    // Remove from group
    if (tab.groupId != null) {
      await _removeTabFromGroup(tabId, tab.groupId!);
    }
    
    _tabs.remove(tabId);
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.tabDeleted,
      data: {
        'tab_id': tabId,
        'title': tab.title,
        'group_id': tab.groupId,
      },
    ));
    
    debugPrint('📑 Deleted tab: ${tab.title}');
  }

  Future<void> moveTab(String tabId, int newIndex) async {
    final tab = _tabs[tabId];
    if (tab == null || tab.groupId == null) return;
    
    final group = _groups[tab.groupId!];
    if (group == null) return;
    
    // Remove from current position
    group.tabIds.remove(tabId);
    
    // Insert at new position
    final insertIndex = math.min(newIndex, group.tabIds.length);
    group.tabIds.insert(insertIndex, tabId);
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.tabMoved,
      data: {
        'tab_id': tabId,
        'new_index': newIndex,
        'group_id': tab.groupId,
      },
    ));
    
    debugPrint('📑 Moved tab ${tab.title} to index $newIndex');
  }

  List<TabGroup> getGroups() {
    return _groupOrder.toList();
  }

  TabGroup? getGroup(String groupId) {
    return _groups[groupId];
  }

  TerminalTab? getTab(String tabId) {
    return _tabs[tabId];
  }

  List<TerminalTab> getTabsInGroup(String groupId) {
    final group = _groups[groupId];
    if (group == null) return [];
    
    return group.tabIds
        .map((tabId) => _tabs[tabId])
        .whereType<TerminalTab>()
        .toList();
  }

  List<TerminalTab> getAllTabs() {
    return _tabs.values.toList();
  }

  List<Color> getAvailableColors() {
    final usedColors = _groups.values.map((g) => g.color).toSet();
    return _groupColors.where((color) => !usedColors.contains(color)).toList();
  }

  TabGroupStatistics getStatistics() {
    return TabGroupStatistics(
      totalGroups: _groups.length,
      totalTabs: _tabs.length,
      collapsedGroups: _groups.values.where((g) => g.isCollapsed).length,
      averageTabsPerGroup: _groups.isEmpty ? 0.0 : _tabs.length / _groups.length,
      colorDistribution: _getColorDistribution(),
    );
  }

  Future<void> _createDefaultGroup() async {
    await createGroup(
      name: 'Default',
      color: Colors.grey,
    );
  }

  String _getDefaultGroupId() {
    return _groups.keys.first;
  }

  Color _getNextAvailableColor() {
    final availableColors = getAvailableColors();
    return availableColors.isNotEmpty ? availableColors.first : Colors.grey;
  }

  Future<void> _addTabToGroup(String tabId, String groupId) async {
    final group = _groups[groupId];
    if (group == null) return;
    
    if (!group.tabIds.contains(tabId)) {
      group.tabIds.add(tabId);
    }
    
    final tab = _tabs[tabId];
    if (tab != null) {
      tab.groupId = groupId;
    }
  }

  Future<void> _removeTabFromGroup(String tabId, String groupId) async {
    final group = _groups[groupId];
    if (group == null) return;
    
    group.tabIds.remove(tabId);
    
    final tab = _tabs[tabId];
    if (tab != null) {
      tab.groupId = null;
    }
  }

  Future<void> _moveTabToGroup(String tabId, String targetGroupId) async {
    final tab = _tabs[tabId];
    if (tab == null) return;
    
    final oldGroupId = tab.groupId;
    
    // Remove from old group
    if (oldGroupId != null) {
      await _removeTabFromGroup(tabId, oldGroupId);
    }
    
    // Add to new group
    await _addTabToGroup(tabId, targetGroupId);
    
    _groupController.add(TabGroupEvent(
      type: TabGroupEventType.tabGroupChanged,
      data: {
        'tab_id': tabId,
        'old_group_id': oldGroupId,
        'new_group_id': targetGroupId,
      },
    ));
    
    debugPrint('📑 Moved tab ${tab.title} to group $targetGroupId');
  }

  Map<String, int> _getColorDistribution() {
    final distribution = <String, int>{};
    
    for (final group in _groups.values) {
      final colorName = _getColorName(group.color);
      distribution[colorName] = (distribution[colorName] ?? 0) + 1;
    }
    
    return distribution;
  }

  String _getColorName(Color color) {
    if (color == Colors.red) return 'red';
    if (color == Colors.blue) return 'blue';
    if (color == Colors.green) return 'green';
    if (color == Colors.orange) return 'orange';
    if (color == Colors.purple) return 'purple';
    if (color == Colors.pink) return 'pink';
    if (color == Colors.teal) return 'teal';
    if (color == Colors.indigo) return 'indigo';
    if (color == Colors.grey) return 'grey';
    return 'custom';
  }

  Future<void> dispose() async {
    _groupController.close();
    _tabs.clear();
    _groups.clear();
    _groupOrder.clear();
    _draggedTabId = null;
    _hoveredGroupId = null;
    _isDraggingOver = false;
    _isInitialized = false;
    
    debugPrint('📑 Terminal Tab Group Manager disposed');
  }
}

/// Data classes
class TerminalTab {
  final String id;
  String title;
  final String? sessionId;
  String? groupId;
  final DateTime createdAt;
  DateTime lastAccessed;
  
  TerminalTab({
    required this.id,
    required this.title,
    this.sessionId,
    this.groupId,
    required this.createdAt,
  }) : lastAccessed = createdAt;
  
  void updateLastAccessed() {
    lastAccessed = DateTime.now();
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'session_id': sessionId,
    'group_id': groupId,
    'created_at': createdAt.toIso8601String(),
    'last_accessed': lastAccessed.toIso8601String(),
  };
  
  factory TerminalTab.fromJson(Map<String, dynamic> json) => TerminalTab(
    id: json['id'] as String,
    title: json['title'] as String,
    sessionId: json['session_id'] as String?,
    groupId: json['group_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  )..lastAccessed = DateTime.parse(json['last_accessed'] as String);
}

class TabGroup {
  final String id;
  String name;
  Color color;
  final List<String> tabIds;
  final DateTime createdAt;
  bool isCollapsed;
  
  TabGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.tabIds,
    required this.createdAt,
    required this.isCollapsed,
  });
  
  int get tabCount => tabIds.length;
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.value.toString(),
    'tab_ids': tabIds,
    'created_at': createdAt.toIso8601String(),
    'is_collapsed': isCollapsed,
  };
  
  factory TabGroup.fromJson(Map<String, dynamic> json) => TabGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    color: Color(int.parse(json['color'] as String)),
    tabIds: (json['tab_ids'] as List<dynamic>).cast<String>(),
    createdAt: DateTime.parse(json['created_at'] as String),
    isCollapsed: json['is_collapsed'] as bool,
  );
}

class TabGroupStatistics {
  final int totalGroups;
  final int totalTabs;
  final int collapsedGroups;
  final double averageTabsPerGroup;
  final Map<String, int> colorDistribution;
  
  TabGroupStatistics({
    required this.totalGroups,
    required this.totalTabs,
    required this.collapsedGroups,
    required this.averageTabsPerGroup,
    required this.colorDistribution,
  });
  
  Map<String, dynamic> toJson() => {
    'total_groups': totalGroups,
    'total_tabs': totalTabs,
    'collapsed_groups': collapsedGroups,
    'average_tabs_per_group': averageTabsPerGroup,
    'color_distribution': colorDistribution,
  };
}

class TabGroupEvent {
  final TabGroupEventType type;
  final Map<String, dynamic>? data;
  
  TabGroupEvent({
    required this.type,
    this.data,
  });
}

enum TabGroupEventType {
  tabCreated,
  tabDeleted,
  tabRenamed,
  tabMoved,
  tabGroupChanged,
  groupCreated,
  groupDeleted,
  groupRenamed,
  groupRecolored,
  groupCollapsed,
  groupExpanded,
  dragStarted,
  dragHover,
  dragEnded,
}
