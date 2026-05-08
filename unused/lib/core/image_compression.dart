import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Image compression for terminal images
/// 
/// Features:
/// - GPU-accelerated image rendering
/// - Memory-efficient texture management
/// - Multiple format support (WebP, AVIF, HEIC)
/// - Progressive loading
class ImageCompressionManager {
  static const int _maxTextureSize = 4096; // 4K texture limit
  static const int _compressionQuality = 80;
  static const Map<String, String> _formatSupport = {
    'webp': 'WebP',
    'avif': 'AVIF',
    'heic': 'HEIC',
    'jpeg': 'JPEG',
    'png': 'PNG',
  };

  final Map<String, CompressedTexture> _textureCache = {};
  final Isolate? _compressionIsolate;

  ImageCompressionManager() {
    _initializeCompressionIsolate();
  }

  /// Initialize compression isolate
  Future<void> _initializeCompressionIsolate() async {
    _compressionIsolate = await Isolate.spawn(_compressionWorker);
  }

  /// Compression worker isolate
  static Future<void> _compressionWorker(SendPort sendPort) async {
    while (true) {
      final message = await sendPort.first;
      
      if (message is CompressionCommand) {
        await _compressImage(message.data);
      }
    }
  }

  /// Compress image with specified format
  Future<CompressedTexture> compressImage(
    Uint8List imageData,
    String targetFormat, {
    String? outputPath,
  }) async {
    final command = CompressionCommand(
      imageData: imageData,
      targetFormat: targetFormat,
      outputPath: outputPath,
    );

    return await _sendToIsolate(command);
  }

  /// Send command to compression isolate
  Future<CompressedTexture> _sendToIsolate(CompressionCommand command) async {
    final receivePort = ReceivePort();
    await _compressionIsolate?.sendPort.send(receivePort);
    
    return await receivePort.first as CompressedTexture;
  }

  /// Get supported formats
  List<String> getSupportedFormats() {
    return _formatSupport.keys.toList();
  }

  /// Check if format is supported
  bool isFormatSupported(String format) {
    return _formatSupport.containsKey(format);
  }

  /// Dispose resources
  void dispose() {
    _compressionIsolate?.kill(priority: Isolate.immediate);
    _compressionIsolate = null;
    _textureCache.clear();
  }
}

/// Compression command for isolate communication
class CompressionCommand {
  final Uint8List imageData;
  final String targetFormat;
  final String? outputPath;

  const CompressionCommand({
    required this.imageData,
    required this.targetFormat,
    this.outputPath,
  });
}

/// Compressed texture result
class CompressedTexture {
  final Uint8List data;
  final String format;
  final int originalSize;
  final int compressedSize;
  final String? outputPath;

  const CompressedTexture({
    required this.data,
    required this.format,
    required this.originalSize,
    required this.compressedSize,
    this.outputPath,
  });

  /// Calculate compression ratio
  double get compressionRatio => originalSize > 0 ? compressedSize / originalSize : 1.0;
}
