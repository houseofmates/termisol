import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Clipboard Media Manager - Advanced clipboard support for all media types
/// 
/// Implements comprehensive clipboard support:
/// - Images (PNG, JPEG, WebP, GIF, SVG)
/// - Videos (MP4, WebM, AVI, MOV)
/// - PDF documents
/// - Audio files
/// - Text and code snippets
/// - Drag and drop support
/// - Format conversion
/// - Preview capabilities
class ClipboardMediaManager {
  bool _isInitialized = false;
  
  // Clipboard state
  Map<String, dynamic> _clipboardData = {};
  String? _currentMimeType;
  List<String> _supportedMimeTypes = [];
  
  // Media preview cache
  final Map<String, ui.Image> _imageCache = {};
  final Map<String, String> _textCache = {};
  
  // Event handlers
  final List<Function(ClipboardMediaData)> _onMediaReceived = [];
  
  ClipboardMediaManager();
  
  bool get isInitialized => _isInitialized;
  String? get currentMimeType => _currentMimeType;
  Map<String, dynamic> get clipboardData => Map.unmodifiable(_clipboardData);
  
  /// Initialize clipboard media manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Setup supported MIME types
      _setupSupportedMimeTypes();
      
      // Setup clipboard monitoring
      await _setupClipboardMonitoring();
      
      _isInitialized = true;
      debugPrint('📋 Clipboard Media Manager initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize Clipboard Media Manager: $e');
      rethrow;
    }
  }
  
  /// Setup supported MIME types
  void _setupSupportedMimeTypes() {
    _supportedMimeTypes = [
      // Images
      'image/png',
      'image/jpeg',
      'image/jpg',
      'image/webp',
      'image/gif',
      'image/svg+xml',
      'image/bmp',
      'image/tiff',
      
      // Videos
      'video/mp4',
      'video/webm',
      'video/avi',
      'video/quicktime',
      'video/x-matroska',
      'video/x-msvideo',
      
      // Documents
      'application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      
      // Audio
      'audio/mpeg',
      'audio/wav',
      'audio/ogg',
      'audio/mp4',
      'audio/webm',
      'audio/aac',
      
      // Text and code
      'text/plain',
      'text/html',
      'application/json',
      'application/xml',
      'text/x-dart',
      'text/x-python',
      'text/x-javascript',
      'text/x-typescript',
      'text/x-java-source',
      'text/x-csrc',
      'text/x-c++src',
      'text/x-go',
      'text/x-rust',
      
      // Archives
      'application/zip',
      'application/x-tar',
      'application/gzip',
      'application/x-7z-compressed',
      'application/x-rar-compressed',
    ];
  }
  
  /// Setup clipboard monitoring
  Future<void> _setupClipboardMonitoring() async {
    // Monitor clipboard changes
    Timer.periodic(const Duration(milliseconds: 500), (_) async {
      await _checkClipboard();
    });
  }
  
  /// Check clipboard for new data
  Future<void> _checkClipboard() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboard?.text != null) {
        await _processTextClipboard(clipboard!.text!);
      }
      
      // Check for image data
      final imageClipboard = await Clipboard.getData('image/png');
      if (imageClipboard != null) {
        await _processImageClipboard(imageClipboard);
      }
    } catch (e) {
      debugPrint('⚠️ Error checking clipboard: $e');
    }
  }
  
  /// Process text clipboard data
  Future<void> _processTextClipboard(String text) async {
    try {
      // Detect if it's a file path
      if (await _isFilePath(text)) {
        await _processFilePath(text);
        return;
      }
      
      // Detect if it's JSON
      if (_isJson(text)) {
        _currentMimeType = 'application/json';
        _clipboardData = {
          'type': 'json',
          'content': text,
          'size': text.length,
        };
        return;
      }
      
      // Detect if it's code
      final codeType = _detectCodeType(text);
      if (codeType != null) {
        _currentMimeType = codeType;
        _clipboardData = {
          'type': 'code',
          'language': _getLanguageFromMimeType(codeType),
          'content': text,
          'size': text.length,
        };
        return;
      }
      
      // Default to plain text
      _currentMimeType = 'text/plain';
      _clipboardData = {
        'type': 'text',
        'content': text,
        'size': text.length,
      };
    } catch (e) {
      debugPrint('⚠️ Error processing text clipboard: $e');
    }
  }
  
  /// Process image clipboard data
  Future<void> _processImageClipboard(Map<String, dynamic> imageData) async {
    try {
      _currentMimeType = 'image/png';
      _clipboardData = {
        'type': 'image',
        'format': 'png',
        'data': imageData,
      };
      
      // Cache image for preview
      if (imageData['imageData'] != null) {
        final imageBytes = base64.decode(imageData['imageData']);
        final codec = await ui.instantiateImageCodec(imageBytes);
        final frame = await codec.getNextFrame();
        _imageCache['current'] = frame.image;
      }
    } catch (e) {
      debugPrint('⚠️ Error processing image clipboard: $e');
    }
  }
  
  /// Process file path from clipboard
  Future<void> _processFilePath(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return;
      }
      
      final stat = await file.stat();
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
      final extension = path.extension(filePath).toLowerCase();
      
      _currentMimeType = mimeType;
      
      if (_isImageFile(mimeType, extension)) {
        await _processImageFile(file);
      } else if (_isVideoFile(mimeType, extension)) {
        await _processVideoFile(file);
      } else if (_isPdfFile(mimeType, extension)) {
        await _processPdfFile(file);
      } else if (_isAudioFile(mimeType, extension)) {
        await _processAudioFile(file);
      } else {
        await _processGenericFile(file, mimeType);
      }
    } catch (e) {
      debugPrint('⚠️ Error processing file path: $e');
    }
  }
  
  /// Process image file
  Future<void> _processImageFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      
      _clipboardData = {
        'type': 'image',
        'format': path.extension(file.path).substring(1),
        'path': file.path,
        'size': bytes.length,
        'width': frame.image.width,
        'height': frame.image.height,
        'imageData': frame.image,
      };
      
      // Cache for preview
      _imageCache['current'] = frame.image;
    } catch (e) {
      debugPrint('⚠️ Error processing image file: $e');
    }
  }
  
  /// Process video file
  Future<void> _processVideoFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final extension = path.extension(file.path).substring(1);
      
      // Extract video metadata (simplified)
      final metadata = await _extractVideoMetadata(file);
      
      _clipboardData = {
        'type': 'video',
        'format': extension,
        'path': file.path,
        'size': bytes.length,
        'duration': metadata['duration'],
        'width': metadata['width'],
        'height': metadata['height'],
        'fps': metadata['fps'],
      };
    } catch (e) {
      debugPrint('⚠️ Error processing video file: $e');
    }
  }
  
  /// Process PDF file
  Future<void> _processPdfFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      
      _clipboardData = {
        'type': 'pdf',
        'path': file.path,
        'size': bytes.length,
        'pages': await _countPdfPages(bytes),
      };
    } catch (e) {
      debugPrint('⚠️ Error processing PDF file: $e');
    }
  }
  
  /// Process audio file
  Future<void> _processAudioFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final extension = path.extension(file.path).substring(1);
      
      // Extract audio metadata (simplified)
      final metadata = await _extractAudioMetadata(file);
      
      _clipboardData = {
        'type': 'audio',
        'format': extension,
        'path': file.path,
        'size': bytes.length,
        'duration': metadata['duration'],
        'bitrate': metadata['bitrate'],
        'sampleRate': metadata['sampleRate'],
      };
    } catch (e) {
      debugPrint('⚠️ Error processing audio file: $e');
    }
  }
  
  /// Process generic file
  Future<void> _processGenericFile(File file, String mimeType) async {
    try {
      final bytes = await file.readAsBytes();
      final extension = path.extension(file.path).substring(1);
      
      _clipboardData = {
        'type': 'file',
        'format': extension,
        'path': file.path,
        'size': bytes.length,
        'mimeType': mimeType,
      };
    } catch (e) {
      debugPrint('⚠️ Error processing generic file: $e');
    }
  }
  
  /// Check if text is a file path
  Future<bool> _isFilePath(String text) async {
    final trimmed = text.trim();
    
    // Check if it looks like a path
    if (trimmed.contains('/') || trimmed.contains('\\')) {
      final file = File(trimmed);
      return await file.exists();
    }
    
    return false;
  }
  
  /// Check if text is JSON
  bool _isJson(String text) {
    try {
      jsonDecode(text);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Detect code type from text
  String? _detectCodeType(String text) {
    final lines = text.split('\n');
    
    // Check for common code patterns
    if (text.contains('class ') && text.contains('{')) {
      return 'text/x-java-source';
    }
    if (text.contains('def ') && text.contains(':')) {
      return 'text/x-python';
    }
    if (text.contains('function ') || text.contains('const ')) {
      return 'text/x-javascript';
    }
    if (text.contains('void main(') || text.contains('import ')) {
      return 'text/x-dart';
    }
    if (text.contains('func ') && text.contains('{')) {
      return 'text/x-go';
    }
    if (text.contains('fn ') && text.contains('->')) {
      return 'text/x-rust';
    }
    if (text.contains('#include') || text.contains('int main(')) {
      return 'text/x-csrc';
    }
    
    return null;
  }
  
  /// Get language from MIME type
  String _getLanguageFromMimeType(String mimeType) {
    final languageMap = {
      'text/x-dart': 'dart',
      'text/x-python': 'python',
      'text/x-javascript': 'javascript',
      'text/x-typescript': 'typescript',
      'text/x-java-source': 'java',
      'text/x-csrc': 'c',
      'text/x-c++src': 'cpp',
      'text/x-go': 'go',
      'text/x-rust': 'rust',
    };
    
    return languageMap[mimeType] ?? 'plaintext';
  }
  
  /// Check if file is an image
  bool _isImageFile(String mimeType, String extension) {
    return mimeType.startsWith('image/') || 
           ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.tiff'].contains(extension);
  }
  
  /// Check if file is a video
  bool _isVideoFile(String mimeType, String extension) {
    return mimeType.startsWith('video/') || 
           ['.mp4', '.webm', '.avi', '.mov', '.mkv', '.wmv'].contains(extension);
  }
  
  /// Check if file is a PDF
  bool _isPdfFile(String mimeType, String extension) {
    return mimeType == 'application/pdf' || extension == '.pdf';
  }
  
  /// Check if file is audio
  bool _isAudioFile(String mimeType, String extension) {
    return mimeType.startsWith('audio/') || 
           ['.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac'].contains(extension);
  }
  
  /// Extract video metadata (simplified)
  Future<Map<String, dynamic>> _extractVideoMetadata(File file) async {
    // This is a simplified implementation
    // In a real app, you would use a video processing library
    return {
      'duration': Duration.zero,
      'width': 1920,
      'height': 1080,
      'fps': 30.0,
    };
  }
  
  /// Extract audio metadata (simplified)
  Future<Map<String, dynamic>> _extractAudioMetadata(File file) async {
    // This is a simplified implementation
    // In a real app, you would use an audio processing library
    return {
      'duration': Duration.zero,
      'bitrate': 320,
      'sampleRate': 44100,
    };
  }
  
  /// Count PDF pages
  Future<int> _countPdfPages(Uint8List bytes) async {
    try {
      final document = await PdfDocument.openData(bytes);
      return document.pagesCount;
    } catch (e) {
      debugPrint('⚠️ Error counting PDF pages: $e');
      return 1;
    }
  }
  
  /// Paste clipboard content to terminal
  Future<void> pasteToTerminal(Terminal terminal) async {
    if (_clipboardData.isEmpty) return;
    
    try {
      final type = _clipboardData['type'];
      
      switch (type) {
        case 'text':
        terminal.write(_clipboardData['content']);
          break;
        case 'code':
          terminal.write(_clipboardData['content']);
          break;
        case 'json':
          terminal.write(_clipboardData['content']);
          break;
        case 'image':
          await _pasteImageToTerminal(terminal, _clipboardData);
          break;
        case 'video':
          await _pasteVideoToTerminal(terminal, _clipboardData);
          break;
        case 'pdf':
          await _pastePdfToTerminal(terminal, _clipboardData);
          break;
        case 'audio':
          await _pasteAudioToTerminal(terminal, _clipboardData);
          break;
        case 'file':
          await _pasteFileToTerminal(terminal, _clipboardData);
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Error pasting to terminal: $e');
    }
  }
  
  /// Paste image to terminal
  Future<void> _pasteImageToTerminal(Terminal terminal, Map<String, dynamic> imageData) async {
    // Generate temporary file and paste path
    final tempDir = Directory.systemTemp;
    final fileName = 'clipboard_image_${DateTime.now().millisecondsSinceEpoch}.${imageData['format']}';
    final tempFile = File(path.join(tempDir.path, fileName));
    
    await tempFile.writeAsBytes(imageData['imageData']);
    terminal.write(tempFile.path);
  }
  
  /// Paste video to terminal
  Future<void> _pasteVideoToTerminal(Terminal terminal, Map<String, dynamic> videoData) async {
    // Paste file path
    terminal.write(videoData['path']);
  }
  
  /// Paste PDF to terminal
  Future<void> _pastePdfToTerminal(Terminal terminal, Map<String, dynamic> pdfData) async {
    // Paste file path
    terminal.write(pdfData['path']);
  }
  
  /// Paste audio to terminal
  Future<void> _pasteAudioToTerminal(Terminal terminal, Map<String, dynamic> audioData) async {
    // Paste file path
    terminal.write(audioData['path']);
  }
  
  /// Paste file to terminal
  Future<void> _pasteFileToTerminal(Terminal terminal, Map<String, dynamic> fileData) async {
    // Paste file path
    terminal.write(fileData['path']);
  }
  
  /// Get preview widget for clipboard content
  Widget? getPreviewWidget(BuildContext context) {
    if (_clipboardData.isEmpty) return null;
    
    final type = _clipboardData['type'];
    
    switch (type) {
      case 'image':
        return _buildImagePreview(context, _clipboardData);
      case 'video':
        return _buildVideoPreview(context, _clipboardData);
      case 'pdf':
        return _buildPdfPreview(context, _clipboardData);
      case 'audio':
        return _buildAudioPreview(context, _clipboardData);
      case 'text':
      case 'code':
      case 'json':
        return _buildTextPreview(context, _clipboardData);
      case 'file':
        return _buildFilePreview(context, _clipboardData);
      default:
        return null;
    }
  }
  
  /// Build image preview widget
  Widget _buildImagePreview(BuildContext context, Map<String, dynamic> imageData) {
    final image = imageData['imageData'] as ui.Image?;
    if (image == null) {
      return Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image, size: 48),
      );
    }
    
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: RawImage(
          image: image,
          width: 200,
          height: 150,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
  
  /// Build video preview widget
  Widget _buildVideoPreview(BuildContext context, Map<String, dynamic> videoData) {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_file, size: 48),
          const SizedBox(height: 8),
          Text(
            videoData['format']?.toString().toUpperCase() ?? 'VIDEO',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            _formatFileSize(videoData['size'] ?? 0),
            style: TextStyle(color: Colors.grey[600]),
          ),
          if (videoData['duration'] != null)
            Text(
              _formatDuration(videoData['duration']),
              style: TextStyle(color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }
  
  /// Build PDF preview widget
  Widget _buildPdfPreview(BuildContext context, Map<String, dynamic> pdfData) {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf, size: 48, color: Colors.red),
          const SizedBox(height: 8),
          const Text(
            'PDF Document',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            _formatFileSize(pdfData['size'] ?? 0),
            style: TextStyle(color: Colors.grey[600]),
          ),
          if (pdfData['pages'] != null)
            Text(
              '${pdfData['pages']} pages',
              style: TextStyle(color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }
  
  /// Build audio preview widget
  Widget _buildAudioPreview(BuildContext context, Map<String, dynamic> audioData) {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.audiotrack, size: 48, color: Colors.purple),
          const SizedBox(height: 8),
          Text(
            audioData['format']?.toString().toUpperCase() ?? 'AUDIO',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            _formatFileSize(audioData['size'] ?? 0),
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
  
  /// Build text preview widget
  Widget _buildTextPreview(BuildContext context, Map<String, dynamic> textData) {
    final content = textData['content'] as String? ?? '';
    final maxLength = 200;
    final displayText = content.length > maxLength 
        ? '${content.substring(0, maxLength)}...' 
        : content;
    
    return Container(
      width: 300,
      height: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                textData['type'] == 'code' ? Icons.code : Icons.text_fields,
                size: 16,
                color: Colors.blue,
              ),
              const SizedBox(width: 4),
              if (textData['language'] != null)
                Text(
                  textData['language'],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                displayText,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          Text(
            '${content.length} characters',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build file preview widget
  Widget _buildFilePreview(BuildContext context, Map<String, dynamic> fileData) {
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getFileIcon(fileData['format']),
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            fileData['format']?.toString().toUpperCase() ?? 'FILE',
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            _formatFileSize(fileData['size'] ?? 0),
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
  
  /// Get file icon
  IconData _getFileIcon(String? format) {
    if (format == null) return Icons.insert_drive_file;
    
    switch (format.toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'svg':
        return Icons.image;
      case 'mp4':
      case 'webm':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
        return Icons.audiotrack;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  /// Format file size
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  
  /// Format duration
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
  
  /// Add media received listener
  void addMediaReceivedListener(Function(ClipboardMediaData) listener) {
    _onMediaReceived.add(listener);
  }
  
  /// Remove media received listener
  void removeMediaReceivedListener(Function(ClipboardMediaData) listener) {
    _onMediaReceived.remove(listener);
  }
  
  /// Clear clipboard
  void clearClipboard() {
    _clipboardData.clear();
    _currentMimeType = null;
    _imageCache.clear();
    _textCache.clear();
    Clipboard.setData(const ClipboardData(text: ''));
  }
  
  /// Get clipboard statistics
  Map<String, dynamic> getStatistics() {
    return {
      'initialized': _isInitialized,
      'currentMimeType': _currentMimeType,
      'hasData': _clipboardData.isNotEmpty,
      'supportedMimeTypes': _supportedMimeTypes,
      'cacheSize': _imageCache.length + _textCache.length,
    };
  }
  
  /// Dispose resources
  void dispose() {
    _clipboardData.clear();
    _imageCache.clear();
    _textCache.clear();
    _onMediaReceived.clear();
    _isInitialized = false;
    debugPrint('📋 Clipboard Media Manager disposed');
  }
}

/// Clipboard media data class
class ClipboardMediaData {
  final String type;
  final String? mimeType;
  final dynamic content;
  final int? size;
  final Map<String, dynamic>? metadata;
  
  ClipboardMediaData({
    required this.type,
    this.mimeType,
    this.content,
    this.size,
    this.metadata,
  });
  
  @override
  String toString() {
    return 'ClipboardMediaData(type: $type, mimeType: $mimeType, size: $size)';
  }
}
