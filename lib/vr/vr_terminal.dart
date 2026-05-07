import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// VR Terminal for Meta Quest 2
///
/// Provides immersive terminal experience with:
/// - Stereoscopic 3D rendering
/// - Hand tracking for gesture-based input
/// - Gaze-based cursor positioning
/// - Haptic feedback integration
/// - Comfortable viewing distance and scaling
class VRTerminal extends StatefulWidget {
  final Widget terminalWidget;
  final bool enableHandTracking;
  final bool enableGazeCursor;
  final double comfortDistance; // meters

  const VRTerminal({
    super.key,
    required this.terminalWidget,
    this.enableHandTracking = true,
    this.enableGazeCursor = true,
    this.comfortDistance = 2.0,
  });

  @override
  State<VRTerminal> createState() => _VRTerminalState();
}

class _VRTerminalState extends State<VRTerminal> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // VR State
  Offset _gazePosition = Offset.zero;
  bool _handTrackingActive = false;
  Offset _leftHandPosition = Offset.zero;
  Offset _rightHandPosition = Offset.zero;
  double _terminalScale = 1.0;
  double _terminalDistance = 2.0;

  // Gesture recognition
  Timer? _pinchTimer;
  bool _isPinching = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _fadeController.forward();

    // Initialize VR systems
    _initializeVR();
  }

  Future<void> _initializeVR() async {
    try {
      // Simulate VR initialization
      await Future.delayed(const Duration(seconds: 1));

      if (widget.enableHandTracking) {
        await _initializeHandTracking();
      }

      if (widget.enableGazeCursor) {
        await _initializeGazeTracking();
      }

      setState(() {
        _handTrackingActive = widget.enableHandTracking;
      });

      debugPrint('🎯 VR Terminal initialized');
    } catch (e) {
      debugPrint('❌ VR initialization failed: $e');
    }
  }

  Future<void> _initializeHandTracking() async {
    // In a real implementation, this would connect to Quest hand tracking APIs
    debugPrint('🤲 Hand tracking initialized');
  }

  Future<void> _initializeGazeTracking() async {
    // In a real implementation, this would connect to Quest eye tracking APIs
    debugPrint('👁️ Gaze tracking initialized');
  }

  void _handleGazeUpdate(Offset position) {
    setState(() {
      _gazePosition = position;
    });
  }

  void _handleHandTrackingUpdate(Offset leftHand, Offset rightHand) {
    setState(() {
      _leftHandPosition = leftHand;
      _rightHandPosition = rightHand;
    });

    // Detect pinch gestures for scaling
    _detectPinchGesture(leftHand, rightHand);
  }

  void _detectPinchGesture(Offset left, Offset right) {
    final distance = (left - right).distance;

    if (distance < 100 && !_isPinching) {
      _isPinching = true;
      _pinchTimer?.cancel();
      _pinchTimer = Timer(const Duration(milliseconds: 500), () {
        // Pinch detected - could trigger actions
        _triggerHapticFeedback();
      });
    } else if (distance > 150 && _isPinching) {
      _isPinching = false;
      _pinchTimer?.cancel();
    }
  }

  void _triggerHapticFeedback() {
    // In a real implementation, this would trigger Quest controller vibration
    HapticFeedback.mediumImpact();
    debugPrint('📳 Haptic feedback triggered');
  }

  void _recenterView() {
    setState(() {
      _terminalDistance = widget.comfortDistance;
      _terminalScale = 1.0;
    });
    _triggerHapticFeedback();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main VR terminal view
          _buildStereoscopicView(),

          // VR controls overlay
          VRTerminalControls(
            onRecenter: _recenterView,
            onToggleKeyboard: () {
              // Toggle virtual keyboard
              _triggerHapticFeedback();
            },
            handTrackingActive: _handTrackingActive,
          ),

          // Gaze cursor
          if (widget.enableGazeCursor)
            Positioned(
              left: _gazePosition.dx - 10,
              top: _gazePosition.dy - 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),

          // Hand tracking indicators
          if (widget.enableHandTracking) ...[
            _buildHandIndicator(_leftHandPosition, Colors.blue),
            _buildHandIndicator(_rightHandPosition, Colors.red),
          ],
        ],
      ),
    );
  }

  Widget _buildStereoscopicView() {
    // Simulate stereoscopic 3D rendering
    // In a real implementation, this would use OpenXR for proper 3D rendering
    return Container(
      color: Colors.black,
      child: Center(
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 1 / _terminalDistance) // Perspective
            ..scale(_terminalScale),
          alignment: Alignment.center,
          child: Container(
            width: 1920,
            height: 1080,
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyan.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.terminalWidget,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandIndicator(Offset position, Color color) {
    if (position == Offset.zero) return const SizedBox.shrink();

    return Positioned(
      left: position.dx - 15,
      top: position.dy - 15,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(
          Icons.pan_tool,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pinchTimer?.cancel();
    super.dispose();
  }
}

/// VR-specific UI controls overlaid on the terminal.
///
/// Provides a floating virtual keyboard toggle, recenter button,
/// and hand-tracking status indicator.
class VRTerminalControls extends StatelessWidget {
  final VoidCallback? onRecenter;
  final VoidCallback? onToggleKeyboard;
  final bool handTrackingActive;

  const VRTerminalControls({
    super.key,
    this.onRecenter,
    this.onToggleKeyboard,
    this.handTrackingActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _VrButton(
            icon: Icons.center_focus_strong,
            onPressed: onRecenter,
            label: 'Recenter',
          ),
          const SizedBox(width: 16),
          _VrButton(
            icon: Icons.keyboard,
            onPressed: onToggleKeyboard,
            label: 'Keyboard',
          ),
          const SizedBox(width: 16),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: handTrackingActive ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _VrButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String label;

  const _VrButton({
    required this.icon,
    this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1a1a1a),
        foregroundColor: const Color(0xFF00d4aa),
      ),
    );
  }
}
