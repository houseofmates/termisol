import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/terminal_tab_group_manager.dart';

/// Tab Group Widget with drag-over merging and colored indicators
class TabGroupWidget extends StatefulWidget {
  final TabGroup group;
  final List<TerminalTab> tabs;
  final bool isActive;
  final VoidCallback? onTabSelected;
  final Function(String)? onTabClosed;
  final Function(String)? onTabRenamed;
  final Function(String)? onGroupCollapsed;
  final Function(String)? onGroupExpanded;
  final Function(String)? onGroupRenamed;
  final Function(String)? onGroupRecolored;
  final Function(String)? onGroupDeleted;

  const TabGroupWidget({
    Key? key,
    required this.group,
    required this.tabs,
    this.isActive = false,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabRenamed,
    this.onGroupCollapsed,
    this.onGroupExpanded,
    this.onGroupRenamed,
    this.onGroupRecolored,
    this.onGroupDeleted,
  }) : super(key: key);

  @override
  State<TabGroupWidget> createState() => _TabGroupWidgetState();
}

class _TabGroupWidgetState extends State<TabGroupWidget>
    with TickerProviderStateMixin {
  late AnimationController _collapseController;
  late AnimationController _hoverController;
  late Animation<double> _collapseAnimation;
  late Animation<double> _hoverAnimation;
  
  bool _isHovering = false;
  bool _isDraggingOver = false;
  String? _draggedTabId;

  @override
  void initState() {
    super.initState();
    
    _collapseController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _collapseAnimation = CurvedAnimation(
      parent: _collapseController,
      curve: Curves.easeInOut,
    );
    
    _hoverAnimation = CurvedAnimation(
      parent: _hoverController,
      curve: Curves.easeInOut,
    );

    // Listen to tab group events
    final groupManager = TerminalTabGroupManager();
    groupManager.events.listen((event) {
      _handleTabGroupEvent(event);
    });

    // Set initial animation state
    if (widget.group.isCollapsed) {
      _collapseController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(TabGroupWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update collapse animation when group state changes
    if (widget.group.isCollapsed != oldWidget.group.isCollapsed) {
      if (widget.group.isCollapsed) {
        _collapseController.forward();
      } else {
        _collapseController.reverse();
      }
    }
  }

  void _handleTabGroupEvent(TabGroupEvent event) {
    switch (event.type) {
      case TabGroupEventType.dragHover:
        final hoveredGroupId = event.data?['hovered_group_id'] as String?;
        final isDraggingOver = event.data?['is_dragging_over'] as bool? ?? false;
        
        if (mounted && hoveredGroupId == widget.group.id) {
          setState(() {
            _isDraggingOver = isDraggingOver;
          });
          
          if (isDraggingOver) {
            _hoverController.forward();
          } else {
            _hoverController.reverse();
          }
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Group header with colored line indicator
        _buildGroupHeader(),
        
        // Tabs container with animation
        AnimatedBuilder(
          animation: _collapseAnimation,
          builder: (context, child) {
            return SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: _collapseController,
                curve: Curves.easeInOut,
              ),
              axis: Axis.vertical,
              child: child,
            );
          },
          child: widget.group.isCollapsed ? null : _buildTabsContainer(),
        ),
      ],
    );
  }

  Widget _buildGroupHeader() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: widget.group.color,
            width: 4,
          ),
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
        color: widget.isActive 
            ? Theme.of(context).colorScheme.surfaceVariant
            : Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          // Colored line indicator (clickable for collapse/expand)
          GestureDetector(
            onTap: () {
              if (widget.group.isCollapsed) {
                widget.onGroupExpanded?.call(widget.group.id);
              } else {
                widget.onGroupCollapsed?.call(widget.group.id);
              }
            },
            child: Container(
              width: 4,
              height: 32,
              color: widget.group.color,
              child: Icon(
                widget.group.isCollapsed ? Icons.chevron_right : Icons.chevron_down,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
          
          // Group name
          Expanded(
            child: GestureDetector(
              onLongPress: () => _showGroupContextMenu(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      widget.group.name,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal,
                        color: widget.group.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.group.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${widget.tabs.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: widget.group.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Drag indicator when hovering
          AnimatedBuilder(
            animation: _hoverAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _isDraggingOver ? _hoverAnimation.value : 0.0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.group.color.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.add,
                    color: widget.group.color,
                    size: 16,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabsContainer() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: widget.group.color.withOpacity(0.3),
            width: 4,
          ),
        ),
      ),
      child: Column(
        children: widget.tabs.map((tab) => _buildTab(tab)).toList(),
      ),
    );
  }

  Widget _buildTab(TerminalTab tab) {
    return DraggableTabWidget(
      key: ValueKey(tab.id),
      tab: tab,
      groupColor: widget.group.color,
      isActive: widget.isActive,
      onSelected: () => widget.onTabSelected?.call(tab.id),
      onClosed: () => widget.onTabClosed?.call(tab.id),
      onRenamed: (newName) => widget.onTabRenamed?.call(tab.id),
      onDragStarted: () => _handleTabDragStarted(tab.id),
      onDragEnded: (targetGroupId) => _handleTabDragEnded(tab.id, targetGroupId),
    );
  }

  void _handleTabDragStarted(String tabId) {
    final groupManager = TerminalTabGroupManager();
    groupManager.startDragTab(tabId);
  }

  void _handleTabDragEnded(String tabId, String? targetGroupId) {
    final groupManager = TerminalTabGroupManager();
    groupManager.endDragTab(tabId, targetGroupId: targetGroupId);
  }

  void _showGroupContextMenu(BuildContext context) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = Box.fromPoints(
      overlay.localToGlobal(Offset.zero) & overlay.size,
    );
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        result.left + 100,
        result.top + 50,
        result.right,
        result.bottom,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              const SizedBox(width: 8),
              Text('Rename Group'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'recolor',
          child: Row(
            children: [
              Icon(Icons.palette, size: 16),
              const SizedBox(width: 8),
              Text('Recolor Group'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16),
              const SizedBox(width: 8),
              Text('Delete Group'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleGroupContextMenuAction(value);
      }
    });
  }

  void _handleGroupContextMenuAction(String action) {
    switch (action) {
      case 'rename':
        _showRenameGroupDialog();
        break;
      case 'recolor':
        _showRecolorGroupDialog();
        break;
      case 'delete':
        _showDeleteGroupDialog();
        break;
    }
  }

  void _showRenameGroupDialog() {
    final controller = TextEditingController(text: widget.group.name);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename Group'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Group Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                widget.onGroupRenamed?.call(widget.group.id);
                Navigator.pop(context);
              }
            },
            child: Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showRecolorGroupDialog() {
    final groupManager = TerminalTabGroupManager();
    final availableColors = groupManager.getAvailableColors();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Recolor Group'),
        content: SizedBox(
          width: 300,
          height: 200,
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1,
            ),
            itemCount: availableColors.length,
            itemBuilder: (context, index) {
              final color = availableColors[index];
              return GestureDetector(
                onTap: () {
                  widget.onGroupRecolored?.call(widget.group.id);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: color == widget.group.color ? Colors.black : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Group'),
        content: Text(
          'Are you sure you want to delete the group "${widget.group.name}"? '
          'Tabs will be moved to the default group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              widget.onGroupDeleted?.call(widget.group.id);
              Navigator.pop(context);
            },
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _collapseController.dispose();
    _hoverController.dispose();
    super.dispose();
  }
}

/// Draggable Tab Widget
class DraggableTabWidget extends StatefulWidget {
  final TerminalTab tab;
  final Color groupColor;
  final bool isActive;
  final VoidCallback? onSelected;
  final VoidCallback? onClosed;
  final Function(String)? onRenamed;
  final VoidCallback? onDragStarted;
  final Function(String?)? onDragEnded;

  const DraggableTabWidget({
    Key? key,
    required this.tab,
    required this.groupColor,
    this.isActive = false,
    this.onSelected,
    this.onClosed,
    this.onRenamed,
    this.onDragStarted,
    this.onDragEnded,
  }) : super(key: key);

  @override
  State<DraggableTabWidget> createState() => _DraggableTabWidgetState();
}

class _DraggableTabWidgetState extends State<DraggableTabWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (data) => data != widget.tab.id,
      onAccept: (data) {
        // Handle tab drop (reordering or merging)
        widget.onDragEnded?.call(null);
      },
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<String>(
          data: widget.tab.id,
          onDragStarted: widget.onDragStarted,
          onDragEnd: (details) {
            // Find target group based on position
            widget.onDragEnded?.call(null);
          },
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: widget.groupColor.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.tab.title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            child: GestureDetector(
              onTap: widget.onSelected,
              onLongPress: () => _showTabContextMenu(context),
              child: Container(
                height: 32,
                decoration: BoxDecoration(
                  color: widget.isActive
                      ? Theme.of(context).colorScheme.primaryContainer
                      : _isHovering
                          ? Theme.of(context).colorScheme.surfaceVariant
                          : Theme.of(context).colorScheme.surface,
                  border: Border(
                    left: BorderSide(
                      color: widget.groupColor.withOpacity(0.5),
                      width: 2,
                    ),
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 16),
                    Icon(
                      _getTabIcon(),
                      size: 16,
                      color: widget.isActive
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.tab.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: widget.isActive
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isHovering)
                      IconButton(
                        onPressed: widget.onClosed,
                        icon: Icon(Icons.close, size: 16),
                        splashRadius: 12,
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

  IconData _getTabIcon() {
    // Return appropriate icon based on tab content/session type
    if (widget.tab.title.toLowerCase().contains('ssh')) {
      return Icons.terminal;
    } else if (widget.tab.title.toLowerCase().contains('docker')) {
      return Icons.dock;
    } else if (widget.tab.title.toLowerCase().contains('git')) {
      return Icons.code;
    } else {
      return Icons.computer;
    }
  }

  void _showTabContextMenu(BuildContext context) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = Box.fromPoints(
      overlay.localToGlobal(Offset.zero) & overlay.size,
    );
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        result.left + 100,
        result.top + 50,
        result.right,
        result.bottom,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              const SizedBox(width: 8),
              Text('Rename Tab'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'close',
          child: Row(
            children: [
              Icon(Icons.close, size: 16),
              const SizedBox(width: 8),
              Text('Close Tab'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleTabContextMenuAction(value);
      }
    });
  }

  void _handleTabContextMenuAction(String action) {
    switch (action) {
      case 'rename':
        _showRenameTabDialog();
        break;
      case 'close':
        widget.onClosed?.call();
        break;
    }
  }

  void _showRenameTabDialog() {
    final controller = TextEditingController(text: widget.tab.title);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename Tab'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Tab Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                widget.onRenamed?.call(controller.text);
                Navigator.pop(context);
              }
            },
            child: Text('Rename'),
          ),
        ],
      ),
    );
  }
}
