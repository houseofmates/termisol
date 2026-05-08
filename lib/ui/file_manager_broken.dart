import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import '../core/video_player.dart';
import '../core/audio_visualizer.dart';
import '../core/model_3d_viewer.dart';
import '../core/graphics_protocol_handler.dart';
import 'text_editor.dart';

/// Built-in file manager with editing preview sidebar for Termisol
/// 
/// Features:
/// - File system navigation
/// - File preview and editing
/// - Multi-format support
/// - Terminal integration
/// - Drag and drop support
/// - Right-click context menus
/// - Full file operations
class TerminalFileManager extends StatefulWidget {
  final Function(String)? onFileSelected;
  final Function(String)? onFileEdited;
  final String? initialPath;
  final bool showHiddenFiles;
  
  const TerminalFileManager({
    super.key,
    this.onFileSelected,
    this.onFileEdited,
    this.initialPath,
    this.showHiddenFiles = false,
  });
  
  @override
  State<TerminalFileManager> createState() => _TerminalFileManagerState();
}

class _TerminalFileManagerState extends State<TerminalFileManager> 
    with TickerProviderStateMixin {
  String _currentPath = Directory.current.path;
  List<FileSystemEntity> _files = [];
  FileSystemEntity? _selectedFile;
  String? _editingContent;
  bool _isEditing = false;
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final TextEditingController _renameController = TextEditingController();
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    if (widget.initialPath != null) {
      _currentPath = widget.initialPath!;
    }
    
    _loadDirectory();
  }
  
  Future<void> _loadDirectory() async {
    try {
      setState(() => _isLoading = true);
      
      final directory = Directory(_currentPath);
      if (!await directory.exists()) {
        throw Exception('Directory does not exist');
      }
      
      final files = await directory.list().toList();
      
      // Filter hidden files if not showing them
      final filteredFiles = widget.showHiddenFiles 
          ? files 
          : files.where((file) => !path.basename(file.path).startsWith('.')).toList();
      
      // Sort files: directories first, then files, alphabetically
      filteredFiles.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      
      setState(() {
        _files = filteredFiles;
        _isLoading = false;
        _error = null;
      });
      
    } catch (e) {
      setState(() {
        _error = 'Failed to load directory: $e';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _navigateToDirectory(String path) async {
    setState(() {
      _currentPath = path;
      _selectedFile = null;
      _editingContent = null;
      _isEditing = false;
    });
    
    await _loadDirectory();
  }
  
  Future<void> _selectFile(FileSystemEntity file) async {
    setState(() {
      _selectedFile = file;
      _isEditing = false;
    });
    
    if (file is File) {
      await _loadFileContent(file);
    }
  }
  
  Future<void> _loadFileContent(File file) async {
    try {
      final content = await file.readAsString();
      setState(() {
        _editingContent = content;
        _editController.text = content;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load file content: $e';
      });
    }
  }
  
  Future<void> _saveFile() async {
    if (_selectedFile is! File || _editingContent == null) return;
    
    try {
      await (_selectedFile as File).writeAsString(_editingContent!);
      
      widget.onFileEdited?.call(_selectedFile!.path);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _createNewFile() async {
    final controller = TextEditingController();
    final fileName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter file name...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (fileName != null && fileName.isNotEmpty) {
      try {
        final newFile = File(path.join(_currentPath, fileName));
        await newFile.writeAsString('');
        
        await _loadDirectory();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _createNewDirectory() async {
    final controller = TextEditingController();
    final dirName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Directory'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter directory name...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    
    if (dirName != null && dirName.isNotEmpty) {
      try {
        final newDir = Directory(path.join(_currentPath, dirName));
        await newDir.create();
        
        await _loadDirectory();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Directory created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create directory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _deleteFile(FileSystemEntity file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete ${path.basename(file.path)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        if (file is File) {
          await file.delete();
        } else if (file is Directory) {
          await file.delete(recursive: true);
        }
        
        await _loadDirectory();
        
        if (_selectedFile == file) {
          setState(() {
            _selectedFile = null;
            _editingContent = null;
            _isEditing = false;
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _renameFile(FileSystemEntity file) async {
    _renameController.text = path.basename(file.path);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: _renameController,
          decoration: const InputDecoration(
            hintText: 'Enter new name...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _renameController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    
    if (newName != null && newName.isNotEmpty && newName != path.basename(file.path)) {
      try {
        final newPath = path.join(path.dirname(file.path), newName);
        await file.rename(newPath);
        
        await _loadDirectory();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renamed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _copyFile(FileSystemEntity file) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save copy as...',
        fileName: path.basename(file.path),
      );
      
      if (result != null && file is File) {
        await file.copy(result.files.single.path!);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File copied successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }
  
  void _onEditChanged(String content) {
    setState(() {
      _editingContent = content;
    });
  }
  
  void _showFileContextMenu(FileSystemEntity file) {
    final fileName = path.basename(file.path);
    final isDirectory = file is Directory;
    final isFile = file is File;
    
    showMenu(
      context: context,
      position: RelativeRect.fromSize(
        size: Size.zero,
        anchor: Size.zero,
      ),
      items: [
        if (isFile) ...[
          PopupMenuItem(
            onTap: () {
              Navigator.pop(context);
              _selectFile(file);
              _toggleEdit();
            },
            child: const Row(
              children: [
                Icon(Icons.edit, size: 16),
                SizedBox(width: 8),
                Text('Edit'),
              ],
            ),
          ),
          PopupMenuItem(
            onTap: () {
              Navigator.pop(context);
              _copyFile(file);
            },
            child: const Row(
              children: [
                Icon(Icons.copy, size: 16),
                SizedBox(width: 8),
                Text('Copy'),
              ],
            ),
          ),
                           PopupMenuItem(
                             onTap: () {
                               Navigator.pop(context);
                               Clipboard.setData(ClipboardData(text: file.path));
                               ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Path copied to clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Row(
              children: [
                Icon(Icons.link, size: 16),
                SizedBox(width: 8),
                Text('Copy Path'),
              ],
            ),
          ),
        ],
        PopupMenuItem(
          onTap: () {
            Navigator.pop(context);
            _renameFile(file);
          },
          child: const Row(
            children: [
              Icon(Icons.drive_file_rename_outline, size: 16),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () {
            Navigator.pop(context);
            _deleteFile(file);
          },
          child: const Row(
            children: [
              Icon(Icons.delete, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
        if (isDirectory) ...[
          PopupMenuItem(
            onTap: () {
              Navigator.pop(context);
              _navigateToDirectory(file.path);
            },
            child: const Row(
              children: [
                Icon(Icons.folder_open, size: 16),
                SizedBox(width: 8),
                Text('Open'),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  List<FileSystemEntity> get _filteredFiles {
    if (_searchQuery.isEmpty) return _files;
    
    return _files.where((file) {
      final fileName = path.basename(file.path).toLowerCase();
      return fileName.contains(_searchQuery.toLowerCase());
    }).toList();
  }
  
  Widget _buildFileList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.grey),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDirectory,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Path bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentPath,
                  style: const TextStyle(color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => _navigateToDirectory(Directory(_currentPath).parent.path),
                icon: const Icon(Icons.arrow_upward, color: Colors.grey),
                tooltip: 'Parent Directory',
              ),
              IconButton(
                onPressed: _loadDirectory,
                icon: const Icon(Icons.refresh, color: Colors.grey),
                tooltip: 'Refresh',
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: _createNewFile,
                    child: const Row(
                      children: [
                        Icon(Icons.note_add, size: 16),
                        SizedBox(width: 8),
                        Text('New File'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: _createNewDirectory,
                    child: const Row(
                      children: [
                        Icon(Icons.create_new_folder, size: 16),
                        SizedBox(width: 8),
                        Text('New Folder'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search files...',
              hintStyle: TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
        ),
        
        // File list
        Expanded(
          child: ListView.builder(
            itemCount: _filteredFiles.length,
            itemBuilder: (context, index) {
              final file = _filteredFiles[index];
              final fileName = path.basename(file.path);
              final isDirectory = file is Directory;
              final isSelected = _selectedFile == file;
              
              return GestureDetector(
                onSecondaryTapDown: (details) {
                  _showFileContextMenu(file);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue[900]!.withOpacity(0.3) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.blue[400]! : Colors.transparent,
                      width: isSelected ? 2 : 0,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      isDirectory ? Icons.folder : _getFileIcon(fileName),
                      color: isSelected ? Colors.blue[400] : Colors.grey,
                      size: 24,
                    ),
                    title: Text(
                      fileName,
                      style: TextStyle(
                        color: isSelected ? Colors.blue[300] : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: isDirectory
                        ? null
                        : Text(
                            _formatFileSize(file.statSync().size),
                            style: TextStyle(color: Colors.grey),
                          ),
                    trailing: PopupMenuButton(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      itemBuilder: (context) => [
                        if (!isDirectory) ...[
                          PopupMenuItem(
                            onTap: () {
                              _selectFile(file);
                              _toggleEdit();
                            },
                            child: const Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            onTap: () => _copyFile(file),
                            child: const Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Copy'),
                              ],
                            ),
                          ),
                           PopupMenuItem(
                             onTap: () {
                               Clipboard.setData(ClipboardData(text: file.path));
                               ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Path copied to clipboard'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            child: const Row(
                              children: [
                                Icon(Icons.link, size: 16),
                                SizedBox(width: 8),
                                Text('Copy Path'),
                              ],
                            ),
                          ),
                        ],
                        PopupMenuItem(
                          onTap: () => _renameFile(file),
                          child: const Row(
                            children: [
                              Icon(Icons.drive_file_rename_outline, size: 16),
                              SizedBox(width: 8),
                              Text('Rename'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          onTap: () => _deleteFile(file),
                          child: const Row(
                            children: [
                              Icon(Icons.delete, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                        if (isDirectory) ...[
                          PopupMenuItem(
                            onTap: () => _navigateToDirectory(file.path),
                            child: const Row(
                              children: [
                                Icon(Icons.folder_open, size: 16),
                                SizedBox(width: 8),
                                Text('Open'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    selected: isSelected,
                    selectedTileColor: Colors.blue[900]!.withOpacity(0.3),
                    onTap: () {
                      if (isDirectory) {
                        _navigateToDirectory(file.path);
                      } else {
                        _selectFile(file);
                        widget.onFileSelected?.call(file.path);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        
        // Action buttons
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            border: Border(top: BorderSide(color: Colors.grey[700]!)),
          ),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _createNewFile,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _createNewDirectory,
                icon: const Icon(Icons.create_new_folder, size: 16),
                label: const Text('Folder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildPreviewPanel() {
    if (_selectedFile == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border(left: BorderSide(color: Colors.grey[700]!)),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.file_open, color: Colors.grey, size: 48),
              SizedBox(height: 16),
              Text(
                'Select a file to preview',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    
    final file = _selectedFile!;
    final fileName = path.basename(file.path);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border(left: BorderSide(color: Colors.grey[700]!)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[800],
              border: Border(bottom: BorderSide(color: Colors.grey[700]!)),
            ),
            child: Row(
              children: [
                Icon(
                  file is Directory ? Icons.folder : _getFileIcon(fileName),
                  color: Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (file is File) ...[
                  IconButton(
                    onPressed: _toggleEdit,
                    icon: Icon(
                      _isEditing ? Icons.save : Icons.edit,
                      color: Colors.blue[400],
                    ),
                    tooltip: _isEditing ? 'Save' : 'Edit',
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = false;
                        _editController.text = _editingContent ?? '';
                      });
                    },
                    icon: const Icon(Icons.refresh, color: Colors.grey),
                    tooltip: 'Reset',
                  ),
                  IconButton(
                    onPressed: () => _copyFile(file),
                    icon: const Icon(Icons.copy, color: Colors.grey),
                    tooltip: 'Copy',
                  ),
                  IconButton(
                    onPressed: () => _deleteFile(file),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _buildFileContent(file),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFileContent(FileSystemEntity file) {
    if (file is Directory) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Directory Contents',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<FileSystemEntity>>(
              future: file.list().toList(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator(color: Colors.grey);
                }
                
                final files = snapshot.data!;
                if (files.isEmpty) {
                  return const Text(
                    'Empty directory',
                    style: TextStyle(color: Colors.grey),
                  );
                }
                
                return ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final subFile = files[index];
                    final subFileName = path.basename(subFile.path);
                    
                    return ListTile(
                      leading: Icon(
                        subFile is Directory ? Icons.folder : _getFileIcon(subFileName),
                        color: Colors.grey,
                        size: 20,
                      ),
                      title: Text(
                        subFileName,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      subtitle: subFile is File
                          ? Text(
                              _formatFileSize(subFile.statSync().size),
                              style: TextStyle(color: Colors.grey),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ],
        ),
      );
    }
    
    final fileName = path.basename(file.path);
    final extension = path.extension(fileName).toLowerCase();
    
    // Check for media files first
    if (['.mp4', '.webm', '.avi', '.mov', '.mkv', '.flv', '.wmv'].contains(extension)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: InlineVideoPlayer(
          videoPath: file.path,
          onClose: () => setState(() => _selectedFile = null),
        ),
      );
    }
    
    if (['.mp3', '.wav', '.ogg', '.flac', '.m4a', '.aac', '.opus'].contains(extension)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AudioVisualizer(
          audioPath: file.path,
          onClose: () => setState(() => _selectedFile = null),
        ),
      );
    }
    
    if (['.obj', '.glb', '.gltf', '.fbx', '.3ds'].contains(extension)) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Model3DViewer(
          modelPath: file.path,
          onClose: () => setState(() => _selectedFile = null),
        ),
      );
    }
    
    if (GraphicsProtocolHandler().isImageFormat(extension.substring(1))) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<ui.Image?>(
          future: GraphicsProtocolHandler().loadImageFromFile(file.path),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Colors.grey));
            }
            
            final image = snapshot.data;
            if (image != null) {
              return Center(
                child: InteractiveViewer(
                  child: RawImage(
                    image: image,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            }
            
            return const Center(
              child: Text(
                'Failed to load image',
                style: TextStyle(color: Colors.red),
              ),
            );
          },
        ),
      );
    }
    
    // Check for text files that can be edited
    final editableExtensions = {
      '.txt', '.md', '.json', '.yaml', '.yml', '.dart', '.py', '.js', '.ts',
      '.html', '.css', '.sh', '.bash', '.zsh', '.fish', '.xml', '.toml',
      '.ini', '.cfg', '.conf', '.gitignore', '.dockerfile', '.env', '.log',
      '.sql', '.php', '.rb', '.go', '.rs', '.cpp', '.c', '.h', '.hpp',
      '.java', '.kt', '.swift', '.scala', '.clj', '.hs', '.ml', '.pl',
      '.vb', '.cs', '.vb', '.pas', '.ada', '.fortran', '.cobol', '.lisp',
      '.scheme', '.r', '.m', '.matlab', '.tex', '.latex', '.bib', '.cls',
      '.sty', '.cfg', '.conf', '.ini', '.reg', '.bat', '.cmd', '.ps1',
      '.vbs', '.wsf', '.wsc', '.ahk', '.au3', '.sh', '.bash', '.zsh',
      '.fish', '.csh', '.tcsh', '.ksh', '.mksh', '.pdksh', '.dash'
    };
    
    if (editableExtensions.contains(extension)) {
      if (_isEditing) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: TextEditor(
            filePath: file.path,
            initialContent: _editingContent ?? '',
            onSave: (content) async {
              await (file as File).writeAsString(content);
              setState(() {
                _editingContent = content;
                _isEditing = false;
              });
              widget.onFileEdited?.call(file.path);
            },
            onClose: () => setState(() => _isEditing = false),
          ),
        );
      }
      
      // Preview mode for text files
      if (_editingContent == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.grey),
        );
      }
      
      return Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            _editingContent!,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ),
      );
    }
    
    // Fallback to file info display
    try {
      final stat = file.statSync();
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getFileIcon(fileName),
                  color: Colors.grey,
                  size: 48,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        extension.toUpperCase(),
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildInfoRow('Size', _formatFileSize(stat.size)),
            _buildInfoRow('Modified', stat.modified.toString().substring(0, 19)),
            _buildInfoRow('Type', extension.toUpperCase()),
            _buildInfoRow('Readable', stat.readable ? 'Yes' : 'No'),
            _buildInfoRow('Writable', stat.writable ? 'Yes' : 'No'),
            if (file is File) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: file.path);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Path copied to clipboard'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Path'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height:16),
            const Text(
              'Error loading file info',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
  
  IconData _getFileIcon(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    
    // Programming languages
    switch (extension) {
      case '.dart':
        return Icons.code;
      case '.py':
        return Icons.code;
      case '.js':
        return Icons.javascript;
      case '.ts':
        return Icons.code;
      case '.html':
        return Icons.web;
      case '.css':
        return Icons.style;
      case '.json':
        return Icons.data_object;
      case '.yaml':
      case '.yml':
        return Icons.description;
      case '.md':
        return Icons.description;
      case '.txt':
        return Icons.text_snippet;
      case '.xml':
        return Icons.code;
      case '.sql':
        return Icons.storage;
      case '.php':
        return Icons.code;
      case '.rb':
        return Icons.code;
      case '.go':
        return Icons.code;
      case '.rs':
        return Icons.code;
      case '.cpp':
      case '.c':
      case '.h':
      case '.hpp':
        return Icons.code;
      case '.java':
        return Icons.code;
      case '.kt':
        return Icons.code;
      case '.swift':
        return Icons.code;
      case '.scala':
        return Icons.code;
      case '.clj':
        return Icons.code;
      case '.hs':
        return Icons.code;
      case '.ml':
        return Icons.code;
      case '.pl':
        return Icons.code;
      case '.vb':
      case '.cs':
        return Icons.code;
      case '.pas':
        return Icons.code;
      case '.ada':
        return Icons.code;
      case '.fortran':
        return Icons.code;
      case '.cobol':
        return Icons.code;
      case '.lisp':
        return Icons.code;
      case '.scheme':
        return Icons.code;
      case '.r':
        return Icons.code;
      case '.m':
        return Icons.code;
      case '.matlab':
        return Icons.code;
      case '.tex':
      case '.latex':
        return Icons.description;
      case '.bib':
        return Icons.description;
      case '.cls':
        return Icons.description;
      case '.sty':
        return Icons.description;
      case '.cfg':
      case '.conf':
      case '.ini':
      case '.reg':
        return Icons.settings;
      case '.bat':
      case '.cmd':
      case '.ps1':
      case '.vbs':
      case '.wsf':
      case '.wsc':
      case '.ahk':
      case '.au3':
        return Icons.terminal;
      case '.sh':
      case '.bash':
      case '.zsh':
      case '.fish':
      case '.csh':
      case '.tcsh':
      case '.ksh':
      case '.mksh':
      case '.pdksh':
      case '.dash':
        return Icons.terminal;
    }
    
    // Image files
    switch (extension) {
      case '.png':
        return Icons.image;
      case '.jpg':
      case '.jpeg':
        return Icons.image;
      case '.gif':
        return Icons.gif;
      case '.webp':
        return Icons.image;
      case '.svg':
        return Icons.image;
      case '.bmp':
        return Icons.image;
      case '.ico':
        return Icons.image;
      case '.tiff':
        return Icons.image;
      case '.tga':
        return Icons.image;
      case '.webm':
        return Icons.video_file;
    }
    
    // Video files
    switch (extension) {
      case '.mp4':
        return Icons.video_file;
      case '.avi':
        return Icons.video_file;
      case '.mov':
        return Icons.video_file;
      case '.mkv':
        return Icons.video_file;
      case '.flv':
        return Icons.video_file;
      case '.wmv':
        return Icons.video_file;
      case '.webm':
        return Icons.video_file;
      case '.m4v':
        return Icons.video_file;
      case '.3gp':
        return Icons.video_file;
      case '.ogv':
        return Icons.video_file;
    }
    
    // Audio files
    switch (extension) {
      case '.mp3':
        return Icons.audiotrack;
      case '.wav':
        return Icons.audiotrack;
      case '.flac':
        return Icons.audiotrack;
      case '.m4a':
        return Icons.audiotrack;
      case '.aac':
        return Icons.audiotrack;
      case '.opus':
        return Icons.audiotrack;
      case '.ogg':
        return Icons.audiotrack;
      case '.wma':
        return Icons.audiotrack;
      case '.aiff':
        return Icons.audiotrack;
    }
    
    // Archive files
    switch (extension) {
      case '.zip':
        return Icons.archive;
      case '.tar':
        return Icons.archive;
      case '.gz':
        return Icons.archive;
      case '.bz2':
        return Icons.archive;
      case '.xz':
        return Icons.archive;
      case '.7z':
        return Icons.archive;
      case '.rar':
        return Icons.archive;
      case '.deb':
        return Icons.archive;
      case '.rpm':
        return Icons.archive;
      case '.dmg':
        return Icons.archive;
      case '.iso':
        return Icons.archive;
      case '.img':
        return Icons.archive;
    }
    
    // Document files
    switch (extension) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.ppt':
      case '.pptx':
        return Icons.slideshow;
      case '.odt':
      case '.ods':
      case '.odp':
        return Icons.description;
    }
    
    // System files
    switch (extension) {
      case '.exe':
        return Icons.desktop_windows;
      case '.msi':
        return Icons.desktop_windows;
      case '.app':
        return Icons.desktop_mac;
      case '.deb':
        return Icons.archive;
      case '.rpm':
        return Icons.archive;
      case '.pkg':
        return Icons.archive;
      case '.dmg':
        return Icons.archive;
    }
    
    // Default file icon
    return Icons.insert_drive_file;
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // File list (60% width)
          Expanded(
            flex: 6,
            child: _buildFileList(),
          ),
          
          // Preview panel (40% width)
          Expanded(
            flex: 4,
            child: _buildPreviewPanel(),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _editController.dispose();
    _renameController.dispose();
    super.dispose();
  }
}
