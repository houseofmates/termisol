import 'dart:math';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';

/// VR-specific terminal enhancements for premium feel.
///
/// Even though Quest 2 displays apps in a 2D panel, we can add
/// depth, parallax, and spatial UI elements to make it feel premium.
class VrEnhancements {
  static double _parallaxOffset = 0.0;
  static bool _is3DEnabled = false;

  /// Enable/disable 3D visual effects (parallax, depth).
  static void set3DEnabled(bool enabled) {
    _is3DEnabled = enabled;
  }

  /// Update parallax effect based on head movement.
  static void updateParallax(double deltaX, double deltaY) {
    if (!_is3DEnabled) return;
    _parallaxOffset = (_parallaxOffset + deltaX * 0.01).clamp(-20.0, 20.0);
  }

  /// Wrap terminal view with VR enhancement layer.
  static Widget enhanceTerminal({
    required Widget child,
    required bool vrMode,
    double fontSize = 28.0,
  }) {
    if (!vrMode) return child;

    return Stack(
      children: [
        // Background depth layer
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 800,
                colors: [
                  Colors.black,
                  Colors.black.withValues(alpha: 0.95),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
        ),
        // Subtle parallax layer
        if (_is3DEnabled)
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(_parallaxOffset * 0.1, _parallaxOffset * 0.05),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.transparent,
                      Colors.cyan.withValues(alpha: 0.02),
                      Colors.blue.withValues(alpha: 0.01),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Terminal with depth shadow
        Positioned.fill(
          child: Container(
            margin: EdgeInsets.all(_is3DEnabled ? 8.0 : 0.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_is3DEnabled ? 12.0 : 0.0),
              boxShadow: _is3DEnabled
                  ? [
                      BoxShadow(
                        color: Colors.cyan.withValues(alpha: 0.3),
                        blurRadius: 20.0,
                        spreadRadius: 2.0,
                      ),
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.2),
                        blurRadius: 40.0,
                        spreadRadius: 4.0,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_is3DEnabled ? 12.0 : 0.0),
              child: child,
            ),
          ),
        ),
        // Floating VR indicators
        if (_is3DEnabled) ...[
          // Top-left corner depth indicator
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [Colors.cyan, Colors.blue],
                ),
              ),
            ),
          ),
          // Bottom-right corner status
          Positioned(
            bottom: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.cyan.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vrpano, color: Colors.cyan, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'VR ENHANCED',
                    style: TextStyle(
                      color: Colors.cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Premium VR terminal theme with subtle depth effects.
  static const vrEnhancedTheme = TerminalTheme(
    foreground: Color(0xFFE0E0E0),
    background: Colors.black,
    cursor: Color(0xFF00FFFF),
    selection: Color(0xFF0088CC),
    black: Color(0xFF000000),
    red: Color(0xFFFF6B6B),
    green: Color(0xFF4EC9B0),
    yellow: Color(0xFFFFD93D),
    blue: Color(0xFF4A90E2),
    magenta: Color(0xFFBD93F9),
    cyan: Color(0xFF39C5BB),
    white: Color(0xFFFFFFFF),
    brightBlack: Color(0xFF6C757D),
    brightRed: Color(0xFFFF7B72),
    brightGreen: Color(0xFF23D863),
    brightYellow: Color(0xFFFFD43B),
    brightBlue: Color(0xFF58A6FF),
    brightMagenta: Color(0xFFBC8CFF),
    brightCyan: Color(0xFF36CFCF),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF3D),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Colors.black,
  );

  /// Animate terminal transitions with VR-friendly easing.
  static Widget animateTransition({
    required Widget child,
    required Duration duration,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      builder: (context, value, child) {
        // Use easeOutCubic for smooth VR transitions
        final curve = Curves.easeOutCubic;
        final curvedValue = curve.transform(value);
        
        return Transform.scale(
          scale: 0.95 + (0.05 * curvedValue), // Subtle scale animation
          child: Opacity(
            opacity: curvedValue,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  /// Create floating action buttons with depth.
  static List<Widget> createFloatingActions({
    required VoidCallback onToggle3D,
    required VoidCallback onToggleParallax,
    bool is3DEnabled = false,
    bool isParallaxEnabled = false,
  }) {
    return [
      // 3D toggle
      Positioned(
        top: 80,
        right: 20,
        child: FloatingActionButton.small(
          onPressed: onToggle3D,
          backgroundColor: is3DEnabled ? Colors.cyan : Colors.grey.shade700,
          child: Icon(
            Icons.view_in_ar,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
      // Parallax toggle
      Positioned(
        top: 140,
        right: 20,
        child: FloatingActionButton.small(
          onPressed: onToggleParallax,
          backgroundColor: isParallaxEnabled ? Colors.blue : Colors.grey.shade700,
          child: Icon(
            Icons.panorama_horizontal,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    ];
  }
}
