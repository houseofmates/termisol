import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../config/pkm_theme.dart';

/// File browser widget closely matching vibecode's file tree design.
///
/// Features:
/// - Recursive tree with toggle expansion arrows (▸ / ▾)
/// - Inline rename via double-click
/// - Right-click context menu (rename, delete)
/// - File type icons based on extension
/// - Breadcrumb bar for directory navigation
/// - New file/folder creation
/// - File preview (text, markdown, images)
/// - Parent directory navigation
/// - Refresh capability
class FileBrowser extends StatefulWidget {
  final String rootPath;
  final ValueChanged<String>? onFileSelected;

  const FileBrowser({
    super.key,
    required this.rootPath,
    this.onFileSelected,
  });

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  String _currentPath = '';
  List<FileSystemEntity> _entries = [];
  final Set<String> _expandedDirs = {};
  final Map<String, List<FileSystemEntity>> _dirCache = {};

  String? _previewFilePath;
  String? _previewContent;
  String? _renameTargetPath;
  String? _renameTargetParent;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.rootPath;
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    try {
      final dir = Directory(_currentPath);
      if (!await dir.exists()) return;

      final list = await dir.list().toList();
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        final aName = a.path.split('/').last.toLowerCase();
        final bName = b.path.split('/').last.toLowerCase();
        return aName.compareTo(bName);
      });

      setState(() {
        _entries = list;
        _dirCache[_currentPath] = list;
      });
    } catch (e) {
      debugPrint('📁 Failed to load directory $_currentPath: $e');
    }
  }

  Future<void> _loadChildren(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return;

      final list = await dir.list().toList();
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        final aName = a.path.split('/').last.toLowerCase();
        final bName = b.path.split('/').last.toLowerCase();
        return aName.compareTo(bName);
      });

      _dirCache[path] = list;
    } catch (e) {
      _dirCache[path] = [];
    }
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
      _previewFilePath = null;
      _previewContent = null;
    });
    _loadDirectory();
  }

  void _navigateUp() {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) {
      _navigateTo(parent);
    }
  }

  Future<void> _createFile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PkmTheme.popup,
        title: const Text('new file', style: TextStyle(color: PkmTheme.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: PkmTheme.text),
          decoration: const InputDecoration(
            hintText: 'filename.ext',
            hintStyle: TextStyle(color: PkmTheme.secondary),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('cancel', style: TextStyle(color: PkmTheme.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('create', style: TextStyle(color: PkmTheme.primary)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.trim().isNotEmpty) {
      final file = File('$_currentPath/${name.trim()}');
      await file.create(recursive: true);
      _loadDirectory();
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PkmTheme.popup,
        title: const Text('new folder', style: TextStyle(color: PkmTheme.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: PkmTheme.text),
          decoration: const InputDecoration(
            hintText: 'folder-name',
            hintStyle: TextStyle(color: PkmTheme.secondary),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('cancel', style: TextStyle(color: PkmTheme.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('create', style: TextStyle(color: PkmTheme.primary)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name != null && name.trim().isNotEmpty) {
      final dir = Directory('$_currentPath/${name.trim()}');
      await dir.create(recursive: true);
      _loadDirectory();
    }
  }

  Future<void> _deleteEntity(String path) async {
    final name = path.split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PkmTheme.popup,
        title: Text('delete $name?', style: const TextStyle(color: Colors.red)),
        content: Text('This will permanently delete $name', style: const TextStyle(color: PkmTheme.secondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('cancel', style: TextStyle(color: PkmTheme.secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final entity = FileSystemEntity.typeSync(path);
      if (entity == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
        _dirCache.remove(path);
        _expandedDirs.remove(path);
      } else {
        await File(path).delete();
      }
      _loadDirectory();
    }
  }

  Future<void> _startRename(String path) async {
    final name = path.split('/').last;
    final parent = Directory(path).parent.path;

    setState(() {
      _renameTargetPath = path;
      _renameTargetParent = parent;
    });
  }

  Future<void> _finishRename(String newName) async {
    final oldPath = _renameTargetPath;
    if (oldPath == null) return;

    final parent = _renameTargetParent ?? Directory(oldPath).parent.path;
    final newPath = '$parent/$newName';

    try {
      final entity = FileSystemEntity.typeSync(oldPath);
      if (entity == FileSystemEntityType.directory) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }
      _dirCache.clear();
      _expandedDirs.clear();
      _loadDirectory();
    } catch (e) {
      debugPrint('📁 Rename failed: $e');
    }

    setState(() {
      _renameTargetPath = null;
      _renameTargetParent = null;
    });
  }

  void _cancelRename() {
    setState(() {
      _renameTargetPath = null;
      _renameTargetParent = null;
    });
  }

  Future<void> _openFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;

      final ext = path.split('.').last.toLowerCase();
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
      final isText = !isImage && !['pdf', 'zip', 'tar', 'gz', 'exe', 'dll', 'so'].contains(ext);

      if (isText) {
        final content = await file.readAsString();
        setState(() {
          _previewFilePath = path;
          _previewContent = content;
        });
      } else {
        setState(() {
          _previewFilePath = path;
          _previewContent = '[Binary file: $ext]';
        });
      }

      widget.onFileSelected?.call(path);
    } catch (e) {
      setState(() {
        _previewFilePath = path;
        _previewContent = 'Failed to open: $e';
      });
    }
  }

  void _clearPreview() {
    setState(() {
      _previewFilePath = null;
      _previewContent = null;
    });
  }

  IconData _fileIcon(String name, bool isDir) {
    if (isDir) return Icons.folder_outlined;

    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return Icons.code;
      case 'py': return Icons.code;
      case 'js': case 'ts': case 'jsx': case 'tsx': return Icons.bolt;
      case 'json': case 'yaml': case 'yml': case 'toml': return Icons.settings;
      case 'sh': case 'bash': return Icons.terminal;
      case 'md': case 'markdown': return Icons.article;
      case 'pdf': return Icons.picture_as_pdf;
      case 'zip': case 'tar': case 'gz': return Icons.archive;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return Icons.image;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Color _fileIconColor(String name, bool isDir) {
    if (isDir) return const Color(0xFF7CB9FF);
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return const Color(0xFF00B4AB);
      case 'py': return const Color(0xFF3572A5);
      case 'js': case 'ts': case 'jsx': case 'tsx': return const Color(0xFFF0DB4F);
      case 'json': case 'yaml': case 'yml': return const Color(0xFFF44336);
      case 'sh': case 'bash': return const Color(0xFF89E051);
      case 'md': return const Color(0xFFC9A84C);
      default: return PkmTheme.secondary;
    }
  }

  List<TextSpan> _buildBreadcrumb() {
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    final spans = <TextSpan>[];

    // Root
    spans.add(TextSpan(
      text: '~',
      style: TextStyle(
        color: PkmTheme.secondary,
        fontFamily: PkmTheme.fontUi,
        fontSize: 12,
        decoration: TextDecoration.underline,
      ),
    ));

    String accumulated = '';
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: '/',
        style: TextStyle(color: PkmTheme.border, fontSize: 11),
      ));
      accumulated += (accumulated.isEmpty ? '' : '/') + parts[i];

      if (i == parts.length - 1) {
        spans.add(TextSpan(
          text: parts[i],
          style: TextStyle(
            color: PkmTheme.text,
            fontFamily: PkmTheme.fontUi,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ));
      } else {
        final target = accumulated;
        spans.add(TextSpan(
          text: parts[i],
          style: TextStyle(
            color: PkmTheme.secondary,
            fontFamily: PkmTheme.fontUi,
            fontSize: 12,
            decoration: TextDecoration.underline,
          ),
        ));
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: const Color(0xFF0a0a0a),
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: const Color(0xFF1a1a1a), width: 1)),
            ),
            child: Row(
              children: [
                const Text(
                  'workspace',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                  ),
                ),
                const Spacer(),
                _headerButton(Icons.arrow_upward, 'parent directory', _navigateUp),
                _headerButton(Icons.add, 'new file', _createFile),
                _headerButton(Icons.create_new_folder_outlined, 'new folder', _createFolder),
                _headerButton(Icons.refresh, 'refresh', _loadDirectory),
              ],
            ),
          ),

          // ── Breadcrumb ──
          if (_currentPath != widget.rootPath)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: const Color(0xFF1a1a1a), width: 1)),
              ),
              child: GestureDetector(
                onTap: _navigateUp,
                child: RichText(
                  text: TextSpan(children: _buildBreadcrumb()),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // ── Preview or File Tree ──
          Expanded(
            child: _previewFilePath != null ? _buildPreview() : _buildFileTree(),
          ),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: const Color(0xFF666666)),
        ),
      ),
    );
  }

  Widget _buildFileTree() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: _entries.map((entity) => _buildFileTreeItem(entity, 0)).toList(),
    );
  }

  Widget _buildFileTreeItem(FileSystemEntity entity, int depth) {
    final name = entity.path.split('/').last;
    final isDir = entity is Directory;
    final isExpanded = _expandedDirs.contains(entity.path);
    final isRenaming = _renameTargetPath == entity.path;
    final baseLeft = 8 + depth * 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (isDir) {
              setState(() {
                if (_expandedDirs.contains(entity.path)) {
                  _expandedDirs.remove(entity.path);
                } else {
                  _expandedDirs.add(entity.path);
                  if (!_dirCache.containsKey(entity.path)) {
                    _loadChildren(entity.path);
                  }
                }
              });
            } else {
              _openFile(entity.path);
            }
          },
          onDoubleTap: () => _startRename(entity.path),
          onSecondaryTap: () => _showContextMenu(entity),
          child: Container(
            height: 32,
            padding: EdgeInsets.only(left: baseLeft, right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _previewFilePath == entity.path
                  ? const Color(0xFF7CB9FF).withOpacity(0.12)
                  : null,
            ),
            child: Row(
              children: [
                if (isDir)
                  SizedBox(
                    width: 14,
                    child: Text(
                      isExpanded ? '\u25BE' : '\u25B8',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 11),
                    ),
                  )
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 6),
                Icon(
                  _fileIcon(name, isDir),
                  size: 14,
                  color: _fileIconColor(name, isDir).withOpacity(0.7),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: isRenaming
                      ? _buildRenameInput(entity.path, name)
                      : Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _previewFilePath == entity.path
                                ? const Color(0xFF7CB9FF)
                                : const Color(0xFF999999),
                            fontSize: 12,
                          ),
                        ),
                ),
                if (!isDir)
                  FutureBuilder<FileStat>(
                    future: File(entity.path).stat(),
                    builder: (ctx, snapshot) {
                      if (!snapshot.hasData) return const SizedBox();
                      final size = snapshot.data!.size;
                      return Text(
                        '${(size / 1024).toStringAsFixed(1)}k',
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        if (isDir && isExpanded)
          ...(_dirCache[entity.path] ?? [])
              .map((child) => _buildFileTreeItem(child, depth + 1)),
      ],
    );
  }

  Widget _buildRenameInput(String path, String currentName) {
    final controller = TextEditingController(text: currentName);

    return TextField(
      controller: controller,
      autofocus: true,
      style: TextStyle(
        color: PkmTheme.text,
        fontSize: 12,
        fontFamily: PkmTheme.fontTerminal,
      ),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        isDense: true,
      ),
      onSubmitted: (value) => _finishRename(value.trim()),
      onTapOutside: (_) => _cancelRename(),
    );
  }

  void _showContextMenu(FileSystemEntity entity) {
    final name = entity.path.split('/').last;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 200, 200, 300),
      color: const Color(0xFF0a0a0a),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Text(
            'rename',
            style: TextStyle(color: PkmTheme.text, fontFamily: PkmTheme.fontUi, fontSize: 12),
          ),
          onTap: () => _startRename(entity.path),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'delete',
            style: TextStyle(color: Colors.red.shade400, fontFamily: PkmTheme.fontUi, fontSize: 12),
          ),
          onTap: () => _deleteEntity(entity.path),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: const Color(0xFF1a1a1a), width: 1)),
          ),
          child: Row(
            children: [
              Text(
                _previewFilePath!.split('/').last,
                style: const TextStyle(color: Color(0xFF999999), fontSize: 11),
              ),
              const Spacer(),
              InkWell(
                onTap: _clearPreview,
                child: const Icon(Icons.close, size: 14, color: Color(0xFF666666)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              _previewContent ?? '',
              style: const TextStyle(
                color: Color(0xFFCDD6E0),
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}