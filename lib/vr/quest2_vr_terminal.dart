import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';

/// Quest 2 VR-optimized terminal mode.
///
/// Quest 2 runs Android apps in a 2D panel inside the VR home environment.
/// This mode optimizes the terminal for readability through a VR headset:
/// - Large fonts (24-32pt) for readability at headset distance
/// - High contrast pure-black theme to reduce god rays
/// - Minimal UI chrome to maximize terminal real estate
/// - Controller-friendly hit targets and scroll
/// - Supports both touch controller and hand tracking input
class Quest2VrTerminal extends StatefulWidget {
  final TerminalSession session;
  final VoidCallback? onExitVr;

  const Quest2VrTerminal({
    super.key,
    required this.session,
    this.onExitVr,
  });

  @override
  State<Quest2VrTerminal> createState() => _Quest2VrTerminalState();
}

class _Quest2VrTerminalState extends State<Quest2VrTerminal> {
  final _focusNode = FocusNode();
  double _fontSize = 28.0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
  }

  void _handleControllerScroll(double delta) {
    // Controller joystick scroll
    widget.session.terminal.scrollUp(delta > 0 ? 3 : -3);
  }

  void _handleControllerSelect() {
    // Controller trigger - send Enter or toggle controls
    setState(() => _showControls = !_showControls);
  }

  void _handleBackButton() {
    widget.onExitVr?.call();
  }

  void _adjustFontSize(double delta) {
    setState(() {
      _fontSize = (_fontSize + delta).clamp(20.0, 48.0);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKey: _handleKeyEvent,
        child: Stack(
          children: [
            // Main terminal view - maximized for VR
            Padding(
              padding: _showControls
                  ? const EdgeInsets.only(top: 80, bottom: 120)
                  : EdgeInsets.zero,
              child: _buildVrTerminalView(),
            ),

            // Top control bar
            if (_showControls) _buildTopBar(),

            // Bottom control bar with large controller-friendly buttons
            if (_showControls) _buildBottomBar(),

            // VR mode indicator
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.vrpano, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'VR MODE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVrTerminalView() {
    return Container(
      color: Colors.black,
      child: TerminalView(
        widget.session.terminal,
        controller: widget.session.controller,
        focusNode: _focusNode,
        autofocus: true,
        theme: _vrTerminalTheme,
        textStyle: TerminalStyle(
          fontFamily: 'DroidSansMono',
          fontSize: _fontSize,
          height: 1.4,
        ),
        onKeyEvent: _handleTerminalKey,
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 80,
        color: Colors.black.withOpacity(0.9),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Exit VR button - large hit target
            _VrButton(
              icon: Icons.exit_to_app,
              label: 'Exit VR',
              onPressed: () => widget.onExitVr?.call(),
            ),
            const SizedBox(width: 16),

            // Session name
            Expanded(
              child: Text(
                widget.session.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Toggle controls visibility
            _VrButton(
              icon: _showControls ? Icons.fullscreen : Icons.fullscreen_exit,
              label: _showControls ? 'Hide' : 'Show',
              onPressed: () => setState(() => _showControls = !_showControls),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 120,
        color: Colors.black.withOpacity(0.9),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _VrButton(
              icon: Icons.text_decrease,
              label: 'Smaller',
              onPressed: () => _adjustFontSize(-2),
            ),
            _VrButton(
              icon: Icons.text_increase,
              label: 'Larger',
              onPressed: () => _adjustFontSize(2),
            ),
            _VrButton(
              icon: Icons.keyboard,
              label: 'Keyboard',
              onPressed: () {
                _focusNode.requestFocus();
                // Trigger system keyboard on Android
                if (Platform.isAndroid) {
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                }
              },
            ),
            _VrButton(
              icon: Icons.copy,
              label: 'Copy',
              onPressed: () {
                // Copy selection if any
                final text = widget.session.terminal.buffer.getText();
                Clipboard.setData(ClipboardData(text: text));
              },
            ),
            _VrButton(
              icon: Icons.paste,
              label: 'Paste',
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  widget.session.writeInput(data!.text!);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      // Map Quest 2 controller buttons
      switch (event.logicalKey) {
        case LogicalKeyboardKey.gameButtonA:
        case LogicalKeyboardKey.gameButtonB:
          setState(() => _showControls = !_showControls);
          break;
        case LogicalKeyboardKey.gameButtonX:
          _adjustFontSize(2);
          break;
        case LogicalKeyboardKey.gameButtonY:
          _adjustFontSize(-2);
          break;
        case LogicalKeyboardKey.gameButtonLeft1:
        case LogicalKeyboardKey.gameButtonRight1:
          widget.onExitVr?.call();
          break;
        default:
          break;
      }
    }
  }

  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    // Let xterm.dart handle terminal keys
    return KeyEventResult.ignored;
  }

  /// High-contrast VR terminal theme optimized for OLED headsets.
  static const _vrTerminalTheme = TerminalTheme(
    foreground: Colors.white,
    background: Colors.black,
    cursor: Colors.cyan,
    selection: Colors.blue,
    black: Color(0xFF000000),
    red: Color(0xFFFF5555),
    green: Color(0xFF55FF55),
    yellow: Color(0xFFFFFF55),
    blue: Color(0xFF5555FF),
    magenta: Color(0xFFFF55FF),
    cyan: Color(0xFF55FFFF),
    white: Color(0xFFFFFFFF),
    brightBlack: Color(0xFF555555),
    brightRed: Color(0xFFFF8888),
    brightGreen: Color(0xFF88FF88),
    brightYellow: Color(0xFFFFFF88),
    brightBlue: Color(0xFF8888FF),
    brightMagenta: Color(0xFFFF88FF),
    brightCyan: Color(0xFF88FFFF),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Colors.yellow,
    searchHitBackgroundCurrent: Colors.orange,
    searchHitForeground: Colors.black,
  );
}

/// Large controller-friendly button for VR use.
class _VrButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _VrButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 100,
          height: 90,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
