import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' show CellOffset, TerminalMouseButton, TerminalMouseButtonState;

import '../core/terminal_session.dart';
import 'openxr_session.dart';
import 'vr_frame_encoder.dart';

/// Fully-featured VR terminal view for Oculus Quest 2.
///
/// When the widget is initialized it attempts to start a native OpenXR
/// session. If VR is unavailable it falls back to a standard on-screen
/// message. While VR is active the visible terminal buffer is streamed to
/// the native renderer at 30 fps and controller input events are translated
/// into terminal mouse actions.
class VrTerminalView extends StatefulWidget {
  final TerminalSession session;

  const VrTerminalView({super.key, required this.session});

  @override
  State<VrTerminalView> createState() => _VrTerminalViewState();
}

class _VrTerminalViewState extends State<VrTerminalView> {
  final _encoder = VrFrameEncoder();
  Timer? _frameTimer;
  bool _vrActive = false;
  String _status = 'Checking VR support...';

  @override
  void initState() {
    super.initState();
    _initializeVr();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    if (_vrActive) {
      unawaited(OpenXrSession.stopSession());
    }
    super.dispose();
  }

  Future<void> _initializeVr() async {
    final supported = await OpenXrSession.isSupported();
    if (!supported) {
      if (mounted) {
        setState(() => _status = 'VR not available on this device');
      }
      return;
    }

    try {
      final initialized = await OpenXrSession.initialize();
      if (!initialized) {
        if (mounted) {
          setState(() => _status = 'Failed to initialize VR runtime');
        }
        return;
      }

      // Subscribe to controller input events from the native runtime.
      OpenXrSession.inputEvents.listen(_onVrInput, onError: (Object e) {
        debugPrint('VR input stream error: $e');
      });

      final started = await OpenXrSession.startSession();
      if (!started) {
        if (mounted) {
          setState(() => _status = 'Failed to start VR session');
        }
        return;
      }

      if (mounted) {
        setState(() {
          _vrActive = true;
          _status = 'VR Session Active';
        });
      }

      // Stream terminal frames at ~30 fps.
      _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!mounted) return;
        _submitFrame();
      });
    } on OpenXrException catch (e) {
      if (mounted) {
        setState(() => _status = 'VR error: $e');
      }
    }
  }

  void _submitFrame() {
    final terminal = widget.session.terminal;
    final frame = _encoder.encode(terminal);
    unawaited(
      OpenXrSession.submitFrame(VrTerminalFrame(
        rows: terminal.viewHeight,
        cols: terminal.viewWidth,
        cells: frame,
      )),
    );
  }

  void _onVrInput(VrInputEvent event) {
    final terminal = widget.session.terminal;
    final cols = terminal.viewWidth;
    final rows = terminal.viewHeight;
    if (cols <= 0 || rows <= 0) return;

    // Map normalized controller coordinates (0..1) to cell grid.
    final cellX = (event.x * cols).clamp(0, cols - 1).toInt();
    final cellY = (event.y * rows).clamp(0, rows - 1).toInt();

    switch (event.type) {
      case VrInputType.trigger:
        final button = TerminalMouseButton.left;
        final state = event.button == 1
            ? TerminalMouseButtonState.down
            : TerminalMouseButtonState.up;
        terminal.mouseInput(button, state, CellOffset(cellX, cellY));
      case VrInputType.thumbstick:
        // TODO: implement scroll / arrow-key mapping for thumbstick.
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Text(
          _status,
          style: const TextStyle(color: Colors.green, fontSize: 24),
        ),
      ),
    );
  }
}

/// Silences unawaited-future lints without losing the fire-and-forget intent.
void unawaited(Future<void> future) {}
