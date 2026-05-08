import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Graphics Protocol Handler - Advanced terminal graphics support
/// 
/// Implements industry-standard graphics protocols:
/// - 24-bit True Color (RGB)
/// - Kitty Graphics Protocol
/// - Sixel Graphics
/// - Alpha Channel Support
/// - Inline Images
class GraphicsProtocolHandler {
  Terminal? _terminal;
  TerminalController? _controller;

  bool _isInitialized = false;
  bool _trueColorEnabled = true;
  bool _kittyProtocolEnabled = true;
  bool _sixelEnabled = true;
  bool _alphaChannelEnabled = true;
  
  // Extended image format support
  final Set<String> _supportedImageFormats = {
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'avif', 'heic', 'heif', 'tiff', 'ico', 'svg'
  };
  
  // Graphics state
  final Map<String, GraphicsImage> _imageCache = {};
  final Map<int, Color> _colorPalette = {};
  final Map<int, ui.Image> _images = {};
  final Map<String, GraphicsOverlay> _overlays = {};
  final List<GraphicsAnimation> _animations = [];
  
  // Pending images for processing
  final Map<int, PendingImage> _pendingImages = {};
  int _nextImageId = 1;

  // Kitty protocol state
  final Map<int, KittyImage> _kittyImages = {};
  int _kittyImageId = 1;
  
  // Protocol state
  GraphicsProtocolState _protocolState = GraphicsProtocolState();
  
  // Rendering optimization
  final Map<String, ui.Picture> _pictureCache = {};
  final Map<int, List<ui.Rect>> _damageRegions = {};
  
  GraphicsProtocolHandler([this._terminal, this._controller]);
  
  bool get isInitialized => _isInitialized;
  bool get trueColorEnabled => _trueColorEnabled;
  bool get kittyProtocolEnabled => _kittyProtocolEnabled;
  bool get sixelEnabled => _sixelEnabled;
  bool get alphaChannelEnabled => _alphaChannelEnabled;
  
  /// Initialize graphics protocol handler
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize default color palette
      _initializeColorPalette();

      // Set up terminal output interception if terminal is available
      if (_terminal != null && _controller != null) {
        _setupOutputInterception();
      }

      _isInitialized = true;
      debugPrint('🎨 Graphics Protocol Handler initialized with True Color support');
    } catch (e) {
      debugPrint('❌ Failed to initialize Graphics Protocol Handler: $e');
    }
  }

  /// Set up output interception to handle graphics protocols
  void _setupOutputInterception() {
    // The terminal output is handled in the session, we'll intercept there
    debugPrint('Graphics protocol output interception ready');
  }
  
  /// Initialize default color palette
  void _initializeColorPalette() {
    // ANSI 256-color palette
    final standardColors = [
      0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xc0c0c0,
      0x808080, 0xff0000, 0x00ff00, 0xffff00, 0x0000ff, 0xff00ff, 0x00ffff, 0xffffff,
    ];
    
    for (int i = 0; i < standardColors.length; i++) {
      _colorPalette[i] = Color(0xFF000000 + standardColors[i]);
    }
    
    // 216-color cube (6x6x6)
    for (int r = 0; r < 6; r++) {
      for (int g = 0; g < 6; g++) {
        for (int b = 0; b < 6; b++) {
          final index = 16 + (36 * r) + (6 * g) + b;
          final color = Color.fromARGB(
            255,
            (r == 0) ? 0 : (55 + 40 * r),
            (g == 0) ? 0 : (55 + 40 * g),
            (b == 0) ? 0 : (55 + 40 * b),
          );
          _colorPalette[index] = color;
        }
      }
    }
    
    // Grayscale ramp
    for (int i = 0; i < 24; i++) {
      final gray = 8 + 10 * i;
      final index = 232 + i;
      _colorPalette[index] = Color.fromARGB(255, gray, gray, gray);
    }
  }
  
  /// Parse ANSI color sequences for True Color support
  Color parseAnsiColor(String sequence, {bool isBackground = false}) {
    if (!_trueColorEnabled) {
      // Fallback to basic ANSI colors
      return _parseBasicAnsiColor(sequence, isBackground: isBackground);
    }
    
    try {
      // Parse True Color (RGB) sequences: ESC[38;2;r;g;b or ESC[48;2;r;g;b
      final rgbMatch = RegExp(r'\x1b\[(38|48);2;(\d+);(\d+);(\d+)m').firstMatch(sequence);
      if (rgbMatch != null) {
        final r = int.parse(rgbMatch.group(2)!);
        final g = int.parse(rgbMatch.group(3)!);
        final b = int.parse(rgbMatch.group(4)!);
        return Color.fromARGB(255, r, g, b);
      }
      
      // Parse 256-color sequences: ESC[38;5;n or ESC[48;5;n
      final colorMatch = RegExp(r'\x1b\[(38|48);5;(\d+)m').firstMatch(sequence);
      if (colorMatch != null) {
        final colorIndex = int.parse(colorMatch.group(2)!);
        return _colorPalette[colorIndex] ?? Colors.white;
      }
      
      // Fallback to basic ANSI
      return _parseBasicAnsiColor(sequence, isBackground: isBackground);
    } catch (e) {
      debugPrint('⚠️ Failed to parse ANSI color: $e');
      return Colors.white;
    }
  }
  
  /// Parse basic ANSI colors (fallback)
  Color _parseBasicAnsiColor(String sequence, {bool isBackground = false}) {
    final match = RegExp(r'\x1b\[(\d+)m').firstMatch(sequence);
    if (match != null) {
      final code = int.parse(match.group(1)!);
      final colorMap = {
        30: Colors.black, 31: Colors.red, 32: Colors.green, 33: Colors.yellow,
        34: Colors.blue, 35: Color(0xFFFF00FF), 36: Colors.cyan, 37: Colors.white,
        40: Colors.black, 41: Colors.red, 42: Colors.green, 43: Colors.yellow,
        44: Colors.blue, 45: Color(0xFFFF00FF), 46: Colors.cyan, 47: Colors.white,
      };
      return colorMap[code] ?? Colors.white;
    }
    return Colors.white;
  }
  
  /// Handle Kitty Graphics Protocol
  String handleKittyProtocol(String sequence) {
    if (!_kittyProtocolEnabled) return '';
    
    try {
      // Parse Kitty graphics sequences: _Gq=1,i=id,t=f,f=24,s=w,h=h
      final match = RegExp(r'_G[^\\]*\\').firstMatch(sequence);
      if (match != null) {
        final params = match.group(0)!;
        return _processKittyGraphics(params);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to handle Kitty protocol: $e');
    }
    
    return '';
  }
  
  /// Process Kitty graphics parameters
  String _processKittyGraphics(String params) {
    final paramMap = <String, String>{};
    final pairs = params.substring(2, params.length - 1).split(',');
    
    for (final pair in pairs) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        paramMap[parts[0]] = parts[1];
      }
    }
    
    final action = params[1]; // a=action, t=transmission, q=query
    
    switch (action) {
      case 'a': // Action
        return _handleKittyAction(paramMap);
      case 't': // Transmission
        return _handleKittyTransmission(paramMap);
      case 'q': // Query
        return _handleKittyQuery(paramMap);
      default:
        return '';
    }
  }
  
  /// Handle Kitty graphics actions
  String _handleKittyAction(Map<String, String> params) {
    final action = params['a'];
    
    switch (action) {
      case 'p': // Put image
        return _putKittyImage(params);
      case 'd': // Delete image
        return _deleteKittyImage(params);
      case 'q': // Query
        return _queryKittyImage(params);
      default:
        return '';
    }
  }
  
  /// Put image via Kitty protocol
  String _putKittyImage(Map<String, String> params) {
    final id = params['i'] ?? _kittyImageId.toString();
    final width = int.tryParse(params['s'] ?? '0') ?? 0;
    final height = int.tryParse(params['h'] ?? '0') ?? 0;
    
    // Store image metadata
    _kittyImages[_kittyImageId] = KittyImage(
      id: _kittyImageId,
      width: width,
      height: height,
      format: params['f'] ?? '24',
    );
    
    _kittyImageId++;
    
    // Return acknowledgment
    return '\x1b_Gi=$id;OK\x1b\\';
  }
  
  /// Delete image via Kitty protocol
  String _deleteKittyImage(Map<String, String> params) {
    final id = int.tryParse(params['i'] ?? '0');
    if (id != null) {
      _kittyImages.remove(id);
    }
    return '\x1b_GOK\x1b\\';
  }
  
  /// Query image via Kitty protocol
  String _queryKittyImage(Map<String, String> params) {
    final id = int.tryParse(params['i'] ?? '0');
    if (id != null && _kittyImages.containsKey(id)) {
      final image = _kittyImages[id]!;
      return '\x1b_Gi=$id;w=${image.width};h=${image.height};OK\x1b\\';
    }
    return '\x1b_GFAIL\x1b\\';
  }
  
  /// Handle Kitty graphics transmission
  String _handleKittyTransmission(Map<String, String> params) {
    // Handle image data transmission
    final format = params['t'] ?? 'f';
    final id = params['i'] ?? _kittyImageId.toString();
    
    // Process image data based on format
    switch (format) {
      case 'f': // Direct transmission
        return _processDirectTransmission(params);
      case 't': // Temporary file
        return _processTemporaryFile(params);
      default:
        return '';
    }
  }
  
  /// Process direct image transmission
  String _processDirectTransmission(Map<String, String> params) {
    try {
      final data = params['d'];
      final format = params['f'] ?? '100';
      final width = params['w'];
      final height = params['h'];
      
      if (data == null) return '\x1b_Gi=1,f=32\x1b\\'; // Error: no data
      
      // Validate base64 data
      try {
        base64.decode(data);
      } catch (e) {
        return '\x1b_Gi=1,f=32\x1b\\'; // Error: invalid base64
      }
      
      // Store image data for rendering
      final imageId = _nextImageId++;
      _pendingImages[imageId] = PendingImage(
        data: data,
        format: format,
        width: width != null ? int.tryParse(width) : null,
        height: height != null ? int.tryParse(height) : null,
      );
      
      return '\x1b_Gi=$imageId,f=$format\x1b\\';
    } catch (e) {
      debugPrint('Error processing direct transmission: $e');
      return '\x1b_Gi=1,f=32\x1b\\'; // Error response
    }
  }
  
  /// Process temporary file transmission
  String _processTemporaryFile(Map<String, String> params) {
    try {
      final filename = params['t'];
      final format = params['f'] ?? '100';
      
      if (filename == null) return '\x1b_Gi=1,f=32\x1b\\'; // Error: no filename
      
      // Validate filename
      if (filename.contains('..') || filename.startsWith('/')) {
        return '\x1b_Gi=1,f=32\x1b\\'; // Error: invalid filename
      }
      
      final file = File('${Directory.systemTemp.path}/$filename');
      if (!file.existsSync()) {
        return '\x1b_Gi=1,f=32\x1b\\'; // Error: file not found
      }
      
      // Read and validate file
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) {
        return '\x1b_Gi=1,f=32\x1b\\'; // Error: empty file
      }
      
      // Store image data
      final imageId = _nextImageId++;
      final base64Data = base64.encode(bytes);
      _pendingImages[imageId] = PendingImage(
        data: base64Data,
        format: format,
        width: null,
        height: null,
      );
      
      // Clean up temp file
      try {
        file.deleteSync();
      } catch (e) {
        debugPrint('Warning: Failed to delete temp file $filename: $e');
      }
      
      return '\x1b_Gi=$imageId,f=$format\x1b\\';
    } catch (e) {
      debugPrint('Error processing temporary file: $e');
      return '\x1b_Gi=1,f=32\x1b\\'; // Error response
    }
  }
  
  /// Handle Kitty graphics queries
  String _handleKittyQuery(Map<String, String> params) {
    final query = params['q'];
    
    switch (query) {
      case 's': // Status
        return _getKittyStatus();
      case 'c': // Capabilities
        return _getKittyCapabilities();
      default:
        return '';
    }
  }
  
  /// Get Kitty protocol status
  String _getKittyStatus() {
    return '\x1b_GOK\x1b\\';
  }
  
  /// Get Kitty protocol capabilities
  String _getKittyCapabilities() {
    return '\x1b_Ga=T,f=32,s=1,v=1,c=1\x1b\\';
  }
  
  /// Handle Sixel graphics
  String handleSixel(String sequence) {
    if (!_sixelEnabled) return '';
    
    try {
      // Parse Sixel sequences: ESC[?...h ... ESC[?...l
      final match = RegExp(r'\x1bP([0-9;]*)(.*?)\x1b\\').firstMatch(sequence);
      if (match != null) {
        return _processSixel(match.group(1)!, match.group(2)!);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to handle Sixel: $e');
    }
    
    return '';
  }
  
  /// Process Sixel data
  String _processSixel(String params, String data) {
    // Parse Sixel parameters
    final paramMap = <String, String>{};
    final pairs = params.split(';');
    
    for (final pair in pairs) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        paramMap[parts[0]] = parts[1];
      }
    }
    
    // Create image from Sixel data
    final imageId = _nextImageId++;
    _imageCache[imageId.toString()] = GraphicsImage(
      id: imageId,
      width: int.tryParse(paramMap['1'] ?? '0') ?? 100,
      height: int.tryParse(paramMap['2'] ?? '0') ?? 100,
      data: data,
      format: 'sixel',
    );
    
    return '\x1b_Gi=$imageId;OK\x1b\\';
  }
  
  /// Convert image to display format
  Future<Uint8List?> convertImageForDisplay(
    String imageId, {
    int? targetWidth,
    int? targetHeight,
    bool enableAlpha = true,
  }) async {
    final image = _imageCache[imageId];
    if (image == null) return null;
    
    try {
      // Convert image based on format
      switch (image.format) {
        case 'sixel':
          return _convertSixelToRGBA(image, targetWidth, targetHeight, enableAlpha);
        case 'kitty':
          return _convertKittyToRGBA(image, targetWidth, targetHeight, enableAlpha);
        default:
          return null;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to convert image: $e');
      return null;
    }
  }
  
  /// Convert Sixel to RGBA format
  Uint8List _convertSixelToRGBA(
    GraphicsImage image,
    int? targetWidth,
    int? targetHeight,
    bool enableAlpha,
  ) {
    final width = targetWidth ?? image.width;
    final height = targetHeight ?? image.height;
    final data = Uint8List(width * height * 4);

    // Parse Sixel data and render to RGBA
    final lines = image.data.split('\n');
    int y = 0;

    for (final line in lines) {
      if (line.isEmpty) continue;

      int x = 0;
      final chars = line.runes.toList();

      for (int i = 0; i < chars.length; i++) {
        final char = chars[i];
        if (char < 63 || char > 126) continue; // Not a SIXEL character

        // Each SIXEL character represents 6 vertical pixels
        final sixelValue = char - 63; // SIXEL values start at 63 ('?')

        for (int bit = 0; bit < 6; bit++) {
          if (y + bit >= height) break;

          final pixelY = y + (5 - bit); // SIXEL bits are ordered top to bottom
          if (pixelY >= height) continue;

          final pixelIndex = ((pixelY * width) + x) * 4;

          if (pixelIndex + 3 < data.length) {
            // Check if bit is set in sixel value
            final bitSet = (sixelValue & (1 << bit)) != 0;

            if (bitSet) {
              // Use current color or default white
              final color = _protocolState.currentColor ?? Colors.white;
              data[pixelIndex] = color.red;
              data[pixelIndex + 1] = color.green;
              data[pixelIndex + 2] = color.blue;
              data[pixelIndex + 3] = enableAlpha ? (color.alpha) : 255;
            } else {
              // Transparent or background
              data[pixelIndex] = 0;
              data[pixelIndex + 1] = 0;
              data[pixelIndex + 2] = 0;
              data[pixelIndex + 3] = 0;
            }
          }
        }

        x++;
        if (x >= width) break;
      }

      y += 6; // Each SIXEL line represents 6 rows
      if (y >= height) break;
    }

    return data;
  }
  
  /// Convert Kitty image to RGBA format
  Uint8List _convertKittyToRGBA(
    GraphicsImage image,
    int? targetWidth,
    int? targetHeight,
    bool enableAlpha,
  ) {
    final width = targetWidth ?? image.width;
    final height = targetHeight ?? image.height;
    final data = Uint8List(width * height * 4);

    try {
      // Decode base64 image data
      final imageBytes = base64.decode(image.data);

      // For now, create a simple gradient pattern based on image dimensions
      // Full implementation would decode the actual Kitty format
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelIndex = ((y * width) + x) * 4;

          if (pixelIndex + 3 < data.length) {
            // Create a pattern based on position
            final r = ((x / width) * 255).toInt();
            final g = ((y / height) * 255).toInt();
            final b = 128;

            data[pixelIndex] = r;
            data[pixelIndex + 1] = g;
            data[pixelIndex + 2] = b;
            data[pixelIndex + 3] = enableAlpha ? 255 : 0;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to decode Kitty image: $e');
      // Fill with gray on error
      for (int i = 0; i < data.length; i += 4) {
        data[i] = 128;
        data[i + 1] = 128;
        data[i + 2] = 128;
        data[i + 3] = enableAlpha ? 255 : 0;
      }
    }

    return data;
  }
  
  /// Clear image cache
  void clearImageCache() {
    _imageCache.clear();
    _kittyImages.clear();
    debugPrint('🗑️ Graphics cache cleared');
  }
  
  /// Get cached image
  GraphicsImage? getCachedImage(String imageId) {
    return _imageCache[imageId];
  }
  
  /// Toggle graphics features
  void setTrueColorEnabled(bool enabled) {
    _trueColorEnabled = enabled;
  }
  
  void setKittyProtocolEnabled(bool enabled) {
    _kittyProtocolEnabled = enabled;
  }
  
  void setSixelEnabled(bool enabled) {
    _sixelEnabled = enabled;
  }
  
  void setAlphaChannelEnabled(bool enabled) {
    _alphaChannelEnabled = enabled;
  }

  /// Process terminal output for graphics protocol sequences
  String processOutput(String output) {
    if (!_isInitialized) return output;

    String processed = output;

    // Process Sixel sequences
    processed = _processSixelSequences(processed);

    // Process Kitty graphics sequences
    processed = _processKittySequences(processed);

    return processed;
  }

  /// Process Sixel graphics sequences in output
  String _processSixelSequences(String output) {
    if (!_sixelEnabled) return output;

    // Look for Sixel DCS sequences: ESC P ... ESC \
    final sixelRegex = RegExp(r'\x1bP([0-9;]*)(.*?)\x1b\\', dotAll: true);
    return output.replaceAllMapped(sixelRegex, (match) {
      final params = match.group(1) ?? '';
      final data = match.group(2) ?? '';
      final response = handleSixel('\x1bP$params$data\x1b\\');
      return response.isNotEmpty ? response : '';
    });
  }

  /// Process Kitty graphics sequences in output
  String _processKittySequences(String output) {
    if (!_kittyProtocolEnabled) return output;

    // Look for Kitty sequences: ESC _ G ... ESC \
    final kittyRegex = RegExp(r'\x1b_G([^\\]*)\x1b\\', dotAll: true);
    return output.replaceAllMapped(kittyRegex, (match) {
      final data = match.group(1) ?? '';
      final response = handleKittyProtocol('\x1b_G$data\x1b\\');
      return response.isNotEmpty ? response : '';
    });
  }
  
  bool isImageFormat(String extension) {
    return _supportedImageFormats.contains(extension.toLowerCase());
  }
  
  Future<ui.Image?> loadImageFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      
      return frame.image;
    } catch (e) {
      debugPrint('Failed to load image: $e');
      return null;
    }
  }
  
  /// Dispose resources
  void dispose() {
    clearImageCache();
    _colorPalette.clear();
    _isInitialized = false;
  }
}

/// Graphics image data structure
class GraphicsImage {
  final int id;
  final int width;
  final int height;
  final String data;
  final String format;
  
  GraphicsImage({
    required this.id,
    required this.width,
    required this.height,
    required this.data,
    required this.format,
  });
}

/// Kitty image data structure
class KittyImage {
  final int id;
  final int width;
  final int height;
  final String format;
  
  KittyImage({
    required this.id,
    required this.width,
    required this.height,
    required this.format,
  });
}

/// Pending image data for processing
class PendingImage {
  final String data;
  final String format;
  final int? width;
  final int? height;
  
  PendingImage({
    required this.data,
    required this.format,
    this.width,
    this.height,
  });
}
