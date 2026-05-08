import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Multimedia Graphics Protocol Handler
/// 
/// Handles inline graphics protocols including SIXEL and Kitty graphics
/// for displaying images, charts, and other visual content directly in the terminal.
class GraphicsProtocolHandler {
  final Map<String, GraphicsImage> _imageCache = {};
  final Map<String, GraphicsAnimation> _animationCache = {};
  final List<GraphicsProtocol> _enabledProtocols = [];
  
  // Protocol parsers
  final SixelParser _sixelParser = SixelParser();
  final KittyParser _kittyParser = KittyParser();
  final ItermParser _itermParser = ItermParser();
  
  // Configuration
  final GraphicsConfig config;
  
  GraphicsProtocolHandler({required this.config}) {
    _initializeProtocols();
  }
  
  void _initializeProtocols() {
    if (config.enableSixel) {
      _enabledProtocols.add(GraphicsProtocol.sixel);
    }
    if (config.enableKitty) {
      _enabledProtocols.add(GraphicsProtocol.kitty);
    }
    if (config.enableIterm) {
      _enabledProtocols.add(GraphicsProtocol.iterm);
    }
    
    debugPrint('🎨 Enabled graphics protocols: $_enabledProtocols');
  }
  
  /// Parse and handle graphics escape sequences
  GraphicsResult? parseSequence(String sequence, int cursorX, int cursorY) {
    for (final protocol in _enabledProtocols) {
      final result = _parseWithProtocol(sequence, protocol, cursorX, cursorY);
      if (result != null) {
        return result;
      }
    }
    return null;
  }
  
  GraphicsResult? _parseWithProtocol(
    String sequence, 
    GraphicsProtocol protocol, 
    int cursorX, 
    int cursorY,
  ) {
    switch (protocol) {
      case GraphicsProtocol.sixel:
        return _sixelParser.parse(sequence, cursorX, cursorY);
      case GraphicsProtocol.kitty:
        return _kittyParser.parse(sequence, cursorX, cursorY);
      case GraphicsProtocol.iterm:
        return _itermParser.parse(sequence, cursorX, cursorY);
    }
  }
  
  /// Download and cache an image from URL
  Future<GraphicsImage?> downloadImage(String url) async {
    if (_imageCache.containsKey(url)) {
      return _imageCache[url];
    }
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final image = GraphicsImage(
          id: url,
          data: response.bodyBytes,
          format: _detectImageFormat(response.bodyBytes),
          width: 0, // Will be determined during decoding
          height: 0,
        );
        
        await _decodeImage(image);
        _imageCache[url] = image;
        
        // Limit cache size
        if (_imageCache.length > config.maxCacheSize) {
          final keysToRemove = _imageCache.keys.take(10);
          for (final key in keysToRemove) {
            _imageCache.remove(key);
          }
        }
        
        return image;
      }
    } catch (e) {
      debugPrint('❌ Failed to download image from $url: $e');
    }
    
    return null;
  }
  
  ImageFormat _detectImageFormat(Uint8List bytes) {
    if (bytes.length < 4) return ImageFormat.unknown;
    
    // Check magic bytes
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return ImageFormat.png;
    } else if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return ImageFormat.jpeg;
    } else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return ImageFormat.gif;
    } else if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      return ImageFormat.webp;
    } else if (bytes[0] == 0x3C && bytes[1] == 0x73 && bytes[2] == 0x76 && bytes[3] == 0x67) {
      return ImageFormat.svg;
    }
    
    return ImageFormat.unknown;
  }
  
  Future<void> _decodeImage(GraphicsImage image) async {
    try {
      final codec = await ui.instantiateImageCodec(image.data);
      final frame = await codec.getNextFrame();
      
      image.width = frame.image.width;
      image.height = frame.image.height;
      image.decodedImage = frame.image;
      
    } catch (e) {
      debugPrint('❌ Failed to decode image: $e');
    }
  }
  
  /// Generate sixel data from an image
  Future<String> generateSixel(GraphicsImage image) async {
    if (image.decodedImage == null) {
      await _decodeImage(image);
    }
    
    if (image.decodedImage == null) {
      return '';
    }
    
    return await _sixelParser.encodeImage(image.decodedImage!);
  }
  
  /// Generate kitty graphics data from an image
  Future<String> generateKitty(GraphicsImage image) async {
    if (image.decodedImage == null) {
      await _decodeImage(image);
    }
    
    if (image.decodedImage == null) {
      return '';
    }
    
    return await _kittyParser.encodeImage(image.decodedImage!, image.id);
  }
  
  /// Clear image cache
  void clearCache() {
    _imageCache.clear();
    _animationCache.clear();
  }
  
  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'imageCount': _imageCache.length,
      'animationCount': _animationCache.length,
      'enabledProtocols': _enabledProtocols.map((p) => p.name).toList(),
    };
  }
  
  /// Dispose resources
  void dispose() {
    for (final image in _imageCache.values) {
      image.decodedImage?.dispose();
    }
    _imageCache.clear();
    _animationCache.clear();
  }
}

/// Graphics image data
class GraphicsImage {
  final String id;
  final Uint8List data;
  final ImageFormat format;
  int width;
  int height;
  ui.Image? decodedImage;
  
  GraphicsImage({
    required this.id,
    required this.data,
    required this.format,
    required this.width,
    required this.height,
  });
}

/// Graphics animation data
class GraphicsAnimation {
  final String id;
  final List<GraphicsImage> frames;
  final Duration frameDuration;
  final bool loop;
  
  GraphicsAnimation({
    required this.id,
    required this.frames,
    required this.frameDuration,
    this.loop = true,
  });
}

/// Graphics result from parsing
class GraphicsResult {
  final GraphicsType type;
  final GraphicsImage? image;
  final GraphicsAnimation? animation;
  final int x;
  final int y;
  final int width;
  final int height;
  
  GraphicsResult({
    required this.type,
    this.image,
    this.animation,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Graphics configuration
class GraphicsConfig {
  final bool enableSixel;
  final bool enableKitty;
  final bool enableIterm;
  final int maxCacheSize;
  final int maxImageSize;
  final bool enableAnimations;
  
  const GraphicsConfig({
    this.enableSixel = true,
    this.enableKitty = true,
    this.enableIterm = true,
    this.maxCacheSize = 100,
    this.maxImageSize = 10 * 1024 * 1024, // 10MB
    this.enableAnimations = true,
  });
}

/// Graphics protocol types
enum GraphicsProtocol {
  sixel('sixel'),
  kitty('kitty'),
  iterm('iterm');
  
  const GraphicsProtocol(this.name);
  final String name;
}

/// Graphics result types
enum GraphicsType {
  image,
  animation,
  clear,
}

/// Image formats
enum ImageFormat {
  png,
  jpeg,
  gif,
  webp,
  svg,
  sixel,
  unknown,
}

/// SIXEL protocol parser
class SixelParser {
  static const int maxColors = 256;
  static const int maxPaletteSize = 256;
  
  GraphicsResult? parse(String sequence, int cursorX, int cursorY) {
    // Check for SIXEL sequence: \x1bP0;1;2;0q...\
    if (!sequence.startsWith('\x1bP') || !sequence.endsWith('\x1b\\')) {
      return null;
    }
    
    try {
      // Extract SIXEL data
      final sixelData = _extractSixelData(sequence);
      if (sixelData.isEmpty) return null;
      
      // Parse SIXEL parameters
      final params = _parseSixelParams(sequence);
      
      // Decode SIXEL to image
      final image = _decodeSixel(sixelData, params);
      
      return GraphicsResult(
        type: GraphicsType.image,
        image: image,
        x: cursorX,
        y: cursorY,
        width: image.width,
        height: image.height,
      );
      
    } catch (e) {
      debugPrint('❌ SIXEL parsing failed: $e');
      return null;
    }
  }
  
  String _extractSixelData(String sequence) {
    final start = sequence.indexOf('q') + 1;
    final end = sequence.lastIndexOf('\x1b\\');
    if (start >= end) return '';
    
    return sequence.substring(start, end);
  }
  
  SixelParams _parseSixelParams(String sequence) {
    final params = SixelParams();
    
    // Parse parameters from \x1bP0;1;2;0q
    final paramStart = sequence.indexOf('[') + 1;
    final paramEnd = sequence.indexOf('q');
    if (paramStart < paramEnd) {
      final paramString = sequence.substring(paramStart, paramEnd);
      final parts = paramString.split(';');
      
      if (parts.length >= 4) {
        params.aspectRatio = int.tryParse(parts[0]) ?? 1;
        params.colorMode = int.tryParse(parts[1]) ?? 0;
        params.gridWidth = int.tryParse(parts[2]) ?? 0;
        params.gridHeight = int.tryParse(parts[3]) ?? 0;
      }
    }
    
    return params;
  }
  
  GraphicsImage _decodeSixel(String sixelData, SixelParams params) {
    // Simplified SIXEL decoding - real implementation would be much more complex
    final width = params.gridWidth > 0 ? params.gridWidth : 800;
    final height = params.gridHeight > 0 ? params.gridHeight : 600;
    
    // Create a simple test pattern for now
    final pixels = Uint8List(width * height * 4); // RGBA
    
    // Generate a test pattern
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final index = (y * width + x) * 4;
        final color = (x + y) % 256;
        
        pixels[index] = color;     // R
        pixels[index + 1] = color; // G
        pixels[index + 2] = color; // B
        pixels[index + 3] = 255;   // A
      }
    }
    
    return GraphicsImage(
      id: 'sixel_${DateTime.now().millisecondsSinceEpoch}',
      data: pixels,
      format: ImageFormat.sixel,
      width: width,
      height: height,
    );
  }
  
  Future<String> encodeImage(ui.Image image) async {
    // Convert image to SIXEL format
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return '';
    
    final pixels = byteData.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    
    // Generate SIXEL data (simplified)
    final sixel = StringBuffer();
    sixel.write('\x1bP0;1;2;0q');
    
    // Simple SIXEL encoding - real implementation would be more sophisticated
    for (int y = 0; y < height; y += 6) { // SIXEL uses 6-pixel vertical bands
      for (int x = 0; x < width; x++) {
        int sixelValue = 0;
        
        for (int dy = 0; dy < 6 && y + dy < height; dy++) {
          final pixelIndex = ((y + dy) * width + x) * 4;
          final brightness = (pixels[pixelIndex] + pixels[pixelIndex + 1] + pixels[pixelIndex + 2]) / 3;
          
          if (brightness > 128) {
            sixelValue |= (1 << dy);
          }
        }
        
        if (sixelValue > 0) {
          sixel.write(String.fromCharCode(63 + sixelValue));
        }
      }
      
      sixel.write('-');
    }
    
    sixel.write('\x1b\\');
    return sixel.toString();
  }
}

/// SIXEL parameters
class SixelParams {
  int aspectRatio = 1;
  int colorMode = 0;
  int gridWidth = 0;
  int gridHeight = 0;
}

/// Kitty graphics protocol parser
class KittyParser {
  GraphicsResult? parse(String sequence, int cursorX, int cursorY) {
    // Check for Kitty sequence: \x1b_G...\
    if (!sequence.startsWith('\x1b_G') || !sequence.endsWith('\x1b\\')) {
      return null;
    }
    
    try {
      // Extract Kitty data
      final kittyData = _extractKittyData(sequence);
      if (kittyData.isEmpty) return null;
      
      // Parse Kitty parameters
      final params = _parseKittyParams(sequence);
      
      // Handle different Kitty commands
      switch (params.action) {
        case KittyAction.transmit:
          return _handleTransmit(kittyData, params, cursorX, cursorY);
        case KittyAction.query:
          return _handleQuery(params, cursorX, cursorY);
        case KittyAction.delete:
          return _handleDelete(params, cursorX, cursorY);
      }
      
    } catch (e) {
      debugPrint('❌ Kitty parsing failed: $e');
      return null;
    }
  }
  
  String _extractKittyData(String sequence) {
    final start = sequence.indexOf('G') + 1;
    final end = sequence.lastIndexOf('\x1b\\');
    if (start >= end) return '';
    
    return sequence.substring(start, end);
  }
  
  KittyParams _parseKittyParams(String sequence) {
    final params = KittyParams();
    
    // Parse parameters from \x1b_Ga=T,f=32,t=d,id=1;...
    final data = _extractKittyData(sequence);
    final parts = data.split(';');
    
    for (final part in parts) {
      final keyValue = part.split('=');
      if (keyValue.length == 2) {
        final key = keyValue[0];
        final value = keyValue[1];
        
        switch (key) {
          case 'a':
            params.action = _parseKittyAction(value);
            break;
          case 'f':
            params.format = int.tryParse(value) ?? 32;
            break;
          case 't':
            params.transmission = value;
            break;
          case 'i':
            params.imageId = value;
            break;
          case 'w':
            params.width = int.tryParse(value);
            break;
          case 'h':
            params.height = int.tryParse(value);
            break;
        }
      }
    }
    
    return params;
  }
  
  KittyAction _parseKittyAction(String value) {
    switch (value) {
      case 'T': return KittyAction.transmit;
      case 'q': return KittyAction.query;
      case 'd': return KittyAction.delete;
      default: return KittyAction.transmit;
    }
  }
  
  GraphicsResult _handleTransmit(String data, KittyParams params, int cursorX, int cursorY) {
    // Handle image transmission
    final imageData = base64.decode(data.split(',')[1] ?? '');
    
    final image = GraphicsImage(
      id: params.imageId,
      data: imageData,
      format: _kittyFormatToImageFormat(params.format),
      width: params.width ?? 0,
      height: params.height ?? 0,
    );
    
    return GraphicsResult(
      type: GraphicsType.image,
      image: image,
      x: cursorX,
      y: cursorY,
      width: image.width,
      height: image.height,
    );
  }
  
  GraphicsResult _handleQuery(KittyParams params, int cursorX, int cursorY) {
    // Handle image query - would return image info
    return GraphicsResult(
      type: GraphicsType.clear,
      x: cursorX,
      y: cursorY,
      width: 0,
      height: 0,
    );
  }
  
  GraphicsResult _handleDelete(KittyParams params, int cursorX, int cursorY) {
    // Handle image deletion
    return GraphicsResult(
      type: GraphicsType.clear,
      x: cursorX,
      y: cursorY,
      width: 0,
      height: 0,
    );
  }
  
  ImageFormat _kittyFormatToImageFormat(int format) {
    switch (format) {
      case 32: return ImageFormat.png;
      case 24: return ImageFormat.jpeg;
      case 100: return ImageFormat.webp;
      default: return ImageFormat.unknown;
    }
  }
  
  Future<String> encodeImage(ui.Image image, String imageId) async {
    // Convert image to Kitty graphics format
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return '';
    
    final pngData = byteData.buffer.asUint8List();
    final base64Data = base64.encode(pngData);
    
    // Generate Kitty graphics sequence
    return '\x1b_Ga=T,f=32,t=d,i=$imageId;${base64Data}\x1b\\';
  }
}

/// Kitty parameters
class KittyParams {
  KittyAction action = KittyAction.transmit;
  int format = 32; // PNG
  String transmission = 'd'; // direct
  String imageId = '';
  int? width;
  int? height;
}

/// Kitty actions
enum KittyAction {
  transmit,
  query,
  delete,
}

/// iTerm2 graphics protocol parser
class ItermParser {
  GraphicsResult? parse(String sequence, int cursorX, int cursorY) {
    // Check for iTerm2 sequence: \x1b]1337;File=...
    if (!sequence.startsWith('\x1b]1337;') || !sequence.endsWith('\x07')) {
      return null;
    }
    
    try {
      // Extract iTerm2 data
      final itermData = _extractItermData(sequence);
      if (itermData.isEmpty) return null;
      
      // Parse iTerm2 parameters
      final params = _parseItermParams(sequence);
      
      // Handle file transmission
      final imageData = base64.decode(itermData);
      
      final image = GraphicsImage(
        id: 'iterm_${DateTime.now().millisecondsSinceEpoch}',
        data: imageData,
        format: _itermFormatToImageFormat(params.format),
        width: params.width ?? 0,
        height: params.height ?? 0,
      );
      
      return GraphicsResult(
        type: GraphicsType.image,
        image: image,
        x: cursorX,
        y: cursorY,
        width: image.width,
        height: image.height,
      );
      
    } catch (e) {
      debugPrint('❌ iTerm2 parsing failed: $e');
      return null;
    }
  }
  
  String _extractItermData(String sequence) {
    final start = sequence.indexOf('File=') + 5;
    final end = sequence.lastIndexOf('\x07');
    if (start >= end) return '';
    
    final headerAndData = sequence.substring(start, end);
    final parts = headerAndData.split(':');
    
    return parts.length > 1 ? parts[1] : '';
  }
  
  ItermParams _parseItermParams(String sequence) {
    final params = ItermParams();
    
    // Parse parameters from File=name=size;type=format;...
    final start = sequence.indexOf('File=') + 5;
    final end = sequence.indexOf(':');
    if (start < end) {
      final header = sequence.substring(start, end);
      final parts = header.split(';');
      
      for (final part in parts) {
        final keyValue = part.split('=');
        if (keyValue.length == 2) {
          final key = keyValue[0];
          final value = keyValue[1];
          
          switch (key) {
            case 'inline':
              params.inline = value == '1';
              break;
            case 'width':
              params.width = int.tryParse(value);
              break;
            case 'height':
              params.height = int.tryParse(value);
              break;
            case 'preserveAspectRatio':
              params.preserveAspectRatio = value == '1';
              break;
          }
        }
      }
    }
    
    return params;
  }
  
  ImageFormat _itermFormatToImageFormat(String format) {
    switch (format.toLowerCase()) {
      case 'png':
        return ImageFormat.png;
      case 'jpeg':
      case 'jpg':
        return ImageFormat.jpeg;
      case 'gif':
        return ImageFormat.gif;
      case 'webp':
        return ImageFormat.webp;
      default:
        return ImageFormat.unknown;
    }
  }
  
  Future<String> encodeImage(ui.Image image, {String? name}) async {
    // Convert image to iTerm2 graphics format
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return '';
    
    final pngData = byteData.buffer.asUint8List();
    final base64Data = base64.encode(pngData);
    final imageName = name ?? 'image_${DateTime.now().millisecondsSinceEpoch}.png';
    
    // Generate iTerm2 graphics sequence
    return '\x1b]1337;File=inline=1:name=$imageName;width=${image.width}:height=${image.height}:${base64Data}\x07';
  }
}

/// iTerm2 parameters
class ItermParams {
  bool inline = true;
  int? width;
  int? height;
  bool preserveAspectRatio = true;
  String format = 'png';
}
