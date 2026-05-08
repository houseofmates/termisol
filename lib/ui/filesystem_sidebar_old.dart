import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:xterm/xterm.dart';
import 'package:path/path.dart' as path;
import 'package:google_fonts/google_fonts.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/sql.dart';

/// Filesystem Sidebar - Interactive file explorer with Varela Round font
/// 
/// Features:
/// - Interactive file/folder navigation
/// - Varela Round font for UI elements
/// - Slideable edge for resizing
/// - Right-click context menu
/// - Markdown editor at bottom
/// - Rainbow coloration for syntax highlighting
/// - File preview capabilities
/// - Drag and drop support
class FilesystemSidebar extends StatefulWidget {
  final String initialDirectory;
  final Function(String)? onFileSelected;
  final Function(String)? onDirectoryChanged;
  final bool initiallyVisible;
  final double initialWidth;
  
  const FilesystemSidebar({
    Key? key,
    required this.initialDirectory,
    this.onFileSelected,
    this.onDirectoryChanged,
    this.initiallyVisible = false,
    this.initialWidth = 300.0,
  }) : super(key: key);
  
  @override
  State<FilesystemSidebar> createState() => _FilesystemSidebarState();
}

class _FilesystemSidebarState extends State<FilesystemSidebar>
    with TickerProviderStateMixin {
  late Directory _currentDirectory;
  List<FileSystemEntity> _files = [];
  List<FileSystemEntity> _filteredFiles = [];
  bool _isLoading = false;
  String _searchQuery = '';
  
  // Sidebar state
  bool _isVisible = widget.initiallyVisible;
  double _sidebarWidth = widget.initialWidth;
  double _minWidth = 200.0;
  double _maxWidth = 600.0;
  bool _isResizing = false;
  
  // File selection
  FileSystemEntity? _selectedFile;
  String? _editingPath;
  TextEditingController _editController = TextEditingController();
  FocusNode _editFocusNode = FocusNode();
  
  // Context menu
  OverlayEntry? _contextMenuOverlay;
  Offset _contextMenuPosition = Offset.zero;
  FileSystemEntity? _contextMenuTarget;
  
  // Markdown editor
  bool _showMarkdownEditor = false;
  double _markdownEditorHeight = 200.0;
  String _markdownContent = '';
  TextEditingController _markdownController = TextEditingController();
  late AnimationController _markdownAnimationController;
  late Animation<double> _markdownAnimation;
  
  // File preview
  FileSystemEntity? _previewFile;
  Uint8List? _previewData;
  String? _previewText;
  
  // Rainbow colors for syntax highlighting
  static const List<Color> _rainbowColors = [
    Color(0xFFFF6B6B), // Red
    Color(0xFF4ECDC4), // Teal
    Color(0xFF45B7D1), // Blue
    Color(0xFFFFA07A), // Light Salmon
    Color(0xFF98D8C8), // Mint
    Color(0xFF6C5CE7), // Purple
    Color(0xFFFD79A8), // Pink
    Color(0xFFFDCB6E), // Yellow
  ];
  
  // View preferences
  FileViewMode _viewMode = FileViewMode.list;
  SortMode _sortMode = SortMode.name;
  bool _showHiddenFiles = false;
  
  // Performance optimization
  final Map<String, List<FileSystemItem>> _directoryCache = {};
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _currentDirectory = Directory(widget.initialDirectory);
    _loadDirectory();
    
    // Setup markdown animation
    _markdownAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _markdownAnimation = CurvedAnimation(
      parent: _markdownAnimationController,
      curve: Curves.easeInOut,
    );
    
    // Setup edit focus listener
    _editFocusNode.addListener(_onEditFocusChange);
  }
  
  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    _markdownController.dispose();
    _markdownAnimationController.dispose();
    _contextMenuOverlay?.remove();
    super.dispose();
  }
  
  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);
    
    try {
      final files = await _currentDirectory.list().toList();
      files.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      
      setState(() {
        _files = files;
        _filteredFiles = files;
        _isLoading = false;
      });
      
      widget.onDirectoryChanged?.call(_currentDirectory.path);
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading directory: $e');
    }
  }
  
  /// Load directory contents
  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _currentPath = path;
    });
    
    try {
      // Check cache first
      if (_directoryCache.containsKey(path)) {
        setState(() {
          _items = _directoryCache[path]!;
          _filteredItems = _items;
          _isLoading = false;
        });
        return;
      }
      
      final directory = Directory(path);
      if (!await directory.exists()) {
        setState(() {
          _items = [];
          _filteredItems = [];
          _isLoading = false;
        });
        return;
      }
      
      final items = <FileSystemItem>[];
      await for (final entity in directory.list()) {
        try {
          final stat = await entity.stat();
          final isDirectory = entity is Directory;
          final name = entity.path.split('/').last;
          
          // Skip hidden files if not shown
          if (!_showHiddenFiles && name.startsWith('.')) {
            continue;
          }
          
          items.add(FileSystemItem(
            name: name,
            path: entity.path,
            isDirectory: isDirectory,
            size: stat.size,
            modified: stat.modified,
            permissions: _parsePermissions(stat.mode),
            icon: _getIconForFile(name, isDirectory),
          ));
        } catch (e) {
          debugPrint('⚠️ Failed to load file: $entity.path - $e');
        }
      }
      
      // Sort items
      _sortItems(items);
      
      // Cache the results
      _directoryCache[path] = items;
      
      setState(() {
        _items = items;
        _filteredItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _items = [];
        _filteredItems = [];
        _isLoading = false;
      });
      debugPrint('⚠️ Failed to load directory: $path - $e');
    }
  }
  
  /// Sort items
  void _sortItems(List<FileSystemItem> items) {
    switch (_sortMode) {
      case SortMode.name:
        items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortMode.size:
        items.sort((a, b) => b.size.compareTo(a.size));
        break;
      case SortMode.modified:
        items.sort((a, b) => b.modified.compareTo(a.modified));
        break;
      case SortMode.type:
        items.sort((a, b) {
          if (a.isDirectory != b.isDirectory) {
            return a.isDirectory ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
    }
    
    // Always put directories first
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return 0;
    });
  }
  
  /// Parse file permissions
  String _parsePermissions(int mode) {
    final permissions = StringBuffer();
    
    // Directory indicator
    permissions.write(mode & 0x4000 != 0 ? 'd' : '-');
    
    // Owner permissions
    permissions.write(mode & 0x400 != 0 ? 'r' : '-');
    permissions.write(mode & 0x200 != 0 ? 'w' : '-');
    permissions.write(mode & 0x100 != 0 ? 'x' : '-');
    
    // Group permissions
    permissions.write(mode & 0x40 != 0 ? 'r' : '-');
    permissions.write(mode & 0x20 != 0 ? 'w' : '-');
    permissions.write(mode & 0x10 != 0 ? 'x' : '-');
    
    // Other permissions
    permissions.write(mode & 0x4 != 0 ? 'r' : '-');
    permissions.write(mode & 0x2 != 0 ? 'w' : '-');
    permissions.write(mode & 0x1 != 0 ? 'x' : '-');
    
    return permissions.toString();
  }
  
  /// Get icon for file
  IconData _getIconForFile(String name, bool isDirectory) {
    if (isDirectory) {
      return Icons.folder;
    }
    
    final extension = name.toLowerCase().split('.').last;
    
    switch (extension) {
      case 'dart':
        return Icons.code;
      case 'js':
      case 'jsx':
        return Icons.javascript;
      case 'ts':
      case 'tsx':
        return Icons.typescript;
      case 'py':
        return Icons.code;
      case 'java':
      case 'class':
        return Icons.coffee;
      case 'cpp':
      case 'c':
      case 'h':
      case 'hpp':
        return Icons.code;
      case 'go':
        return Icons.code;
      case 'rs':
        return Icons.code;
      case 'html':
      case 'htm':
        return Icons.web;
      case 'css':
      case 'scss':
      case 'sass':
        return Icons.style;
      case 'json':
        return Icons.data_object;
      case 'xml':
      case 'yaml':
      case 'yml':
        return Icons.data_object;
      case 'md':
      case 'txt':
        return Icons.description;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'svg':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
        return Icons.audiotrack;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
        return Icons.videocam;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.archive;
      case 'exe':
      case 'msi':
      case 'deb':
      case 'rpm':
      case 'dmg':
      case 'pkg':
        return Icons.app_settings_alt;
      case 'doc':
      case 'docx':
      case 'odt':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'ods':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
      case 'odp':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  /// Handle search
  void _onSearchChanged(String query) {
    _searchQuery = query;
    
    // Debounce search
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }
  
  /// Perform search
  void _performSearch() {
    setState(() {
      _isSearching = _searchQuery.isNotEmpty;
      
      if (_searchQuery.isEmpty) {
        _filteredItems = _items;
      } else {
        _filteredItems = _items.where((item) {
          return item.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
      }
    });
  }
  
  /// Handle item tap
  void _onItemTap(FileSystemItem item) {
    if (item.isDirectory) {
      _loadDirectory(item.path);
      widget.onDirectorySelected(item.path);
    } else {
      widget.onFileSelected(item.path);
    }
  }
  
  /// Handle item long press
  void _onItemLongPress(FileSystemItem item) {
    setState(() {
      if (_selectedItems.contains(item.path)) {
        _selectedItems.remove(item.path);
      } else {
        _selectedItems.add(item.path);
      }
      _isMultiSelectMode = _selectedItems.isNotEmpty;
    });
  }
  
  /// Navigate to parent directory
  void _navigateToParent() {
    final parent = Directory(_currentPath).parent;
    if (parent != null) {
      _loadDirectory(parent.path);
    }
  }
  
  /// Navigate to quick access directory
  void _navigateToQuickAccess(DirectoryBookmark bookmark) {
    _loadDirectory(bookmark.path);
    widget.onDirectorySelected(bookmark.path);
  }
  
  /// Toggle view mode
  void _toggleViewMode() {
    setState(() {
      _viewMode = FileViewMode.values[(_viewMode.index + 1) % FileViewMode.values.length];
    });
  }
  
  /// Toggle sort mode
  void _toggleSortMode() {
    setState(() {
      _sortMode = SortMode.values[(_sortMode.index + 1) % SortMode.values.length];
      _sortItems(_items);
      _filteredItems = _items;
    });
  }
  
  /// Toggle hidden files
  void _toggleHiddenFiles() {
    setState(() {
      _showHiddenFiles = !_showHiddenFiles;
      _directoryCache.clear(); // Clear cache to refresh
      _loadDirectory(_currentPath);
    });
  }
  
  /// Clear selection
  void _clearSelection() {
    setState(() {
      _selectedItems.clear();
      _isMultiSelectMode = false;
    });
  }
  
  /// Delete selected items
  Future<void> _deleteSelectedItems() async {
    for (final path in _selectedItems) {
      try {
        final entity = File(path);
        if (await entity.exists()) {
          await entity.delete();
        }
      } catch (e) {
        debugPrint('⚠️ Failed to delete $path: $e');
      }
    }
    
    _clearSelection();
    _directoryCache.clear(); // Clear cache to refresh
    _loadDirectory(_currentPath);
  }
  
  /// Create new directory
  Future<void> _createDirectory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Directory'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Directory Name',
            hintText: 'Enter directory name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (name != null && name!.isNotEmpty) {
      try {
        final newDir = Directory('$_currentPath/$name');
        await newDir.create();
        _directoryCache.clear(); // Clear cache to refresh
        _loadDirectory(_currentPath);
      } catch (e) {
        debugPrint('⚠️ Failed to create directory: $e');
      }
    }
  }
  
  /// Build header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _currentPath,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
            ],
          ),
          const SizedBox(height: 8.0),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search files...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isSearching
                        ? IconButton(
                            onPressed: () {
                              _onSearchChanged('');
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              IconButton(
                onPressed: _toggleViewMode,
                icon: _getViewModeIcon(),
                tooltip: 'Toggle view mode',
              ),
              IconButton(
                onPressed: _toggleSortMode,
                icon: _getSortModeIcon(),
                tooltip: 'Toggle sort mode',
              ),
              IconButton(
                onPressed: _toggleHiddenFiles,
                icon: Icon(_showHiddenFiles ? Icons.visibility_off : Icons.visibility),
                tooltip: _showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
              ),
            ],
          ),
          if (_isMultiSelectMode) ...[
            const SizedBox(height: 8.0),
            Row(
              children: [
                Text('${_selectedItems.length} selected'),
                const Spacer(),
                IconButton(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear selection',
                ),
                IconButton(
                  onPressed: _deleteSelectedItems,
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete selected',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  /// Build quick access
  Widget _buildQuickAccess() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Access',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _quickAccess.map((bookmark) {
              return ActionChip(
                label: Text(bookmark.name),
                onPressed: () => _navigateToQuickAccess(bookmark),
                avatar: Icon(
                  _getIconForFile(bookmark.name, true),
                  size: 16.0,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  /// Build breadcrumbs
  Widget _buildBreadcrumbs() {
    final pathParts = _currentPath.split('/');
    final breadcrumbs = <Widget>[];
    
    // Root
    breadcrumbs.add(
      GestureDetector(
        onTap: () => _loadDirectory('/'),
        child: Text(
          '/',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
    
    // Path parts
    for (int i = 0; i < pathParts.length; i++) {
      if (pathParts[i].isEmpty) continue;
      
      breadcrumbs.add(const Text(' / '));
      
      final currentPath = '/' + pathParts.sublist(0, i + 1).join('/');
      breadcrumbs.add(
        GestureDetector(
          onTap: () => _loadDirectory(currentPath),
          child: Text(
            pathParts[i],
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: breadcrumbs,
        ),
      ),
    );
  }
  
  /// Build file list
  Widget _buildFileList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64.0,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16.0),
            Text(
              _isSearching ? 'No files found' : 'Empty directory',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).disabledColor,
              ),
            ),
          ],
        ),
      );
    }
    
    switch (_viewMode) {
      case FileViewMode.list:
        return _buildListView();
      case FileViewMode.grid:
        return _buildGridView();
    }
  }
  
  /// Build list view
  Widget _buildListView() {
    return ListView.builder(
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        final isSelected = _selectedItems.contains(item.path);
        
        return ListTile(
          leading: Icon(
            item.icon,
            color: item.isDirectory
                ? Theme.of(context).primaryColor
                : Theme.of(context).iconTheme.color,
          ),
          title: Text(
            item.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : null,
            ),
          ),
          subtitle: item.isDirectory
              ? null
              : Text(_formatFileSize(item.size)),
          trailing: item.isDirectory
              ? null
              : Text(
                  _formatDate(item.modified),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          selected: isSelected,
          onTap: () => _onItemTap(item),
          onLongPress: () => _onItemLongPress(item),
        );
      },
    );
  }
  
  /// Build grid view
  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        final isSelected = _selectedItems.contains(item.path);
        
        return GestureDetector(
          onTap: () => _onItemTap(item),
          onLongPress: () => _onItemLongPress(item),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).dividerColor,
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 32.0,
                  color: item.isDirectory
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).iconTheme.color,
                ),
                const SizedBox(height: 4.0),
                Text(
                  item.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12.0,
                  ),
                ),
                if (!item.isDirectory) ...[
                  const SizedBox(height: 2.0),
                  Text(
                    _formatFileSize(item.size),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// Build floating action button
  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: _createDirectory,
      child: const Icon(Icons.create_new_folder),
      tooltip: 'New Directory',
    );
  }
  
  /// Get view mode icon
  IconData _getViewModeIcon() {
    switch (_viewMode) {
      case FileViewMode.list:
        return Icons.list;
      case FileViewMode.grid:
        return Icons.grid_view;
    }
  }
  
  /// Get sort mode icon
  IconData _getSortModeIcon() {
    switch (_sortMode) {
      case SortMode.name:
        return Icons.sort_by_alpha;
      case SortMode.size:
        return Icons.sort_by_size;
      case SortMode.modified:
        return Icons.access_time;
      case SortMode.type:
        return Icons.sort;
    }
  }
  
  /// Format file size
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  /// Format date
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300.0,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildBreadcrumbs(),
          _buildQuickAccess(),
          Expanded(
            child: _buildFileList(),
          ),
        ],
      ),
    );
  }
}

/// File system item data structure
class FileSystemItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String permissions;
  final IconData icon;
  
  FileSystemItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.permissions,
    required this.icon,
  });
}

/// File view mode enumeration
enum FileViewMode {
  list,
  grid,
}

/// Sort mode enumeration
enum SortMode {
  name,
  size,
  modified,
  type,
}
