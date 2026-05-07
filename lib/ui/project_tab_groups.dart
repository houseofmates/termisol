import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/personal_command_fingerprint.dart';

/// Project-based tab grouping with drag-and-drop functionality
/// 
/// Features:
/// - Drag tabs to merge into groups
/// - Collapsible, recolorable, renamable groups
/// - Browser-like tab grouping
/// - Project-based organization
/// - Persistent group state
class ProjectTabGroups extends StatefulWidget {
  final List<TabData> initialTabs;
  final Function(int)? onTabSelected;
  final Function(int)? onTabClosed;
  final Function(String, int)? onTabMoved;
  final Function(String)? onGroupRenamed;
  final Function(String, Color)? onGroupRecolored;
  final PersonalCommandFingerprint? fingerprintSystem;
  
  const ProjectTabGroups({
    super.key,
    required this.initialTabs,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabMoved,
    this.onGroupRenamed,
    this.onGroupRecolored,
    this.fingerprintSystem,
  });
  
  @override
  State<ProjectTabGroups> createState() => _ProjectTabGroupsState();
}

class _ProjectTabGroupsState extends State<ProjectTabGroups> 
    with TickerProviderStateMixin {
  final List<TabGroup> _groups = [];
  final List<TabData> _ungroupedTabs = [];
  final Map<int, String> _tabToGroupMap = {};
  
  int? _draggedTabIndex;
  String? _draggedFromGroup;
  String? _hoveredGroup;
  bool _isDragging = false;
  
  late AnimationController _dragAnimationController;
  late AnimationController _groupAnimationController;
  late Animation<double> _dragAnimation;
  late Animation<double> _groupAnimation;
  
  @override
  void initState() {
    super.initState();
    
    _dragAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _groupAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _dragAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _dragAnimationController, curve: Curves.easeOut),
    );
    
    _groupAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _groupAnimationController, curve: Curves.easeInOut),
    );
    
    _initializeGroups();
  }
  
  void _initializeGroups() {
    // Group tabs by project context from fingerprint system
    final projectTabs = <String, List<TabData>>{};
    
    for (final tab in widget.initialTabs) {
      final project = tab.project ?? 'ungrouped';
      projectTabs.putIfAbsent(project, () => []).add(tab);
      _tabToGroupMap[tab.id] = project;
    }
    
    // Create groups
    for (final entry in projectTabs.entries) {
      if (entry.key == 'ungrouped') {
        _ungroupedTabs.addAll(entry.value);
      } else {
        final group = TabGroup(
          id: entry.key,
          name: _formatGroupName(entry.key),
          color: _getGroupColor(entry.key),
          tabs: entry.value,
          isCollapsed: false,
        );
        _groups.add(group);
      }
    }
    
    // Sort groups by last used
    _groups.sort((a, b) {
      final aLastUsed = a.tabs.isNotEmpty ? a.tabs.map((t) => t.lastUsed).reduce(math.max) : 0;
      final bLastUsed = b.tabs.isNotEmpty ? b.tabs.map((t) => t.lastUsed).reduce(math.max) : 0;
      return bLastUsed.compareTo(aLastUsed);
    });
  }
  
  String _formatGroupName(String project) {
    // Format project name based on context
    switch (project) {
      case 'server_233':
        return '🖥️ Server .233';
      case 'server_250':
        return '🖥️ Server .250';
      case 'development':
        return '💻 Development';
      case 'documents':
        return '📄 Documents';
      default:
        return '📁 ${project[0].toUpperCase()}${project.substring(1)}';
    }
  }
  
  Color _getGroupColor(String project) {
    // Assign colors based on project type
    switch (project) {
      case 'server_233':
        return Colors.red[400]!;
      case 'server_250':
        return Colors.blue[400]!;
      case 'development':
        return Colors.green[400]!;
      case 'documents':
        return Colors.orange[400]!;
      default:
        return Colors.purple[400]!;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Group header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Project Groups',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_ungroupedTabs.isNotEmpty)
                  TextButton.icon(
                    onPressed: _createGroupFromUngrouped,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Group', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          
          // Groups and tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ungrouped tabs
                  if (_ungroupedTabs.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _buildUngroupedSection(),
                    const SizedBox(width: 16),
                  ],
                  
                  // Project groups
                  ..._groups.asMap().entries.map((entry) {
                    final index = entry.key;
                    final group = entry.value;
                    return _buildProjectGroup(group, index);
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUngroupedSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ungrouped',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: _ungroupedTabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              return _buildTab(tab, index, null);
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProjectGroup(TabGroup group, int groupIndex) {
    final isHovered = _hoveredGroup == group.id;
    final isCollapsed = group.isCollapsed;
    
    return Container(
      margin: const EdgeInsets.only(left: 8, right: 8),
      decoration: BoxDecoration(
        color: group.color.withOpacity(isHovered ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: group.color.withOpacity(isHovered ? 0.8 : 0.4),
          width: isHovered ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          GestureDetector(
            onTap: () => _toggleGroupCollapse(group),
            onDoubleTap: () => _showGroupRenameDialog(group),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isCollapsed ? Icons.folder : Icons.folder_open,
                    size: 16,
                    color: group.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.name,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: group.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showGroupColorPicker(group),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: group.color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${group.tabs.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
            ),
          ),
          
          // Tabs (animated)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: isCollapsed
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: group.tabs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final tab = entry.value;
                        return _buildTab(tab, index, group.id);
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTab(TabData tab, int tabIndex, String? groupId) {
    final isDragged = _draggedTabIndex == tab.id;
    final isHovered = _isDragging && _hoveredGroup == groupId;
    
    return DragTarget<String>(
      onWillAccept: (data) {
        // Allow dropping on tabs from other groups
        return data != groupId && data != null;
      },
      onAccept: (data) {
        _moveTabToGroup(tab.id, data);
      },
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<String>(
          data: groupId ?? 'ungrouped',
          feedback: _buildDragFeedback(tab),
          childWhenDragging: _buildDragPlaceholder(tab),
          onDragStarted: () {
            setState(() {
              _isDragging = true;
              _draggedTabIndex = tab.id;
              _draggedFromGroup = groupId;
            });
          },
          onDragEnd: (details) {
            setState(() {
              _isDragging = false;
              _draggedTabIndex = null;
              _draggedFromGroup = null;
              _hoveredGroup = null;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isHovered 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isHovered 
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: Opacity(
              opacity: isDragged ? 0.5 : 1.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: tab.isActive 
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor,
                    width: tab.isActive ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tab icon based on content
                    _getTabIcon(tab),
                    const SizedBox(width: 6),
                    
                    // Tab title
                    Flexible(
                      child: Text(
                        tab.title,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tab.isActive 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: tab.isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    
                    // Close button
                    if (!tab.isPinned)
                      GestureDetector(
                        onTap: () => widget.onTabClosed?.call(tab.id),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _getTabIcon(TabData tab) {
    // Return icon based on tab content or project
    if (tab.project != null) {
      switch (tab.project) {
        case 'server_233':
          return const Icon(Icons.dns, size: 14);
        case 'server_250':
          return const Icon(Icons.dns, size: 14);
        case 'development':
          return const Icon(Icons.code, size: 14);
        case 'documents':
          return const Icon(Icons.description, size: 14);
        default:
          return const Icon(Icons.folder, size: 14);
      }
    }
    
    // Default icon based on content
    if (tab.title.toLowerCase().contains('git')) {
      return const Icon(Icons.source, size: 14);
    } else if (tab.title.toLowerCase().contains('docker')) {
      return const Icon(Icons.inventory_2, size: 14);
    } else if (tab.title.toLowerCase().contains('ssh')) {
      return const Icon(Icons.terminal, size: 14);
    }
    
    return const Icon(Icons.tab, size: 14);
  }
  
  Widget _buildDragFeedback(TabData tab) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _getTabIcon(tab),
          const SizedBox(width: 6),
          Text(
            tab.title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDragPlaceholder(TabData tab) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
          style: BorderStyle.solid,
        ),
      ),
      child: Text(
        'Drop here',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
  
  void _toggleGroupCollapse(TabGroup group) {
    setState(() {
      group.isCollapsed = !group.isCollapsed;
    });
  }
  
  void _showGroupRenameDialog(TabGroup group) {
    final controller = TextEditingController(text: group.name);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter group name...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              widget.onGroupRenamed?.call(group.id, controller.text);
              setState(() {
                group.name = controller.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
  
  void _showGroupColorPicker(TabGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Group Color'),
        content: SizedBox(
          width: 300,
          height: 200,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 1.0,
            ),
            itemCount: _predefinedColors.length,
            itemBuilder: (context, index) {
              final color = _predefinedColors[index];
              return GestureDetector(
                onTap: () {
                  widget.onGroupRecolored?.call(group.id, color);
                  setState(() {
                    group.color = color;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: group.color == color
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
  
  void _moveTabToGroup(int tabId, String targetGroupId) {
    // Find the tab
    TabData? tab;
    String? sourceGroupId;
    
    // Check ungrouped tabs
    for (final t in _ungroupedTabs) {
      if (t.id == tabId) {
        tab = t;
        sourceGroupId = 'ungrouped';
        break;
      }
    }
    
    // Check grouped tabs
    if (tab == null) {
      for (final group in _groups) {
        for (final t in group.tabs) {
          if (t.id == tabId) {
            tab = t;
            sourceGroupId = group.id;
            group.tabs.remove(t);
            break;
          }
        }
        if (tab != null) break;
      }
    }
    
    if (tab == null) return;
    
    // Move to target group
    if (targetGroupId == 'ungrouped') {
      _ungroupedTabs.add(tab!);
    } else {
      final targetGroup = _groups.firstWhere((g) => g.id == targetGroupId);
      targetGroup.tabs.add(tab!);
    }
    
    // Update mapping
    _tabToGroupMap[tabId] = targetGroupId;
    
    // Notify parent
    widget.onTabMoved?.call(tabId, targetGroupId);
    
    setState(() {});
  }
  
  void _createGroupFromUngrouped() {
    if (_ungroupedTabs.isEmpty) return;
    
    final groupName = 'New Group ${_groups.length + 1}';
    final newGroup = TabGroup(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: groupName,
      color: _getGroupColor('custom'),
      tabs: List.from(_ungroupedTabs),
      isCollapsed: false,
    );
    
    _groups.add(newGroup);
    _ungroupedTabs.clear();
    
    // Update mappings
    for (final tab in newGroup.tabs) {
      _tabToGroupMap[tab.id] = newGroup.id;
    }
    
    setState(() {});
  }
  
  List<Color> get _predefinedColors => [
    Colors.red[400]!,
    Colors.blue[400]!,
    Colors.green[400]!,
    Colors.orange[400]!,
    Colors.purple[400]!,
    Colors.teal[400]!,
    Colors.pink[400]!,
    Colors.indigo[400]!,
    Colors.amber[400]!,
    Colors.cyan[400]!,
    Colors.lime[400]!,
    Colors.brown[400]!,
  ];
  
  @override
  void dispose() {
    _dragAnimationController.dispose();
    _groupAnimationController.dispose();
    super.dispose();
  }
}

/// Tab data
class TabData {
  final int id;
  final String title;
  final bool isActive;
  final bool isPinned;
  final String? project;
  final int lastUsed;
  
  TabData({
    required this.id,
    required this.title,
    required this.isActive,
    this.isPinned = false,
    this.project,
    required this.lastUsed,
  });
}

/// Tab group
class TabGroup {
  final String id;
  String name;
  Color color;
  List<TabData> tabs;
  bool isCollapsed;
  
  TabGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.tabs,
    this.isCollapsed = false,
  });
}
