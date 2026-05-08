import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import 'vr_enhancements.dart';

/// Quest 2 VR-optimized terminal mode.
///
/// Quest 2 runs Android apps in a 2D panel inside VR home environment.
/// This mode optimizes the terminal for readability through a VR headset:
/// - Large fonts (24-32pt) for readability at headset distance
/// - High contrast pure-black theme to reduce god rays
/// - Minimal UI chrome to maximize terminal real estate
/// - Controller-friendly hit targets and scroll
/// - Supports both touch controller and hand tracking input
/// - Premium 3D effects with parallax and depth shadows
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
  bool _is3DEnabled = false;
  bool _isParallaxEnabled = false;

  @override
  void initState() {
    super.initState();
    VrEnhancements.set3DEnabled(false);
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
    return VrEnhancements.animateTransition(
      duration: const Duration(milliseconds: 300),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: RawKeyboardListener(
          focusNode: _focusNode,
          onKey: _handleKeyEvent,
          child: Stack(
            children: [
              // Main terminal view with enhancements
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

              // Floating VR controls
              ...VrEnhancements.createFloatingActions(
                onToggle3D: () {
                  setState(() {
                    _is3DEnabled = !_is3DEnabled;
                    VrEnhancements.set3DEnabled(_is3DEnabled);
                  });
                },
                onToggleParallax: () {
                  setState(() {
                    _isParallaxEnabled = !_isParallaxEnabled;
                  });
                },
                is3DEnabled: _is3DEnabled,
                isParallaxEnabled: _isParallaxEnabled,
              ),

              // VR mode indicator
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vrpano, color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        _is3DEnabled ? 'VR 3D' : 'VR MODE',
                        style: const TextStyle(
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
      ),
    );
  }

  Widget _buildVrTerminalView() {
    final terminal = TerminalView(
      widget.session.terminal,
      controller: widget.session.controller,
      focusNode: _focusNode,
      autofocus: true,
      theme: _is3DEnabled ? VrEnhancements.vrEnhancedTheme : _vrTerminalTheme,
      textStyle: TerminalStyle(
        fontFamily: 'DroidSansMono',
        fontSize: _fontSize,
        height: 1.4,
      ),
      onKeyEvent: _handleTerminalKey,
      padding: const EdgeInsets.all(16),
    );

    return VrEnhancements.enhanceTerminal(
      child: terminal,
      vrMode: true,
      fontSize: _fontSize,
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 80,
        color: Colors.black.withValues(alpha: 0.9),
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
            const SizedBox(width: 16),
            // 3D toggle
            _VrButton(
              icon: Icons.view_in_ar,
              label: '3D',
              onPressed: () => setState(() {
                _is3DEnabled = !_is3DEnabled;
                VrEnhancements.set3DEnabled(_is3DEnabled);
              }),
            ),
            const SizedBox(width: 16),
            // Parallax toggle
            _VrButton(
              icon: Icons.panorama_horizontal,
              label: 'Parallax',
              onPressed: () => setState(() {
                _isParallaxEnabled = !_isParallaxEnabled;
              }),
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
        color: Colors.black.withValues(alpha: 0.9),
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
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
