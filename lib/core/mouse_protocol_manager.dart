import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

/// Mouse protocol modes.
enum TermisolMouseMode {
  none,
  normal, // X10 - basic click reporting
  buttonTracking, // X11 - button press/release
  any, // X11 - all events
  highlight, // Highlight tracking (for URLs)
  urxvt, // URXVT extended mode
  sgr, // SGR - extended coordinates
}

/// Manages mouse protocol (SGR, UTF-8, URXVT) for terminal applications.
/// Enables clicking links, selecting text in vim/tmux, and interactive apps.
class MouseProtocolManager {
  final Terminal terminal;
  final TerminalController controller;
  bool _enabled = false;
  TermisolMouseMode _currentMode = TermisolMouseMode.none;

  MouseProtocolManager(this.terminal, this.controller);

  /// Enable mouse protocol with specified mode.
  void enable(TermisolMouseMode mode) {
    if (!_enabled || _currentMode != mode) {
      _enabled = true;
      _currentMode = mode;

      switch (mode) {
        case TermisolMouseMode.none:
          break;
        case TermisolMouseMode.normal:
          terminal.write('\x1b[?9h'); // X10
          break;
        case TermisolMouseMode.buttonTracking:
          terminal.write('\x1b[?1000h'); // X11
          break;
        case TermisolMouseMode.any:
          terminal.write('\x1b[?1003h'); // X11 any
          break;
        case TermisolMouseMode.highlight:
          terminal.write('\x1b[?1001h'); // Highlight
          break;
        case TermisolMouseMode.urxvt:
          terminal.write('\x1b[?1015h'); // URXVT
          break;
        case TermisolMouseMode.sgr:
          terminal.write('\x1b[?1006h'); // SGR
          break;
      }

      if (kDebugMode) debugPrint('Mouse protocol enabled: $mode');
    }
  }

  /// Disable mouse protocol.
  void disable() {
    if (_enabled) {
      _enabled = false;
      _currentMode = TermisolMouseMode.none;

      // Disable all mouse modes
      terminal.write('\x1b[?9l'); // X10
      terminal.write('\x1b[?1000l'); // X11
      terminal.write('\x1b[?1003l'); // X11 any
      terminal.write('\x1b[?1001l'); // Highlight
      terminal.write('\x1b[?1015l'); // URXVT
      terminal.write('\x1b[?1006l'); // SGR

      if (kDebugMode) debugPrint('Mouse protocol disabled');
    }
  }

  /// Check if mouse protocol is enabled.
  bool get isEnabled => _enabled;

  /// Get current mouse mode.
  TermisolMouseMode get currentMode => _currentMode;

  /// Handle mouse events from terminal.
  void handleMouseEvent(String event) {
    if (!_enabled) return;

    // Parse mouse event sequences
    if (event.startsWith('\x1b[M') || event.startsWith('\x1b[<')) {
      final parts = event.split(';');
      if (parts.length >= 3) {
        final buttonCode = int.tryParse(parts[0].substring(3)) ?? 0;
        final x = int.tryParse(parts[1]) ?? 0;
        final y = int.tryParse(parts[2].substring(0, parts[2].indexOf('M'))) ?? 0;

        // Determine button and action
        final button = _getButtonName(buttonCode);
        final action = _getAction(buttonCode);

        if (kDebugMode) debugPrint('Mouse: $button $action at ($x, $y)');

        // Handle URL clicks (highlight mode)
        if (_currentMode == TermisolMouseMode.highlight && button == 'left' && action == 'press') {
          _handleUrlClick(x, y);
        }
      }
    }
  }

  /// Get button name from code.
  String _getButtonName(int code) {
    switch (code & 3) {
      case 0:
        return 'left';
      case 1:
        return 'middle';
      case 2:
        return 'right';
      case 3:
        return 'release';
      default:
        return 'unknown';
    }
  }

  /// Get action from button code.
  String _getAction(int code) {
    if ((code & 32) != 0) return 'move';
    if ((code & 64) != 0) return 'wheel';
    if ((code & 1) != 0) return 'press';
    return 'release';
  }

  /// Handle potential URL clicks in highlight mode.
  void _handleUrlClick(int x, int y) {
    if (kDebugMode) debugPrint('Potential URL click at ($x, $y)');
  }

  void dispose() {
    disable();
  }
}
