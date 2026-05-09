import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import '../ui/terminal_view.dart';
import '../config/pkm_theme.dart';

/// Platform channel interface for future native OpenXR integration.
///
/// Channel: com.termisol/vr
/// Methods (to be implemented natively):
///   - initializeVr() -> Map<String, dynamic>
///   - isVrSupported() -> bool
///   - startVrSession() -> bool
///   - stopVrSession() -> bool
///   - triggerHapticFeedback(int durationMs) -> void
///   - getBuildInfo() -> Map<String, String>  // returns {model, manufacturer}
class VrTerminalView extends StatefulWidget {
  final TerminalSession session;

  const VrTerminalView({super.key, required this.session});

  @override
  State<VrTerminalView> createState() => _VrTerminalViewState();
}

class _VrTerminalViewState extends State<VrTerminalView> {
  static const _vrChannel = MethodChannel('com.termisol/vr');

  @override
  void initState() {
    super.initState();
    // document the platform channel interface for future native openxr integration
    _vrChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'initializeVr':
        case 'isVrSupported':
        case 'startVrSession':
        case 'stopVrSession':
        case 'triggerHapticFeedback':
        case 'getBuildInfo':
          return null;
        default:
          throw MissingPluginException('not implemented: ${call.method}');
      }
    });
  }

  CellOffset _getCellOffset(Offset localPosition) {
    final size = MediaQuery.of(context).size;
    final aspectRatio = 0.8;
    final terminalWidth = size.height * aspectRatio;
    final terminalHeight = size.height;
    final left = (size.width - terminalWidth) / 2;
    final top = 0.0;

    final relX = localPosition.dx - left;
    final relY = localPosition.dy - top;

    final cols = widget.session.terminal.viewWidth;
    final rows = widget.session.terminal.viewHeight;
    final cellWidth = terminalWidth / (cols > 0 ? cols : 80);
    final cellHeight = terminalHeight / (rows > 0 ? rows : 24);

    return CellOffset(
      (relX / cellWidth).clamp(0, cols - 1).toInt(),
      (relY / cellHeight).clamp(0, rows - 1).toInt(),
    );
  }

  void _sendPointerEvent(bool down, Offset position) {
    final cell = _getCellOffset(position);
    final button = down ? TerminalMouseButton.left : TerminalMouseButton.left;
    final state = down ? TerminalMouseButtonState.down : TerminalMouseButtonState.up;
    widget.session.terminal.mouseInput(button, state, cell);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        setState(() {
          _pointerPosition = event.localPosition;
          _pointerDown = true;
        });
        _sendPointerEvent(true, event.localPosition);
      },
      onPointerMove: (event) {
        setState(() => _pointerPosition = event.localPosition);
      },
      onPointerUp: (event) {
        setState(() => _pointerDown = false);
        _sendPointerEvent(false, event.localPosition);
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: 0.8,
          child: Container(
            color: Colors.black,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'VR Terminal Mode',
                  style: TextStyle(
                    color: PkmTheme.primary,
                    fontSize: 24,
                    fontFamily: PkmTheme.fontUi,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: TermisolTerminalView(session: widget.session),
                ),
                const Text(
                  'Use Quest controllers to interact',
                  style: TextStyle(
                    color: PkmTheme.text,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
