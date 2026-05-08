import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'graphics_protocol_handler.dart';
import '../core/high_performance_terminal_renderer.dart';

/// Multimedia Terminal Renderer
/// 
/// Extends the high-performance terminal renderer with support for inline
/// graphics, animations, and multimedia content using SIXEL, Kitty, and iTerm2 protocols.
class MultimediaTerminalRenderer extends HighPerformanceTerminalRenderer {
  final GraphicsProtocolHandler _graphicsHandler;
  final List<GraphicsOverlay> _overlays = [];
  final Map<String, GraphicsAnimation> _activeAnimations = {};
  
  // Animation timer
  Timer? _animationTimer;
  
  // Performance optimization
  final Set<String> _dirtyOverlays = {};
  
  MultimediaTerminalRenderer({
    required super.columns,
    required super.rows,
    required super.gpuRenderer,
    required GraphicsConfig graphicsConfig,
  }) : _graphicsHandler = GraphicsProtocolHandler(config: graphicsConfig) {
    _initializeMultimedia();
  }
  
  void _initializeMultimedia() {
    // Start animation timer
    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _updateAnimations();
    });
    
    debugPrint('🎨 Multimedia terminal renderer initialized');
  }
  
  /// Write text with graphics protocol support
  @override
  void write(String text, {
    int? col,
    int? row,
    TerminalStyle? style,
    bool moveCursor = true,
  }) {
    // Check for graphics escape sequences
    final graphicsResult = _parseGraphicsSequences(text, col ?? 0, row ?? 0);
    
    if (graphicsResult != null) {
      _handleGraphicsResult(graphicsResult);
      return;
    }
    
    // Handle normal text
    super.write(text, col: col, row: row, style: style, moveCursor: moveCursor);
  }
  
  /// Parse and handle graphics escape sequences
  GraphicsResult? _parseGraphicsSequences(String text, int cursorX, int cursorY) {
    // Look for graphics escape sequences
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '\x1b') {
        // Found potential escape sequence
        var sequenceEnd = i + 1;
        
        // Find end of sequence
        while (sequenceEnd < text.length) {
          final char = text[sequenceEnd];
          if (char == '\\' || char == '\x07' || char == 'G' || char == 'q') {
            break;
          }
          sequenceEnd++;
        }
        
        if (sequenceEnd < text.length) {
          final sequence = text.substring(i, sequenceEnd + 1);
          final result = _graphicsHandler.parseSequence(sequence, cursorX, cursorY);
          
          if (result != null) {
            // Skip the processed sequence in normal text processing
            final remainingText = text.substring(sequenceEnd + 1);
            if (remainingText.isNotEmpty) {
              super.write(remainingText, col: cursorX, row: cursorY, moveCursor: false);
            }
            return result;
          }
        }
      }
    }
    
    return null;
  }
  
  /// Handle graphics rendering result
  void _handleGraphicsResult(GraphicsResult result) {
    switch (result.type) {
      case GraphicsType.image:
        if (result.image != null) {
          _addImageOverlay(result);
        }
        break;
      case GraphicsType.animation:
        if (result.animation != null) {
          _addAnimationOverlay(result);
        }
        break;
      case GraphicsType.clear:
        _clearOverlays(result.x, result.y, result.width, result.height);
        break;
    }
  }
  
  /// Add image overlay to terminal
  void _addImageOverlay(GraphicsResult result) {
    final image = result.image!;
    
    // Create overlay
    final overlay = GraphicsOverlay(
      id: image.id,
      type: GraphicsOverlayType.image,
      x: result.x,
      y: result.y,
      width: result.width,
      height: result.height,
      image: image,
    );
    
    _overlays.add(overlay);
    _dirtyOverlays.add(overlay.id);
    
    // Mark region as dirty
    _markDirty(result.x, result.y);
  }
  
  /// Add animation overlay to terminal
  void _addAnimationOverlay(GraphicsResult result) {
    final animation = result.animation!;
    
    // Create overlay
    final overlay = GraphicsOverlay(
      id: animation.id,
      type: GraphicsOverlayType.animation,
      x: result.x,
      y: result.y,
      width: result.width,
      height: result.height,
      animation: animation,
    );
    
    _overlays.add(overlay);
    _activeAnimations[animation.id] = animation;
    _dirtyOverlays.add(overlay.id);
    
    // Mark region as dirty
    _markDirty(result.x, result.y);
  }
  
  /// Clear overlays in region
  void _clearOverlays(int x, int y, int width, int height) {
    _overlays.removeWhere((overlay) {
      if (overlay.x >= x && overlay.y >= y &&
          overlay.x < x + width && overlay.y < y + height) {
        _dirtyOverlays.remove(overlay.id);
        if (overlay.animation != null) {
          _activeAnimations.remove(overlay.animation!.id);
        }
        return true;
      }
      return false;
    });
    
    _markDirty(x, y);
  }
  
  /// Update animations
  void _updateAnimations() {
    if (_activeAnimations.isEmpty) return;
    
    bool needsRedraw = false;
    
    for (final animation in _activeAnimations.values) {
      if (animation.updateFrame()) {
        // Find overlay for this animation
        final overlay = _overlays.firstWhere(
          (o) => o.animation?.id == animation.id,
          orElse: () => GraphicsOverlay.empty(),
        );
        
        if (overlay.id.isNotEmpty) {
          _dirtyOverlays.add(overlay.id);
          needsRedraw = true;
        }
      }
    }
    
    if (needsRedraw) {
      markFullRedraw();
    }
  }
  
  /// Render with graphics overlays
  @override
  void render(ui.Canvas canvas, Size size) {
    // Render base terminal content
    super.render(canvas, size);
    
    // Render graphics overlays
    _renderOverlays(canvas, size);
  }
  
  /// Render graphics overlays
  void _renderOverlays(ui.Canvas canvas, Size size) {
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;
    
    for (final overlay in _overlays) {
      if (!_dirtyOverlays.contains(overlay.id)) {
        continue; // Skip clean overlays
      }
      
      final x = overlay.x * cellWidth;
      final y = overlay.y * cellHeight;
      final width = overlay.width * cellWidth;
      final height = overlay.height * cellHeight;
      
      switch (overlay.type) {
        case GraphicsOverlayType.image:
          _renderImageOverlay(canvas, overlay, x, y, width, height);
          break;
        case GraphicsOverlayType.animation:
          _renderAnimationOverlay(canvas, overlay, x, y, width, height);
          break;
      }
    }
    
    // Clear dirty flags
    _dirtyOverlays.clear();
  }
  
  /// Render image overlay
  void _renderImageOverlay(ui.Canvas canvas, GraphicsOverlay overlay, double x, double y, double width, double height) {
    final image = overlay.image!;
    
    if (image.decodedImage != null) {
      // Calculate scaling to fit
      final scaleX = width / image.decodedImage!.width;
      final scaleY = height / image.decodedImage!.height;
      final scale = math.min(scaleX, scaleY);
      
      final scaledWidth = image.decodedImage!.width * scale;
      final scaledHeight = image.decodedImage!.height * scale;
      
      // Center the image
      final offsetX = (width - scaledWidth) / 2;
      final offsetY = (height - scaledHeight) / 2;
      
      canvas.drawImageRect(
        image.decodedImage!,
        Rect.fromLTWH(0, 0, image.decodedImage!.width, image.decodedImage!.height),
        Rect.fromLTWH(x + offsetX, y + offsetY, scaledWidth, scaledHeight),
        Paint(),
      );
    }
  }
  
  /// Render animation overlay
  void _renderAnimationOverlay(ui.Canvas canvas, GraphicsOverlay overlay, double x, double y, double width, double height) {
    final animation = overlay.animation!;
    final currentFrame = animation.getCurrentFrame();
    
    if (currentFrame != null && currentFrame.decodedImage != null) {
      // Calculate scaling to fit
      final scaleX = width / currentFrame.decodedImage!.width;
      final scaleY = height / currentFrame.decodedImage!.height;
      final scale = math.min(scaleX, scaleY);
      
      final scaledWidth = currentFrame.decodedImage!.width * scale;
      final scaledHeight = currentFrame.decodedImage!.height * scale;
      
      // Center the image
      final offsetX = (width - scaledWidth) / 2;
      final offsetY = (height - scaledHeight) / 2;
      
      canvas.drawImageRect(
        currentFrame.decodedImage!,
        Rect.fromLTWH(0, 0, currentFrame.decodedImage!.width, currentFrame.decodedImage!.height),
        Rect.fromLTWH(x + offsetX, y + offsetY, scaledWidth, scaledHeight),
        Paint(),
      );
    }
  }
  
  /// Download and display image from URL
  Future<void> displayImageFromUrl(String url, {int? col, int? row}) async {
    final image = await _graphicsHandler.downloadImage(url);
    if (image != null) {
      final result = GraphicsResult(
        type: GraphicsType.image,
        image: image,
        x: col ?? 0,
        y: row ?? 0,
        width: image.width,
        height: image.height,
      );
      
      _handleGraphicsResult(result);
    }
  }
  
  /// Display image from bytes
  Future<void> displayImageFromBytes(Uint8List bytes, {int? col, int? row}) async {
    final format = _graphicsHandler._detectImageFormat(bytes);
    final image = GraphicsImage(
      id: 'bytes_${DateTime.now().millisecondsSinceEpoch}',
      data: bytes,
      format: format,
      width: 0,
      height: 0,
    );
    
    await _graphicsHandler._decodeImage(image);
    
    if (image.decodedImage != null) {
      final result = GraphicsResult(
        type: GraphicsType.image,
        image: image,
        x: col ?? 0,
        y: row ?? 0,
        width: image.width,
        height: image.height,
      );
      
      _handleGraphicsResult(result);
    }
  }
  
  /// Generate SIXEL from image at cursor position
  Future<String> generateSixelAtCursor(int cursorX, int cursorY) async {
    // Find image at cursor position
    final overlay = _overlays.firstWhere(
      (o) => o.x == cursorX && o.y == cursorY && o.image != null,
      orElse: () => GraphicsOverlay.empty(),
    );
    
    if (overlay.id.isNotEmpty && overlay.image != null) {
      return await _graphicsHandler.generateSixel(overlay.image!);
    }
    
    return '';
  }
  
  /// Generate Kitty graphics from image at cursor position
  Future<String> generateKittyAtCursor(int cursorX, int cursorY) async {
    // Find image at cursor position
    final overlay = _overlays.firstWhere(
      (o) => o.x == cursorX && o.y == cursorY && o.image != null,
      orElse: () => GraphicsOverlay.empty(),
    );
    
    if (overlay.id.isNotEmpty && overlay.image != null) {
      return await _graphicsHandler.generateKitty(overlay.image!);
    }
    
    return '';
  }
  
  /// Clear all graphics overlays
  void clearGraphics() {
    _overlays.clear();
    _activeAnimations.clear();
    _dirtyOverlays.clear();
    markFullRedraw();
  }
  
  /// Get multimedia statistics
  Map<String, dynamic> getMultimediaStats() {
    return {
      'overlayCount': _overlays.length,
      'animationCount': _activeAnimations.length,
      'dirtyOverlays': _dirtyOverlays.length,
      ..._graphicsHandler.getCacheStats(),
    };
  }
  
  /// Dispose multimedia resources
  @override
  void dispose() {
    _animationTimer?.cancel();
    _graphicsHandler.dispose();
    _overlays.clear();
    _activeAnimations.clear();
    _dirtyOverlays.clear();
    
    super.dispose();
  }
}

/// Graphics overlay for terminal rendering
class GraphicsOverlay {
  final String id;
  final GraphicsOverlayType type;
  final int x;
  final int y;
  final int width;
  final int height;
  final GraphicsImage? image;
  final GraphicsAnimation? animation;
  
  GraphicsOverlay({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.image,
    this.animation,
  });
  
  factory GraphicsOverlay.empty() {
    return GraphicsOverlay(
      id: '',
      type: GraphicsOverlayType.image,
      x: 0,
      y: 0,
      width: 0,
      height: 0,
    );
  }
  
  bool get isEmpty => id.isEmpty;
}

/// Graphics overlay types
enum GraphicsOverlayType {
  image,
  animation,
}

/// Extended graphics animation with frame management
class ExtendedGraphicsAnimation extends GraphicsAnimation {
  int _currentFrameIndex = 0;
  Timer? _frameTimer;
  bool _isPlaying = true;
  
  ExtendedGraphicsAnimation({
    required super.id,
    required super.frames,
    required super.frameDuration,
    super.loop = true,
  }) {
    _startAnimation();
  }
  
  void _startAnimation() {
    _frameTimer = Timer.periodic(frameDuration, (_) {
      if (_isPlaying) {
        _nextFrame();
      }
    });
  }
  
  void _nextFrame() {
    _currentFrameIndex++;
    
    if (_currentFrameIndex >= frames.length) {
      if (loop) {
        _currentFrameIndex = 0;
      } else {
        _isPlaying = false;
        _frameTimer?.cancel();
      }
    }
  }
  
  /// Update to next frame, returns true if frame changed
  bool updateFrame() {
    if (!_isPlaying) return false;
    
    final previousFrame = _currentFrameIndex;
    _nextFrame();
    return previousFrame != _currentFrameIndex;
  }
  
  /// Get current frame
  GraphicsImage? getCurrentFrame() {
    if (_currentFrameIndex < frames.length) {
      return frames[_currentFrameIndex];
    }
    return null;
  }
  
  /// Play animation
  void play() {
    _isPlaying = true;
  }
  
  /// Pause animation
  void pause() {
    _isPlaying = false;
  }
  
  /// Stop animation and reset to first frame
  void stop() {
    _isPlaying = false;
    _currentFrameIndex = 0;
    _frameTimer?.cancel();
  }
  
  /// Dispose animation
  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }
}
