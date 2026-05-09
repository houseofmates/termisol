import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'package:http/http.dart' as http;

/// enhanced clipboard manager supporting text, images, gifs, and videos
class EnhancedClipboardManager {
  final Terminal terminal;
  final TerminalController controller;
  final String tempDir;
  
  // Configuration
  final int maxTextLength;
  final int maxFileSizeMB;
  final Duration pasteDelay;
  
  EnhancedClipboardManager({
    required this.terminal,
    required this.controller,
    this.tempDir = '/tmp/termisol_clipboard',
    this.maxTextLength = 1000000, // 1MB text
    this.maxFileSizeMB = 50, // 50MB files
    this.pasteDelay = const Duration(milliseconds: 100),
  }) {
    _ensureTempDir();
  }

  /// Ensure temporary directory exists
  void _ensureTempDir() {
    final dir = Directory(tempDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// Get clipboard content type and data
  Future<ClipboardContent> getClipboardContent() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      
      // Check for text content
      if (data?.text != null && data!.text!.isNotEmpty) {
        return ClipboardContent(
          type: ClipboardContentType.text,
          text: data.text!,
          size: data.text!.length,
        );
      }

      // On desktop platforms, check for file content
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final fileContent = await _getClipboardFiles();
        if (fileContent != null) {
          return fileContent;
        }
      }

      // Check for image content (platform-specific)
      final imageContent = await _getClipboardImage();
      if (imageContent != null) {
        return imageContent;
      }

      return ClipboardContent(type: ClipboardContentType.empty);
    } catch (e) {
      debugPrint('Error getting clipboard content: $e');
      return ClipboardContent(type: ClipboardContentType.empty);
    }
  }

  /// Get files from clipboard (Windows/Linux/MacOS)
  Future<ClipboardContent?> _getClipboardFiles() async {
    try {
      // Windows: Use clipboard file API
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-Command', 
          'Get-Clipboard -Format FileDropList'
        ]);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final paths = output.split('\n').where((p) => p.isNotEmpty).toList();
          if (paths.isNotEmpty) {
            final firstPath = paths.first.trim();
            if (File(firstPath).existsSync()) {
              return ClipboardContent(
                type: ClipboardContentType.file,
                filePath: firstPath,
                size: await _getFileSize(firstPath),
              );
            }
          }
        }
      }
      
      // Linux: Use xclip to get file list
      if (Platform.isLinux) {
        // Check if xclip is available
        try {
          final whichResult = await Process.run('which', ['xclip']);
          if (whichResult.exitCode != 0) {
            debugPrint('xclip not available for file clipboard access');
            return null;
          }
          
          final result = await Process.run('xclip', ['-selection', 'clipboard', '-t', 'text/uri-list', '-o']);
          if (result.exitCode == 0) {
            final output = result.stdout as String;
            final uris = output.split('\n').where((uri) => uri.isNotEmpty).toList();
            if (uris.isNotEmpty) {
              final firstUri = uris.first.trim();
              final filePath = firstUri.replaceFirst(RegExp(r'^file://'), '');
              if (File(filePath).existsSync()) {
                return ClipboardContent(
                  type: ClipboardContentType.file,
                  filePath: filePath,
                  size: await _getFileSize(filePath),
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Linux file clipboard access failed: $e');
          return null;
        }
      }
      
      // macOS: Use applescript to get file paths
      if (Platform.isMacOS) {
        final script = '''
          tell application "Finder"
            set theItems to (get the clipboard as «class furl»)
            if theItems is not {} then
              set firstItem to first item of theItems
              return POSIX path of firstItem
            end if
          end tell
        ''';
        
        try {
          final result = await Process.run('osascript', ['-e', script]);
          if (result.exitCode == 0) {
            final output = result.stdout as String;
            final filePath = output.trim();
            if (filePath.isNotEmpty && File(filePath).existsSync()) {
              return ClipboardContent(
                type: ClipboardContentType.file,
                filePath: filePath,
                size: await _getFileSize(filePath),
              );
            }
          }
        } catch (e) {
          debugPrint('macOS file clipboard access failed: $e');
          return null;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting clipboard files: $e');
      return null;
    }
  }

  /// Get image from clipboard
  Future<ClipboardContent?> _getClipboardImage() async {
    try {
      // Platform-specific image detection
      if (Platform.isMacOS) {
        final script = '''
          tell application "System Events"
            try
              set theClipboard to the clipboard as data class «class PNGf»
              return theClipboard
            on error
              return ""
            end try
          end tell
        ''';
        
        try {
          final result = await Process.run('osascript', ['-e', script]);
          if (result.exitCode == 0) {
            final output = result.stdout as String;
            if (output.isNotEmpty) {
              // Parse the binary data from osascript output
              final imageData = await _parseOsascriptImageData(output);
              if (imageData != null) {
                return ClipboardContent(
                  type: ClipboardContentType.image,
                  imageData: imageData!,
                  size: imageData.length,
                  format: 'png',
                );
              }
            }
          }
        } catch (e) {
          debugPrint('macOS image clipboard access failed: $e');
          return null;
        }
      }
      
      // For other platforms, we'd need additional implementations
      return null;
    } catch (e) {
      debugPrint('Error getting clipboard image: $e');
      return null;
    }
  }

  /// Enhanced paste with support for all content types
  Future<PasteResult> paste() async {
    try {
      final content = await getClipboardContent();
      
      switch (content.type) {
        case ClipboardContentType.text:
          return await _pasteText(content.text!);
          
        case ClipboardContentType.file:
          return await _pasteFile(content.filePath!);
          
        case ClipboardContentType.image:
          return await _pasteImage(content.imageData!, content.format!);
          
        case ClipboardContentType.empty:
          return PasteResult(
            success: false,
            message: 'No content in clipboard',
          );
      }
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Paste failed: $e',
      );
    }
  }

  /// Paste text content with large block support
  Future<PasteResult> _pasteText(String text) async {
    if (text.length > maxTextLength) {
      return await _pasteLargeText(text);
    }
    
    try {
      // Use bracketed paste mode for better compatibility
      terminal.paste(text);
      await Future.delayed(pasteDelay);
      
      return PasteResult(
        success: true,
        message: 'Pasted ${text.length} characters',
        type: PasteType.text,
        metadata: {'length': text.length},
      );
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Text paste failed: $e',
      );
    }
  }

  /// Paste large text blocks with progress indication
  Future<PasteResult> _pasteLargeText(String text) async {
    try {
      final chunks = _splitTextIntoChunks(text, 8192); // 8KB chunks
      int totalPasted = 0;
      
      // Show progress in terminal
      terminal.write('\n\r📋 Pasting large text block (${text.length} chars)...\n\r');
      
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        terminal.paste(chunk);
        totalPasted += chunk.length;
        
        // Update progress
        final progress = ((i + 1) / chunks.length * 100).round();
        terminal.write('\r\033[KProgress: $progress% (${totalPasted}/${text.length} chars)');
        
        // Small delay to prevent overwhelming the terminal
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      // Clear progress line and show completion
      terminal.write('\r\033[K✅ Pasted $totalPasted characters successfully\n\r');
      
      return PasteResult(
        success: true,
        message: 'Pasted large text block: $totalPasted characters',
        type: PasteType.largeText,
        metadata: {
          'length': totalPasted,
          'chunks': chunks.length,
        },
      );
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Large text paste failed: $e',
      );
    }
  }

  /// Split text into manageable chunks
  List<String> _splitTextIntoChunks(String text, int chunkSize) {
    final chunks = <String>[];
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, text.length);
      chunks.add(text.substring(i, end));
    }
    return chunks;
  }

  /// Paste file from clipboard
  Future<PasteResult> _pasteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return PasteResult(
          success: false,
          message: 'File not found: $filePath',
        );
      }

      final fileSize = await file.length();
      final fileName = path.basename(filePath);
      final fileSizeMB = fileSize / (1024 * 1024);

      if (fileSizeMB > maxFileSizeMB) {
        return PasteResult(
          success: false,
          message: 'File too large: ${fileSizeMB.toStringAsFixed(1)}MB (max: ${maxFileSizeMB}MB)',
        );
      }

      // Determine file type and handle accordingly
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
      
      if (mimeType.startsWith('image/')) {
        return await _pasteImageFile(file, fileName, mimeType);
      } else if (mimeType.startsWith('video/')) {
        return await _pasteVideoFile(file, fileName, mimeType);
      } else if (mimeType.contains('gif')) {
        return await _pasteGifFile(file, fileName, mimeType);
      } else {
        return await _pasteGenericFile(file, fileName, mimeType);
      }
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'File paste failed: $e',
      );
    }
  }

  /// Paste image data directly
  Future<PasteResult> _pasteImage(Uint8List imageData, String format) async {
    try {
      final fileName = 'clipboard_image_${DateTime.now().millisecondsSinceEpoch}.$format';
      final tempFile = File(path.join(tempDir, fileName));
      await tempFile.writeAsBytes(imageData);
      
      return await _pasteImageFile(tempFile, fileName, 'image/$format');
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Image paste failed: $e',
      );
    }
  }

  /// Paste image file
  Future<PasteResult> _pasteImageFile(File imageFile, String fileName, String mimeType) async {
    try {
      final fileSize = await imageFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      
      // Show image info in terminal
      terminal.write('\n\r🖼️  Detected image: $fileName (${fileSizeMB.toStringAsFixed(1)}MB)\n\r');
      
      // Create a temporary file in the current working directory
      final currentDir = Directory.current.path;
      final targetPath = path.join(currentDir, fileName);
      
      // Copy image to current directory
      await imageFile.copy(targetPath);
      
      // Generate appropriate terminal command based on image type
      String command;
      if (mimeType.contains('png')) {
        command = '\x1b]1337;File=name=$fileName;inline=1:' + 
                  base64.encode(await imageFile.readAsBytes()) + '\x07';
      } else {
        // For other image formats, just show the path
        command = '📁 Image saved to: $targetPath';
      }
      
      terminal.write('$command\n\r');
      
      return PasteResult(
        success: true,
        message: 'Image pasted: $fileName',
        type: PasteType.image,
        metadata: {
          'fileName': fileName,
          'path': targetPath,
          'size': fileSize,
          'mimeType': mimeType,
        },
      );
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Image file paste failed: $e',
      );
    }
  }

  /// Paste GIF file with special handling
  Future<PasteResult> _pasteGifFile(File gifFile, String fileName, String mimeType) async {
    try {
      final fileSize = await gifFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      
      terminal.write('\n\r🎬 Detected GIF: $fileName (${fileSizeMB.toStringAsFixed(1)}MB)\n\r');
      
      // Save GIF to current directory
      final currentDir = Directory.current.path;
      final targetPath = path.join(currentDir, fileName);
      await gifFile.copy(targetPath);
      
      // Show GIF preview info
      terminal.write('📁 GIF saved to: $targetPath\n\r');
      terminal.write('💡 You can view with: open $targetPath\n\r');
      
      // Try to extract GIF info and display
      if (Platform.isMacOS || Platform.isLinux) {
        terminal.write('🔍 Analyzing GIF...\n\r');
        // Here you could add GIF analysis logic
      }
      
      return PasteResult(
        success: true,
        message: 'GIF pasted: $fileName',
        type: PasteType.gif,
        metadata: {
          'fileName': fileName,
          'path': targetPath,
          'size': fileSize,
          'mimeType': mimeType,
        },
      );
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'GIF paste failed: $e',
      );
    }
  }

  /// Paste video file
  Future<PasteResult> _pasteVideoFile(File videoFile, String fileName, String mimeType) async {
    try {
      final fileSize = await videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      
      terminal.write('\n\r🎥 Detected video: $fileName (${fileSizeMB.toStringAsFixed(1)}MB)\n\r');
      
      // Save video to current directory
      final currentDir = Directory.current.path;
      final targetPath = path.join(currentDir, fileName);
      await videoFile.copy(targetPath);
      
      terminal.write('📁 Video saved to: $targetPath\n\r');
      
      // Show video info and playback suggestions
      terminal.write('💡 Playback suggestions:\n\r');
      terminal.write('   • mpv $targetPath\n\r');
      terminal.write('   • vlc $targetPath\n\r');
      if (Platform.isMacOS) {
        terminal.write('   • open $targetPath\n\r');
      }
      
      return PasteResult(
        success: true,
        message: 'Video pasted: $fileName',
        type: PasteType.video,
        metadata: {
          'fileName': fileName,
          'path': targetPath,
          'size': fileSize,
          'mimeType': mimeType,
        },
      );
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Video paste failed: $e',
      );
    }
  }

  /// Paste generic file
  Future<PasteResult> _pasteGenericFile(File file, String fileName, String mimeType) async {
    try {
      final fileSize = await file.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      
      terminal.write('\n\r📄 Detected file: $fileName (${fileSizeMB.toStringAsFixed(1)}MB)\n\r');
      
      // Save file to current directory
      final currentDir = Directory.current.path;
      final targetPath = path.join(currentDir, fileName);
      await file.copy(targetPath);
      
      terminal.write('📁 File saved to: $targetPath\n\r');
      
      // Show file-specific suggestions
      if (mimeType.contains('pdf')) {
        terminal.write('💡 Open with: xdg-open $targetPath\n\r');
      } else if (mimeType.contains('text')) {
        terminal.write('💡 View with: cat $targetPath\n\r');
        terminal.write('💡 Edit with: nano $targetPath\n\r');
      }
      
      return PasteResult(
        success: true,
        message: 'File pasted: $fileName',
        type: PasteType.file,
        metadata: {
          'fileName': fileName,
          'path': targetPath,
          'size': fileSize,
          'mimeType': mimeType,
        },
      );
    } catch (e) {
      return PasteResult(
        success: false,
        message: 'Generic file paste failed: $e',
      );
    }
  }

  /// Get file size
  Future<int> _getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      return await file.length();
    } catch (e) {
      debugPrint('Error getting file size: $e');
      return 0;
    }
  }

  /// Parse image data from osascript output
  Future<Uint8List?> _parseOsascriptImageData(String output) async {
    try {
      // osascript returns binary data in a specific format
      // This is a simplified parser - real implementation would be more complex
      final lines = output.split('\n');
      final dataLines = lines.where((line) => line.trim().isNotEmpty).toList();
      
      if (dataLines.isEmpty) return null;
      
      // Convert to bytes (simplified approach)
      final List<int> bytes = [];
      for (final line in dataLines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          // Parse hex values or other format from osascript
          // This is a placeholder for the actual parsing logic
          final parts = trimmed.split(' ');
          for (final part in parts) {
            final value = int.tryParse(part);
            if (value != null && value >= 0 && value <= 255) {
              bytes.add(value);
            }
          }
        }
      }
      
      return bytes.isNotEmpty ? Uint8List.fromList(bytes) : null;
    } catch (e) {
      debugPrint('Error parsing osascript image data: $e');
      return null;
    }
  }

  /// Copy selection to clipboard (enhanced)
  Future<bool> copy() async {
    try {
      final selection = controller.selection;
      if (selection == null) return false;
      
      final text = terminal.buffer.getText(selection);
      if (text.isEmpty) return false;
      
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      debugPrint('Copy failed: $e');
      return false;
    }
  }

  /// Copy all content (enhanced)
  Future<bool> copyAll() async {
    try {
      final text = terminal.buffer.getText();
      if (text.isEmpty) return false;
      
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      debugPrint('Copy all failed: $e');
      return false;
    }
  }

  /// Check if clipboard has content
  Future<bool> hasContent() async {
    final content = await getClipboardContent();
    return content.type != ClipboardContentType.empty;
  }

  /// Get clipboard summary
  Future<String> getClipboardSummary() async {
    final content = await getClipboardContent();
    
    switch (content.type) {
      case ClipboardContentType.text:
        final length = content.text?.length ?? 0;
        return 'Text: $length characters';
        
      case ClipboardContentType.file:
        final fileName = path.basename(content.filePath ?? '');
        final size = content.size ?? 0;
        return 'File: $fileName (${(size / (1024 * 1024)).toStringAsFixed(1)}MB)';
        
      case ClipboardContentType.image:
        final size = content.size ?? 0;
        return 'Image: ${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
        
      case ClipboardContentType.empty:
        return 'Empty';
    }
  }

  /// Clean up temporary files
  Future<void> cleanup() async {
    try {
      final dir = Directory(tempDir);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Cleanup failed: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    // No specific resources to dispose
  }
}

/// clipboard content types
enum ClipboardContentType {
  empty,
  text,
  file,
  image,
}

/// clipboard content data class
class ClipboardContent {
  final ClipboardContentType type;
  final String? text;
  final String? filePath;
  final Uint8List? imageData;
  final String? format;
  final int? size;
  
  ClipboardContent({
    required this.type,
    this.text,
    this.filePath,
    this.imageData,
    this.format,
    this.size,
  });
}

/// paste result types
enum PasteType {
  text,
  largeText,
  file,
  image,
  gif,
  video,
}

/// paste result class
class PasteResult {
  final bool success;
  final String message;
  final PasteType? type;
  final Map<String, dynamic>? metadata;
  
  PasteResult({
    required this.success,
    required this.message,
    this.type,
    this.metadata,
  });
}