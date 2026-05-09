import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xterm/xterm.dart';

/// Graphics Protocol Handler - Advanced terminal graphics support
///
/// Implements industry-standard graphics protocols:
/// - 24-bit True Color (RGB)
/// - Kitty Graphics Protocol
/// - Sixel Graphics
/// - Alpha Channel Support
/// - Inline Images with proper rendering
class GraphicsProtocolHandler {
  // Terminal reference for output interception
  final Terminal? _terminal;
  final TerminalController? _controller;

  bool _isInitialized = false;
  bool _trueColorEnabled = true;
  bool _kittyProtocolEnabled = true;
  bool _sixelEnabled = true;
  bool _alphaChannelEnabled = true;

  // Extended image format support
  final Set<String> _supportedImageFormats = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'bmp',
    'webp',
    'avif',
    'heic',
    'heif',
    'tiff',
    'ico',
    'svg',
  };

  // Graphics state
  final Map<String, GraphicsImage> _imageCache = {};
  final Map<String, Offset> _imagePositions =
      {}; // imageId -> character position (x,y)
  final Map<int, Color> _colorPalette = {};
  final Map<String, GraphicsOverlay> _overlays = {};
  final List<GraphicsAnimation> _animations = [];

  // Pending images for processing
  final Map<int, PendingImage> _pendingImages = {};
  int _nextImageId = 1;

  String? _cacheDir;
  final List<String> _tempFilePaths = [];

  // Protocol state
  final GraphicsProtocolState _protocolState = GraphicsProtocolState();

  // Rendering optimization
  final Map<String, ui.Picture> _pictureCache = {};
  final Map<int, List<ui.Rect>> _damageRegions = {};

  // Performance monitoring
  int _totalImagesProcessed = 0;
  int _totalRenderTime = 0;
  final StreamController<GraphicsEvent> _eventController =
      StreamController.broadcast();

  GraphicsProtocolHandler([this._terminal, this._controller]);

  bool get isInitialized => _isInitialized;
  bool get trueColorEnabled => _trueColorEnabled;
  bool get kittyProtocolEnabled => _kittyProtocolEnabled;
  bool get sixelEnabled => _sixelEnabled;
  bool get alphaChannelEnabled => _alphaChannelEnabled;

  Stream<GraphicsEvent> get events => _eventController.stream;
  Map<String, GraphicsImage> get cachedImages => Map.unmodifiable(_imageCache);
  Map<String, Offset> get imagePositions => Map.unmodifiable(_imagePositions);

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

      try {
        final dir = await getTemporaryDirectory();
        _cacheDir = dir.path;
      } catch (_) {
        _cacheDir = Directory.systemTemp.path;
      }

      _isInitialized = true;
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.initialized,
          'Graphics Protocol Handler initialized with True Color support',
        ),
      );
    } catch (e) {
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.error,
          'Failed to initialize Graphics Protocol Handler: $e',
          data: {'error': e.toString()},
        ),
      );
      rethrow;
    }
  }

  /// Set up output interception to handle graphics protocols
  void _setupOutputInterception() {
    final terminal = _terminal;
    if (terminal == null) return;
    final original = terminal.onOutput;
    terminal.onOutput = (data) {
      final processed = processOutput(
        data,
        terminal.buffer.cursorX,
        terminal.buffer.cursorY,
      );
      original?.call(processed);
    };
  }

  /// Initialize default color palette (256 colors + true color support)
  void _initializeColorPalette() {
    // ANSI 16-color palette
    final standardColors = [
      0x000000,
      0x800000,
      0x008000,
      0x808000,
      0x000080,
      0x800080,
      0x008080,
      0xc0c0c0,
      0x808080,
      0xff0000,
      0x00ff00,
      0xffff00,
      0x0000ff,
      0xff00ff,
      0x00ffff,
      0xffffff,
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
      return _parseBasicAnsiColor(sequence, isBackground: isBackground);
    }

    try {
      // Parse True Color (RGB) sequences: ESC[38;2;r;g;b or ESC[48;2;r;g;b
      final rgbMatch = RegExp(
        r'\x1b\[(38|48);2;(\d+);(\d+);(\d+)m',
      ).firstMatch(sequence);
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
      debugPrint('Failed to parse ANSI color: $e');
      return Colors.white;
    }
  }

  /// Parse basic ANSI colors (fallback)
  Color _parseBasicAnsiColor(String sequence, {bool isBackground = false}) {
    final match = RegExp(r'\x1b\[(\d+)m').firstMatch(sequence);
    if (match != null) {
      final code = int.parse(match.group(1)!);
      final colorMap = {
        30: Colors.black,
        31: Colors.red,
        32: Colors.green,
        33: Colors.yellow,
        34: Colors.blue,
        35: const Color(0xFFFF00FF),
        36: Colors.cyan,
        37: Colors.white,
        40: Colors.black,
        41: Colors.red,
        42: Colors.green,
        43: Colors.yellow,
        44: Colors.blue,
        45: const Color(0xFFFF00FF),
        46: Colors.cyan,
        47: Colors.white,
      };
      return colorMap[code] ?? Colors.white;
    }
    return Colors.white;
  }

  /// Process terminal output for graphics protocol sequences
  String processOutput(String output, int cursorX, int cursorY) {
    if (!_isInitialized) return output;

    String processed = output;

    // Process Sixel sequences
    processed = _processSixelSequences(processed, cursorX, cursorY);

    // Process Kitty graphics sequences
    processed = _processKittySequences(processed, cursorX, cursorY);

    return processed;
  }

  /// Process Sixel graphics sequences in output
  String _processSixelSequences(String output, int cursorX, int cursorY) {
    if (!_sixelEnabled) return output;

    // Look for Sixel DCS sequences: ESC P ... ESC \
    final sixelRegex = RegExp(r'\x1bP([0-9;]*)(.*?)\x1b\\', dotAll: true);
    return output.replaceAllMapped(sixelRegex, (match) {
      final params = match.group(1) ?? '';
      final data = match.group(2) ?? '';
      final response = handleSixel('\x1bP$params$data\x1b\\', cursorX, cursorY);
      return response.isNotEmpty ? response : '';
    });
  }

  /// Process Kitty graphics sequences in output
  String _processKittySequences(String output, int cursorX, int cursorY) {
    if (!_kittyProtocolEnabled) return output;

    // Look for Kitty sequences: ESC _ G ... ESC \
    final kittyRegex = RegExp(r'\x1b_G([^\\]*)\x1b\\', dotAll: true);
    return output.replaceAllMapped(kittyRegex, (match) {
      final data = match.group(1) ?? '';
      final response = handleKittyProtocol(
        '\x1b_G$data\x1b\\',
        cursorX,
        cursorY,
      );
      return response.isNotEmpty ? response : '';
    });
  }

  /// Handle Kitty Graphics Protocol
  String handleKittyProtocol(String sequence, int cursorX, int cursorY) {
    if (!_kittyProtocolEnabled) return '';

    try {
      // Parse Kitty graphics sequences: _Gq=1,i=id,t=f,f=24,s=w,h=h
      final match = RegExp(r'_G[^\\]*\\').firstMatch(sequence);
      if (match != null) {
        final params = match.group(0)!;
        return _processKittyGraphics(params, cursorX, cursorY);
      }
    } catch (e) {
      debugPrint('Failed to handle Kitty protocol: $e');
    }

    return '';
  }

  /// Process Kitty graphics parameters
  String _processKittyGraphics(String params, int cursorX, int cursorY) {
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
        return _handleKittyAction(paramMap, cursorX, cursorY);
      case 't': // Transmission
        return _handleKittyTransmission(paramMap, cursorX, cursorY);
      case 'q': // Query
        return _handleKittyQuery(paramMap);
      default:
        return '';
    }
  }

  /// Handle Kitty graphics actions
  String _handleKittyAction(
    Map<String, String> params,
    int cursorX,
    int cursorY,
  ) {
    final action = params['a'];

    switch (action) {
      case 'p': // Put image
        return _putKittyImage(params, cursorX, cursorY);
      case 'd': // Delete image
        return _deleteKittyImage(params);
      case 'q': // Query
        return _queryKittyImage(params);
      default:
        return '';
    }
  }

  /// Put image via Kitty protocol
  String _putKittyImage(Map<String, String> params, int cursorX, int cursorY) {
    final id = params['i'] ?? _nextImageId.toString();
    final width = int.tryParse(params['s'] ?? '0') ?? 0;
    final height = int.tryParse(params['h'] ?? '0') ?? 0;

    // Store image metadata
    _imageCache[id] = GraphicsImage(
      id: _nextImageId++,
      width: width,
      height: height,
      data: '', // Will be filled by transmission
      format: 'kitty',
    );

    // Store position
    _imagePositions[id] = Offset(cursorX.toDouble(), cursorY.toDouble());

    _eventController.add(
      GraphicsEvent(
        GraphicsEventType.imageReceived,
        'Kitty image received',
        data: {'id': id, 'width': width, 'height': height},
      ),
    );

    // Return acknowledgment
    return '\x1b_Gi=$id;OK\x1b\\';
  }

  /// Delete image via Kitty protocol
  String _deleteKittyImage(Map<String, String> params) {
    final id = params['i'];
    if (id != null) {
      _imageCache.remove(id);
      _imagePositions.remove(id);
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.imageDeleted,
          'Kitty image deleted',
          data: {'id': id},
        ),
      );
    }
    return '\x1b_GOK\x1b\\';
  }

  /// Query image via Kitty protocol
  String _queryKittyImage(Map<String, String> params) {
    final id = params['i'];
    if (id != null && _imageCache.containsKey(id)) {
      final image = _imageCache[id]!;
      return '\x1b_Gi=$id;w=${image.width};h=${image.height};OK\x1b\\';
    }
    return '\x1b_GFAIL\x1b\\';
  }

  /// Handle Kitty graphics transmission
  String _handleKittyTransmission(
    Map<String, String> params,
    int cursorX,
    int cursorY,
  ) {
    // Handle image data transmission
    final format = params['t'] ?? 'f';
    final id = params['i'] ?? _nextImageId.toString();

    // Process image data based on format
    switch (format) {
      case 'f': // Direct transmission
        return _processDirectTransmission(params, id, cursorX, cursorY);
      case 't': // Temporary file
        return _processTemporaryFileTransmission(params, id, cursorX, cursorY);
      default:
        return '';
    }
  }

  /// Process direct image transmission
  String _processDirectTransmission(
    Map<String, String> params,
    String id,
    int cursorX,
    int cursorY,
  ) {
    try {
      final data = params['d'];
      final format = params['f'] ?? '100';
      final width = int.tryParse(params['w'] ?? '0') ?? 0;
      final height = int.tryParse(params['h'] ?? '0') ?? 0;

      if (data == null) return '\x1b_Gi=$id,f=32\x1b\\'; // Error: no data

      // Validate base64 data
      try {
        base64.decode(data);
      } catch (e) {
        return '\x1b_Gi=$id,f=32\x1b\\'; // Error: invalid base64
      }

      // Store image data
      if (_imageCache.containsKey(id)) {
        final image = _imageCache[id]!;
        _imageCache[id] = GraphicsImage(
          id: image.id,
          width: width > 0 ? width : image.width,
          height: height > 0 ? height : image.height,
          data: data,
          format: 'kitty',
        );

        // Ensure position is set
        _imagePositions[id] ??= Offset(cursorX.toDouble(), cursorY.toDouble());
      }

      _totalImagesProcessed++;
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.imageProcessed,
          'Kitty image processed',
          data: {'id': id, 'size': data.length},
        ),
      );

      return '\x1b_Gi=$id,f=$format\x1b\\';
    } catch (e) {
      debugPrint('Error processing direct transmission: $e');
      return '\x1b_Gi=$id,f=32\x1b\\'; // Error response
    }
  }

  /// Process temporary file transmission
  String _processTemporaryFileTransmission(
    Map<String, String> params,
    String id,
    int cursorX,
    int cursorY,
  ) {
    try {
      final data = params['d'];
      final format = params['f'] ?? '100';
      final width = int.tryParse(params['w'] ?? '0') ?? 0;
      final height = int.tryParse(params['h'] ?? '0') ?? 0;

      if (data == null) return '\x1b_Gi=$id,f=32\x1b\\';

      final bytes = base64.decode(data);
      final cacheDir = _cacheDir ?? Directory.systemTemp.path;
      final filePath = '$cacheDir/kitty_temp_$id.tmp';
      final file = File(filePath);
      file.writeAsBytesSync(bytes);
      _tempFilePaths.add(filePath);

      if (_imageCache.containsKey(id)) {
        final image = _imageCache[id]!;
        _imageCache[id] = GraphicsImage(
          id: image.id,
          width: width > 0 ? width : image.width,
          height: height > 0 ? height : image.height,
          data: data,
          format: 'kitty',
        );
        _imagePositions[id] ??= Offset(cursorX.toDouble(), cursorY.toDouble());
      } else {
        _imageCache[id] = GraphicsImage(
          id: _nextImageId++,
          width: width,
          height: height,
          data: data,
          format: 'kitty',
        );
        _imagePositions[id] = Offset(cursorX.toDouble(), cursorY.toDouble());
      }

      _totalImagesProcessed++;
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.imageProcessed,
          'Kitty temp file processed',
          data: {'id': id, 'path': filePath, 'size': bytes.length},
        ),
      );

      return '\x1b_Gi=$id,f=$format\x1b\\';
    } catch (e) {
      debugPrint('Error processing temporary file transmission: $e');
      return '\x1b_Gi=$id,f=32\x1b\\';
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
  String handleSixel(String sequence, int cursorX, int cursorY) {
    if (!_sixelEnabled) return '';

    try {
      // Parse Sixel DCS sequences: ESC P ... ESC \
      final match = RegExp(r'\x1bP([0-9;]*)(.*?)\x1b\\').firstMatch(sequence);
      if (match != null) {
        return _processSixel(
          match.group(1)!,
          match.group(2)!,
          cursorX,
          cursorY,
        );
      }
    } catch (e) {
      debugPrint('Failed to handle Sixel: $e');
    }

    return '';
  }

  /// Process Sixel data
  String _processSixel(String params, String data, int cursorX, int cursorY) {
    try {
      // Parse Sixel parameters
      final paramMap = <String, String>{};
      final paramPairs = params.split(';');

      for (final pair in paramPairs) {
        if (pair.contains('=')) {
          final parts = pair.split('=');
          if (parts.length == 2) {
            paramMap[parts[0]] = parts[1];
          }
        }
      }

      final width = int.tryParse(paramMap['1'] ?? '0') ?? 100;
      final height = int.tryParse(paramMap['2'] ?? '0') ?? 100;

      // Create image from Sixel data
      final imageId = _nextImageId++;
      final idStr = imageId.toString();
      _imageCache[idStr] = GraphicsImage(
        id: imageId,
        width: width,
        height: height,
        data: data,
        format: 'sixel',
      );

      // Store position
      _imagePositions[idStr] = Offset(cursorX.toDouble(), cursorY.toDouble());

      _totalImagesProcessed++;
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.imageProcessed,
          'Sixel image processed',
          data: {'id': imageId, 'width': width, 'height': height},
        ),
      );

      return '\x1b_Gi=$imageId;OK\x1b\\';
    } catch (e) {
      debugPrint('Error processing Sixel data: $e');
      return '\x1b_Gi=1,f=32\x1b\\'; // Error response
    }
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

    final startTime = DateTime.now();

    try {
      // Convert image based on format
      Uint8List? result;
      switch (image.format) {
        case 'sixel':
          result = _convertSixelToRGBA(
            image,
            targetWidth,
            targetHeight,
            enableAlpha,
          );
          break;
        case 'kitty':
          result = await _convertKittyToRGBA(
            image,
            targetWidth,
            targetHeight,
            enableAlpha,
          );
          break;
        default:
          result = null;
      }

      final endTime = DateTime.now();
      final renderTime = endTime.difference(startTime).inMilliseconds;
      _totalRenderTime += renderTime;

      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.imageRendered,
          'Image converted for display',
          data: {
            'id': imageId,
            'format': image.format,
            'renderTime': renderTime,
            'size': result?.length ?? 0,
          },
        ),
      );

      return result;
    } catch (e) {
      debugPrint('Failed to convert image: $e');
      _eventController.add(
        GraphicsEvent(
          GraphicsEventType.renderError,
          'Image conversion failed',
          data: {'id': imageId, 'error': e.toString()},
        ),
      );
      return null;
    }
  }

  ({int value, int next}) _parseSixelInt(List<int> runes, int start) {
    int v = 0;
    int i = start;
    while (i < runes.length) {
      final c = runes[i];
      if (c >= 0x30 && c <= 0x39) {
        v = v * 10 + (c - 0x30);
        i++;
      } else {
        break;
      }
    }
    return (value: v, next: i);
  }

  List<int> _readSixelSemicolonNumbers(List<int> runes, int start) {
    final vals = <int>[];
    int i = start;
    while (i < runes.length) {
      final c = runes[i];
      if (c >= 0x30 && c <= 0x39) {
        final res = _parseSixelInt(runes, i);
        vals.add(res.value);
        i = res.next;
      } else if (c == 0x3B) {
        i++;
      } else {
        break;
      }
    }
    return vals;
  }

  Color _hlsToRgb(double h, double l, double s) {
    double r, g, b;
    if (s == 0) {
      r = g = b = l;
    } else {
      double hue2rgb(double p, double q, double t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1 / 6) return p + (q - p) * 6 * t;
        if (t < 1 / 2) return q;
        if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
        return p;
      }

      final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      final p = 2 * l - q;
      r = hue2rgb(p, q, h + 1 / 3);
      g = hue2rgb(p, q, h);
      b = hue2rgb(p, q, h - 1 / 3);
    }
    return Color.fromARGB(
      255,
      (r * 255).round(),
      (g * 255).round(),
      (b * 255).round(),
    );
  }

  /// Convert Sixel to RGBA format
  Uint8List _convertSixelToRGBA(
    GraphicsImage image,
    int? targetWidth,
    int? targetHeight,
    bool enableAlpha,
  ) {
    final runes = image.data.runes.toList();
    int idx = 0;
    while (idx < runes.length && (runes[idx] <= 0x20 || runes[idx] == 0x71)) {
      idx++;
    }

    int x = 0, y = 0;
    int maxX = 0, maxY = 0;
    int? rasterW, rasterH;
    final colors = <int, Color>{};

    // first pass: determine dimensions and build palette
    for (int i = idx; i < runes.length;) {
      final c = runes[i];
      if (c == 0x1B) {
        i++;
        if (i < runes.length && runes[i] == 0x5C) i++;
        continue;
      }
      if (c == 0x22) {
        i++;
        final vals = _readSixelSemicolonNumbers(runes, i);
        i = _skipSixelNumbers(runes, i);
        if (vals.length >= 3 && vals[2] > 0) rasterW = vals[2];
        if (vals.length >= 4 && vals[3] > 0) rasterH = vals[3];
        continue;
      }
      if (c == 0x21) {
        i++;
        final res = _parseSixelInt(runes, i);
        final count = res.value;
        i = res.next;
        if (i < runes.length && runes[i] >= 63 && runes[i] <= 126) {
          x += count;
          i++;
        }
        continue;
      }
      if (c == 0x2D) {
        if (x > maxX) maxX = x;
        x = 0;
        y += 6;
        i++;
        continue;
      }
      if (c == 0x24) {
        if (x > maxX) maxX = x;
        x = 0;
        i++;
        continue;
      }
      if (c >= 63 && c <= 126) {
        x++;
        i++;
        continue;
      }
      if (c == 0x23) {
        i++;
        final regRes = _parseSixelInt(runes, i);
        int reg = regRes.value;
        i = regRes.next;
        if (i < runes.length && runes[i] == 0x3B) {
          i++;
          final modeRes = _parseSixelInt(runes, i);
          int mode = modeRes.value;
          i = modeRes.next;
          if (i < runes.length && runes[i] == 0x3B) {
            i++;
            final nums = <int>[];
            while (i < runes.length) {
              final rc = runes[i];
              if (rc >= 0x30 && rc <= 0x39) {
                final nres = _parseSixelInt(runes, i);
                nums.add(nres.value);
                i = nres.next;
              } else if (rc == 0x3B) {
                i++;
              } else {
                break;
              }
            }
            if (mode == 2 && nums.length >= 3) {
              int r = nums[0], g = nums[1], b = nums[2];
              if (r <= 100 && g <= 100 && b <= 100) {
                r = (r * 255) ~/ 100;
                g = (g * 255) ~/ 100;
                b = (b * 255) ~/ 100;
              }
              colors[reg] = Color.fromARGB(
                255,
                r.clamp(0, 255),
                g.clamp(0, 255),
                b.clamp(0, 255),
              );
            } else if (mode == 1 && nums.length >= 3) {
              colors[reg] = _hlsToRgb(
                nums[0] / 360.0,
                nums[1] / 100.0,
                nums[2] / 100.0,
              );
            }
          }
        }
        continue;
      }
      i++;
    }
    if (x > maxX) maxX = x;
    if (y + 6 > maxY) maxY = y + 6;

    int width = targetWidth ?? rasterW ?? maxX;
    if (width <= 0) width = image.width;
    int height = targetHeight ?? rasterH ?? maxY;
    if (height <= 0) height = image.height;

    final pixels = Uint8List(width * height * 4);
    for (int i = 3; i < pixels.length; i += 4) {
      pixels[i] = enableAlpha ? 0 : 255;
    }

    // second pass: render
    x = 0;
    y = 0;
    Color currentColor = Colors.white;
    for (int i = idx; i < runes.length;) {
      final c = runes[i];
      if (c == 0x1B) {
        i++;
        if (i < runes.length && runes[i] == 0x5C) i++;
        continue;
      }
      if (c == 0x22) {
        i++;
        while (i < runes.length &&
            ((runes[i] >= 0x30 && runes[i] <= 0x39) || runes[i] == 0x3B)) {
          i++;
        }
        continue;
      }
      if (c == 0x21) {
        i++;
        final res = _parseSixelInt(runes, i);
        final count = res.value;
        i = res.next;
        if (i < runes.length && runes[i] >= 63 && runes[i] <= 126) {
          final sixelVal = runes[i] - 63;
          for (int r = 0; r < count; r++) {
            for (int bit = 0; bit < 6; bit++) {
              if ((sixelVal & (1 << bit)) != 0) {
                final py = y + bit;
                final px = x;
                if (px < width && py < height) {
                  final p = (py * width + px) * 4;
                  pixels[p] = currentColor.red;
                  pixels[p + 1] = currentColor.green;
                  pixels[p + 2] = currentColor.blue;
                  pixels[p + 3] = enableAlpha ? currentColor.alpha : 255;
                }
              }
            }
            x++;
            if (x >= width) {
              x = 0;
              y += 6;
            }
          }
          i++;
        }
        continue;
      }
      if (c == 0x2D) {
        x = 0;
        y += 6;
        i++;
        continue;
      }
      if (c == 0x24) {
        x = 0;
        i++;
        continue;
      }
      if (c >= 63 && c <= 126) {
        final sixelVal = c - 63;
        for (int bit = 0; bit < 6; bit++) {
          if ((sixelVal & (1 << bit)) != 0) {
            final py = y + bit;
            final px = x;
            if (px < width && py < height) {
              final p = (py * width + px) * 4;
              pixels[p] = currentColor.red;
              pixels[p + 1] = currentColor.green;
              pixels[p + 2] = currentColor.blue;
              pixels[p + 3] = enableAlpha ? currentColor.alpha : 255;
            }
          }
        }
        x++;
        if (x >= width) {
          x = 0;
          y += 6;
        }
        i++;
        continue;
      }
      if (c == 0x23) {
        i++;
        final regRes = _parseSixelInt(runes, i);
        int reg = regRes.value;
        i = regRes.next;
        if (i < runes.length && runes[i] == 0x3B) {
          i++;
          final modeRes = _parseSixelInt(runes, i);
          int mode = modeRes.value;
          i = modeRes.next;
          if (i < runes.length && runes[i] == 0x3B) {
            i++;
            final nums = <int>[];
            while (i < runes.length) {
              final rc = runes[i];
              if (rc >= 0x30 && rc <= 0x39) {
                final nres = _parseSixelInt(runes, i);
                nums.add(nres.value);
                i = nres.next;
              } else if (rc == 0x3B) {
                i++;
              } else {
                break;
              }
            }
            if (mode == 2 && nums.length >= 3) {
              int r = nums[0], g = nums[1], b = nums[2];
              if (r <= 100 && g <= 100 && b <= 100) {
                r = (r * 255) ~/ 100;
                g = (g * 255) ~/ 100;
                b = (b * 255) ~/ 100;
              }
              colors[reg] = Color.fromARGB(
                255,
                r.clamp(0, 255),
                g.clamp(0, 255),
                b.clamp(0, 255),
              );
            } else if (mode == 1 && nums.length >= 3) {
              colors[reg] = _hlsToRgb(
                nums[0] / 360.0,
                nums[1] / 100.0,
                nums[2] / 100.0,
              );
            }
          }
          if (colors.containsKey(reg)) currentColor = colors[reg]!;
        } else {
          if (colors.containsKey(reg)) currentColor = colors[reg]!;
        }
        continue;
      }
      i++;
    }

    return pixels;
  }

  int _skipSixelNumbers(List<int> runes, int start) {
    int i = start;
    while (i < runes.length &&
        ((runes[i] >= 0x30 && runes[i] <= 0x39) || runes[i] == 0x3B)) {
      i++;
    }
    return i;
  }

  /// Convert Kitty image to RGBA format
  Future<Uint8List> _convertKittyToRGBA(
    GraphicsImage image,
    int? targetWidth,
    int? targetHeight,
    bool enableAlpha,
  ) async {
    final width = targetWidth ?? image.width;
    final height = targetHeight ?? image.height;
    final data = Uint8List(width * height * 4);

    try {
      final imageBytes = base64.decode(image.data);
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final actualW = uiImage.width;
      final actualH = uiImage.height;
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      codec.dispose();
      if (byteData == null) throw Exception('decode failed');
      final raw = byteData.buffer.asUint8List();

      for (int y = 0; y < height; y++) {
        final srcY = (y * actualH) ~/ height;
        for (int x = 0; x < width; x++) {
          final srcX = (x * actualW) ~/ width;
          final s = (srcY * actualW + srcX) * 4;
          final d = (y * width + x) * 4;
          data[d] = raw[s];
          data[d + 1] = raw[s + 1];
          data[d + 2] = raw[s + 2];
          data[d + 3] = enableAlpha ? raw[s + 3] : 255;
        }
      }
    } catch (e) {
      debugPrint('Failed to decode Kitty image: $e');
      for (int i = 0; i < data.length; i += 4) {
        data[i] = 128;
        data[i + 1] = 128;
        data[i + 2] = 128;
        data[i + 3] = enableAlpha ? 255 : 255;
      }
    }

    return data;
  }

  /// Clear image cache
  void clearImageCache() {
    for (final path in _tempFilePaths) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    _tempFilePaths.clear();
    _imageCache.clear();
    _imagePositions.clear();
    _pendingImages.clear();
    _pictureCache.clear();
    _damageRegions.clear();
    _eventController.add(
      GraphicsEvent(GraphicsEventType.cacheCleared, 'Graphics cache cleared'),
    );
  }

  /// Get cached image
  GraphicsImage? getCachedImage(String imageId) {
    return _imageCache[imageId];
  }

  /// Get all cached images
  Map<String, GraphicsImage> getCachedImages() {
    return Map.unmodifiable(_imageCache);
  }

  /// Toggle graphics features
  void setTrueColorEnabled(bool enabled) {
    _trueColorEnabled = enabled;
    _eventController.add(
      GraphicsEvent(
        GraphicsEventType.settingChanged,
        'True Color ${enabled ? 'enabled' : 'disabled'}',
        data: {'feature': 'trueColor', 'enabled': enabled},
      ),
    );
  }

  void setKittyProtocolEnabled(bool enabled) {
    _kittyProtocolEnabled = enabled;
    _eventController.add(
      GraphicsEvent(
        GraphicsEventType.settingChanged,
        'Kitty Protocol ${enabled ? 'enabled' : 'disabled'}',
        data: {'feature': 'kitty', 'enabled': enabled},
      ),
    );
  }

  void setSixelEnabled(bool enabled) {
    _sixelEnabled = enabled;
    _eventController.add(
      GraphicsEvent(
        GraphicsEventType.settingChanged,
        'Sixel ${enabled ? 'enabled' : 'disabled'}',
        data: {'feature': 'sixel', 'enabled': enabled},
      ),
    );
  }

  void setAlphaChannelEnabled(bool enabled) {
    _alphaChannelEnabled = enabled;
    _eventController.add(
      GraphicsEvent(
        GraphicsEventType.settingChanged,
        'Alpha Channel ${enabled ? 'enabled' : 'disabled'}',
        data: {'feature': 'alpha', 'enabled': enabled},
      ),
    );
  }

  /// Check if image format is supported
  bool isImageFormatSupported(String extension) {
    return _supportedImageFormats.contains(extension.toLowerCase());
  }

  /// Load image from file
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

  /// Get performance statistics
  Map<String, dynamic> getPerformanceStats() {
    final avgRenderTime = _totalImagesProcessed > 0
        ? _totalRenderTime / _totalImagesProcessed
        : 0.0;

    return {
      'totalImagesProcessed': _totalImagesProcessed,
      'totalRenderTime': _totalRenderTime,
      'averageRenderTime': avgRenderTime,
      'cachedImages': _imageCache.length,
      'cachedPictures': _pictureCache.length,
    };
  }

  /// Dispose resources
  void dispose() {
    clearImageCache();
    _colorPalette.clear();
    _animations.clear();
    _eventController.close();
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

  @override
  String toString() => 'GraphicsImage(id: $id, ${width}x$height, $format)';
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

/// Graphics overlay for positioning images
class GraphicsOverlay {
  final String imageId;
  final Offset position;
  final Size size;
  final DateTime createdAt;

  GraphicsOverlay({
    required this.imageId,
    required this.position,
    required this.size,
  }) : createdAt = DateTime.now();
}

/// Graphics animation data
class GraphicsAnimation {
  final String id;
  final List<String> frameIds;
  final Duration frameDuration;
  final bool loop;

  GraphicsAnimation({
    required this.id,
    required this.frameIds,
    required this.frameDuration,
    this.loop = false,
  });
}

/// Graphics protocol state
class GraphicsProtocolState {
  Color? currentColor;
  Color? backgroundColor;
  int? currentPaletteIndex;

  GraphicsProtocolState({
    this.currentColor,
    this.backgroundColor,
    this.currentPaletteIndex,
  });
}

/// Graphics event types
enum GraphicsEventType {
  initialized,
  imageReceived,
  imageProcessed,
  imageRendered,
  imageDeleted,
  renderError,
  settingChanged,
  cacheCleared,
  error,
}

/// Graphics event
class GraphicsEvent {
  final GraphicsEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  GraphicsEvent(this.type, this.message, {this.data})
    : timestamp = DateTime.now();

  @override
  String toString() => '[$timestamp] $type: $message';
}
