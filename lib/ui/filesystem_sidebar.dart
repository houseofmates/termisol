import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
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
  
  void _filterFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredFiles = _files;
      } else {
        _filteredFiles = _files.where((file) {
          return path.basename(file.path)
              .toLowerCase()
              .contains(query.toLowerCase());
        }).toList();
      }
    });
  }
  
  void _navigateToDirectory(Directory directory) {
    setState(() {
      _currentDirectory = directory;
      _selectedFile = null;
      _previewFile = null;
      _previewData = null;
      _previewText = null;
    });
    _loadDirectory();
  }
  
  void _navigateToParent() {
    final parent = _currentDirectory.parent;
    if (parent.path != _currentDirectory.path) {
      _navigateToDirectory(parent);
    }
  }
  
  Future<void> _selectFile(FileSystemEntity file) async {
    setState(() {
      _selectedFile = file;
      _previewFile = file;
    });
    
    if (file is File) {
      await _loadFilePreview(file);
    }
    
    widget.onFileSelected?.call(file.path);
  }
  
  Future<void> _loadFilePreview(File file) async {
    try {
      final size = await file.length();
      if (size > 1024 * 1024) { // 1MB limit
        setState(() {
          _previewText = 'File too large for preview (${(size / 1024 / 1024).toStringAsFixed(1)}MB)';
        });
        return;
      }
      
      final bytes = await file.readAsBytes();
      final extension = path.extension(file.path).toLowerCase();
      
      if (_isTextFile(extension)) {
        final content = utf8.decode(bytes);
        setState(() {
          _previewData = bytes;
          _previewText = content;
        });
      } else {
        setState(() {
          _previewData = bytes;
          _previewText = 'Binary file: ${_formatFileSize(size)}';
        });
      }
    } catch (e) {
      setState(() {
        _previewText = 'Error loading file: $e';
      });
    }
  }
  
  bool _isTextFile(String extension) {
    final textExtensions = {
      '.txt', '.md', '.json', '.yaml', '.yml', '.toml', '.ini', '.conf',
      '.py', '.js', '.ts', '.dart', '.java', '.cpp', '.c', '.h', '.hpp',
      '.go', '.rs', '.sh', '.bash', '.zsh', '.fish', '.ps1', '.bat',
      '.html', '.css', '.scss', '.sass', '.less', '.xml', '.svg',
      '.log', '.sql', '.gitignore', '.dockerfile', 'dockerfile',
      '.env', '.cfg', '.plist', '.gradle', '.properties',
    };
    return textExtensions.contains(extension);
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  
  void _showContextMenu(BuildContext context, Offset position, FileSystemEntity target) {
    _hideContextMenu();
    
    _contextMenuPosition = position;
    _contextMenuTarget = target;
    
    _contextMenuOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx,
        top: position.dy,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (target is File) ...[
                  _buildContextMenuItem(
                    icon: Icons.edit,
                    label: 'Edit',
                    onTap: () => _startEditing(target),
                  ),
                  _buildContextMenuItem(
                    icon: Icons.content_copy,
                    label: 'Copy',
                    onTap: () => _copyFile(target),
                  ),
                  _buildContextMenuItem(
                    icon: Icons.cut,
                    label: 'Cut',
                    onTap: () => _cutFile(target),
                  ),
                ],
                _buildContextMenuItem(
                  icon: Icons.drive_file_rename_outline,
                  label: 'Rename',
                  onTap: () => _startRenaming(target),
                ),
                _buildContextMenuItem(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onTap: () => _deleteFile(target),
                ),
                if (target is Directory) ...[
                  _buildContextMenuItem(
                    icon: Icons.folder_open,
                    label: 'Open in Terminal',
                    onTap: () => _openInTerminal(target),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_contextMenuOverlay!);
  }
  
  Widget _buildContextMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        _hideContextMenu();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.varelaRound(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _hideContextMenu() {
    _contextMenuOverlay?.remove();
    _contextMenuOverlay = null;
  }
  
  void _startEditing(File file) {
    final extension = path.extension(file.path).toLowerCase();
    if (_isTextFile(extension)) {
      setState(() {
        _markdownContent = _previewText ?? '';
        _markdownController.text = _markdownContent;
        _showMarkdownEditor = true;
      });
      _markdownAnimationController.forward();
    }
  }
  
  void _startRenaming(FileSystemEntity target) {
    setState(() {
      _editingPath = target.path;
      _editController.text = path.basename(target.path);
    });
    _editFocusNode.requestFocus();
    _editController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _editController.text.length,
    );
  }
  
  Future<void> _finishEditing() async {
    if (_editingPath == null || _editController.text.isEmpty) {
      _cancelEditing();
      return;
    }
    
    try {
      final oldPath = _editingPath!;
      final newPath = path.join(path.dirname(oldPath), _editController.text);
      
      if (oldPath != newPath) {
        await File(oldPath).rename(newPath);
        _loadDirectory();
      }
    } catch (e) {
      debugPrint('Error renaming file: $e');
    }
    
    _cancelEditing();
  }
  
  void _cancelEditing() {
    setState(() {
      _editingPath = null;
      _editController.clear();
    });
  }
  
  void _onEditFocusChange() {
    if (!_editFocusNode.hasFocus && _editingPath != null) {
      _finishEditing();
    }
  }
  
  Future<void> _deleteFile(FileSystemEntity target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${target is Directory ? 'Directory' : 'File'}'),
        content: Text('Are you sure you want to delete "${path.basename(target.path)}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: GoogleFonts.varelaRound()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: GoogleFonts.varelaRound()),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        if (target is Directory) {
          await target.delete(recursive: true);
        } else {
          await target.delete();
        }
        _loadDirectory();
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }
    }
  }
  
  void _copyFile(FileSystemEntity target) {
    // Implementation would copy file to clipboard
    debugPrint('Copy file: ${target.path}');
  }
  
  void _cutFile(FileSystemEntity target) {
    // Implementation would cut file to clipboard
    debugPrint('Cut file: ${target.path}');
  }
  
  void _openInTerminal(Directory directory) {
    // Implementation would change terminal working directory
    debugPrint('Open in terminal: ${directory.path}');
  }
  
  void _toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }
  
  void _startResize(DragStartDetails details) {
    setState(() => _isResizing = true);
  }
  
  void _updateResize(DragUpdateDetails details) {
    if (!_isResizing) return;
    
    final newWidth = (_sidebarWidth + details.delta.dx)
        .clamp(_minWidth, _maxWidth);
    setState(() => _sidebarWidth = newWidth);
  }
  
  void _endResize(DragEndDetails details) {
    setState(() => _isResizing = false);
  }
  
  Color _getRainbowColor(int index) {
    return _rainbowColors[index % _rainbowColors.length];
  }
  
  String _getLanguageFromExtension(String extension) {
    final languageMap = {
      '.dart': 'dart',
      '.py': 'python',
      '.js': 'javascript',
      '.ts': 'javascript',
      '.json': 'json',
      '.yaml': 'yaml',
      '.yml': 'yaml',
      '.md': 'markdown',
      '.sh': 'bash',
      '.bash': 'bash',
      '.zsh': 'bash',
      '.fish': 'bash',
      '.cpp': 'cpp',
      '.c': 'cpp',
      '.java': 'java',
      '.go': 'go',
      '.rs': 'rust',
      '.sql': 'sql',
    };
    return languageMap[extension] ?? 'plaintext';
  }
  
  String _highlightCode(String code, String language) {
    try {
      final result = highlight.highlight(
        code,
        language: language,
        theme: highlight.themeMap['github']!,
      );
      return result.toHtml();
    } catch (e) {
      return code;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }
    
    return Row(
      children: [
        // Main sidebar
        Container(
          width: _sidebarWidth,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(),
              
              // Search bar
              _buildSearchBar(),
              
              // File list
              Expanded(
                child: _buildFileList(),
              ),
              
              // Markdown editor
              _buildMarkdownEditor(),
            ],
          ),
        ),
        
        // Resize handle
        GestureDetector(
          onHorizontalDragStart: _startResize,
          onHorizontalDragUpdate: _updateResize,
          onHorizontalDragEnd: _endResize,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: _isResizing ? Colors.blue.withOpacity(0.5) : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Icon(
              Icons.drag_handle,
              size: 16,
              color: Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path.basename(_currentDirectory.path),
              style: GoogleFonts.varelaRound(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: _navigateToParent,
            icon: const Icon(Icons.arrow_upward),
            iconSize: 20,
          ),
          IconButton(
            onPressed: _loadDirectory,
            icon: const Icon(Icons.refresh),
            iconSize: 20,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: TextField(
        onChanged: _filterFiles,
        style: GoogleFonts.varelaRound(),
        decoration: InputDecoration(
          hintText: 'Search files...',
          hintStyle: GoogleFonts.varelaRound(color: Colors.grey),
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          isDense: true,
        ),
      ),
    );
  }
  
  Widget _buildFileList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return ListView.builder(
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        final isSelected = _selectedFile?.path == file.path;
        final isEditing = _editingPath == file.path;
        final fileName = path.basename(file.path);
        final isDirectory = file is Directory;
        
        return Container(
          decoration: BoxDecoration(
            color: isSelected 
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
          ),
          child: GestureDetector(
            onTap: () {
              if (isDirectory) {
                _navigateToDirectory(file);
              } else {
                _selectFile(file);
              }
            },
            onSecondaryTapDown: (details) {
              _showContextMenu(
                context,
                details.globalPosition,
                file,
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isDirectory ? Icons.folder : _getFileIcon(file),
                    size: 20,
                    color: isDirectory 
                        ? Colors.blue
                        : _getRainbowColor(index),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: isEditing
                        ? TextField(
                            controller: _editController,
                            focusNode: _editFocusNode,
                            style: GoogleFonts.varelaRound(),
                            onSubmitted: (_) => _finishEditing(),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              isDense: true,
                            ),
                          )
                        : Text(
                            fileName,
                            style: GoogleFonts.varelaRound(
                              fontSize: 14,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (!isDirectory && !isEditing)
                    Text(
                      _formatFileSize(file.statSync().size),
                      style: GoogleFonts.varelaRound(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildMarkdownEditor() {
    return SizeTransition(
      sizeFactor: _markdownAnimation,
      child: Container(
        height: _markdownEditorHeight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
        ),
        child: Column(
          children: [
            // Editor header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Markdown Editor',
                    style: GoogleFonts.varelaRound(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      _markdownAnimationController.reverse();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        setState(() => _showMarkdownEditor = false);
                      });
                    },
                    icon: const Icon(Icons.close),
                    iconSize: 16,
                  ),
                ],
              ),
            ),
            
            // Editor content
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _markdownController,
                  maxLines: null,
                  expands: true,
                  style: GoogleFonts.varelaRound(
                    fontSize: 14,
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Start typing markdown...',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  IconData _getFileIcon(FileSystemEntity file) {
    final extension = path.extension(file.path).toLowerCase();
    
    switch (extension) {
      case '.dart':
        return Icons.code;
      case '.py':
        return Icons.code;
      case '.js':
      case '.ts':
        return Icons.javascript;
      case '.json':
        return Icons.data_object;
      case '.yaml':
      case '.yml':
        return Icons.description;
      case '.md':
        return Icons.article;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
        return Icons.image;
      case '.mp4':
      case '.avi':
      case '.mov':
      case '.webm':
        return Icons.video_file;
      case '.mp3':
      case '.wav':
      case '.ogg':
        return Icons.audio_file;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.zip':
      case '.tar':
      case '.gz':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }
}

/// Rainbow syntax highlighter for various file types
class RainbowHighlighter {
  static const Map<String, List<Color>> _languageColors = {
    'dart': [
      Color(0xFF00BCD4), // Cyan for classes
      Color(0xFF4CAF50), // Green for keywords
      Color(0xFFFF9800), // Orange for strings
      Color(0xFF9C27B0), // Purple for methods
      Color(0xFFF44336), // Red for comments
    ],
    'python': [
      Color(0xFF3776AB), // Blue for keywords
      Color(0xFFFFD43B), // Yellow for strings
      Color(0xFF646464), // Gray for comments
      Color(0xFF00A86B), // Green for functions
      Color(0xFF306998), // Dark blue for classes
    ],
    'javascript': [
      Color(0xFFF7DF1E), // Yellow for keywords
      Color(0xFF323330), // Dark for strings
      Color(0xFF646464), // Gray for comments
      Color(0xFF007396), // Blue for functions
      Color(0xFFE535AB), // Pink for classes,
    ],
    'json': [
      Color(0xFF000000), // Black for keys
      Color(0xFF008000), // Green for string values
      Color(0xFF0000FF), // Blue for numbers
      Color(0xFFFF0000), // Red for booleans
    ],
    'markdown': [
      Color(0xFF2E7EE6), // Blue for headers
      Color(0xFF5A5A5A), // Gray for text
      Color(0xFF008000), // Green for links
      Color(0xFFFF6B6B), // Red for emphasis
    ],
  };
  
  static List<Color> getColorsForLanguage(String language) {
    return _languageColors[language] ?? [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];
  }
}
