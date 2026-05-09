import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// throttles terminal rendering to maintain 60fps (16ms per frame).
/// prevents ui freezing during heavy output like `cat large.log`.
class ThrottledRenderer {
  final Terminal terminal;
  Duration _frameInterval = const Duration(milliseconds: 16);
  final List<String> _pendingOutput = [];
  Timer? _renderTimer;
  bool _isRendering = false;
  int _lastRenderTime = 0;

  ThrottledRenderer(this.terminal);

  void setTargetFps(int fps) {
    final ms = fps > 0 ? 1000 ~/ fps : 16;
    _frameInterval = Duration(milliseconds: ms);
  }

  /// Queue output for throttled rendering.
  void write(String data) {
    _pendingOutput.add(data);
    _scheduleRender();
  }

  /// Schedule a render if not already rendering.
  void _scheduleRender() {
    if (_isRendering) return;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRenderTime < _frameInterval.inMilliseconds) {
      return; // Too soon since last render
    }
    
    _renderTimer?.cancel();
    _renderTimer = Timer(_frameInterval, _render);
  }

  /// Render pending output immediately.
  void _render() {
    if (_pendingOutput.isEmpty) return;
    
    _isRendering = true;
    _lastRenderTime = DateTime.now().millisecondsSinceEpoch;
    
    try {
      // Batch all pending output
      final batch = _pendingOutput.join();
      _pendingOutput.clear();
      
      // Send to terminal in one go
      terminal.write(batch);
      
      debugPrint('🎬 Rendered ${batch.length} chars in ${DateTime.now().millisecondsSinceEpoch - _lastRenderTime}ms');
    } catch (e) {
      debugPrint('❌ Render error: $e');
    } finally {
      _isRendering = false;
    }
  }

  /// Force immediate render (bypasses throttle).
  void forceRender() {
    _renderTimer?.cancel();
    _render();
  }

  /// Clear pending output.
  void clear() {
    _pendingOutput.clear();
    _renderTimer?.cancel();
  }

  /// Get current render statistics.
  Map<String, dynamic> getStats() {
    return {
      'pendingOutputLength': _pendingOutput.length,
      'isRendering': _isRendering,
      'lastRenderTime': _lastRenderTime,
      'frameInterval': _frameInterval.inMilliseconds,
    };
  }

  void dispose() {
    _renderTimer?.cancel();
    clear();
  }
}
