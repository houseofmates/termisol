import 'dart:async';
import 'package:flutter/material.dart';
import '../core/service_registry.dart';
import '../core/vr_platform_channel.dart';
import '../config/pkm_theme.dart';

class VrTerminal extends StatefulWidget {
  final Widget terminalWidget;
  final ServiceRegistry registry;

  const VrTerminal({
    super.key,
    required this.terminalWidget,
    required this.registry,
  });

  @override
  State<VrTerminal> createState() => _VrTerminalState();
}

class _VrTerminalState extends State<VrTerminal> with TickerProviderStateMixin {
  VrDeviceInfo? _deviceInfo;
  StreamSubscription<VrDeviceInfo>? _deviceSubscription;
  StreamSubscription<HandTrackingData>? _handSubscription;
  StreamSubscription<EyeTrackingData>? _eyeSubscription;

  Offset _gazePosition = Offset.zero;
  HandTrackingData? _handData;
  // ignore: unused_field
  EyeTrackingData? _eyeData;

  double _terminalScale = 1.0;
  double _terminalDistance = 2.0;
  Offset _terminalPosition = Offset.zero;
  bool _vrActive = false;
  bool _handTrackingActive = false;
  bool _eyeTrackingActive = false;
  String _statusMessage = 'Initializing VR...';

  late AnimationController _fadeController;
  Timer? _gestureTimer;
  HandGesture _currentGesture = HandGesture.unknown;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _initializeVr();
  }

  Future<void> _initializeVr() async {
    final vrEnabled = widget.registry.isEnabled(TermisolFeatures.vrSupport);
    if (!vrEnabled) {
      setState(() => _statusMessage = 'VR support disabled');
      return;
    }

    try {
      final supported = await VrPlatformChannel.isVrSupported();
      if (!supported) {
        setState(() => _statusMessage = 'VR not supported on this device');
        return;
      }

      final initResult = await VrPlatformChannel.initialize();
      if (!initResult.success) {
        setState(() => _statusMessage = 'VR initialization failed: ${initResult.error}');
        return;
      }

      _deviceInfo = initResult.deviceInfo;

      final sessionStarted = await VrPlatformChannel.startVrSession();
      if (!sessionStarted) {
        setState(() => _statusMessage = 'Failed to start VR session');
        return;
      }

      _setupTrackingStreams();

      setState(() {
        _vrActive = true;
        _statusMessage = 'VR Active';
        _handTrackingActive = _deviceInfo?.supportsHandTracking ?? false;
        _eyeTrackingActive = _deviceInfo?.supportsEyeTracking ?? false;
      });

      unawaited(_fadeController.forward());
    } catch (e) {
      setState(() => _statusMessage = 'VR initialization error: $e');
    }
  }

  void _setupTrackingStreams() {
    _deviceSubscription = VrPlatformChannel.deviceDetectionStream.listen(
      (deviceInfo) => setState(() => _deviceInfo = deviceInfo),
      onError: (error) => debugPrint('Device detection error: $error'),
    );

    if (_deviceInfo?.supportsHandTracking ?? false) {
      _handSubscription = VrPlatformChannel.handTrackingStream.listen(
        (handData) {
          setState(() => _handData = handData);
          _processHandTracking(handData);
        },
        onError: (error) => debugPrint('Hand tracking error: $error'),
      );
    }

    if (_deviceInfo?.supportsEyeTracking ?? false) {
      _eyeSubscription = VrPlatformChannel.eyeTrackingStream.listen(
        (eyeData) {
          setState(() {
            _eyeData = eyeData;
            _gazePosition = eyeData.gazePosition;
          });
          _processEyeTracking(eyeData);
        },
        onError: (error) => debugPrint('Eye tracking error: $error'),
      );
    }
  }

  void _processHandTracking(HandTrackingData handData) {
    final newGesture = _analyzeGestures(handData.leftHand, handData.rightHand);
    if (newGesture != _currentGesture) {
      _currentGesture = newGesture;
      _onGestureDetected(newGesture);
    }
    _handleHandInteractions(handData.leftHand, handData.rightHand);
  }

  void _processEyeTracking(EyeTrackingData eyeData) {
    if (eyeData.leftEyeBlink || eyeData.rightEyeBlink) {
      _handleBlinkGesture();
    }
    if (eyeData.pupilDilation > 0.8) {
      _adjustTerminalDistance(-0.1);
    } else if (eyeData.pupilDilation < 0.3) {
      _adjustTerminalDistance(0.1);
    }
  }

  HandGesture _analyzeGestures(HandData left, HandData right) {
    if (left.gesture == HandGesture.pinch || right.gesture == HandGesture.pinch) {
      return HandGesture.pinch;
    }
    if (left.gesture == HandGesture.point || right.gesture == HandGesture.point) {
      return HandGesture.point;
    }
    if (left.gesture == HandGesture.fist || right.gesture == HandGesture.fist) {
      return HandGesture.fist;
    }
    if (left.gesture == HandGesture.open || right.gesture == HandGesture.open) {
      return HandGesture.open;
    }
    return HandGesture.unknown;
  }

  void _onGestureDetected(HandGesture gesture) {
    switch (gesture) {
      case HandGesture.pinch:
        setState(() => _terminalScale = (_terminalScale * 1.1).clamp(0.5, 3.0));
      case HandGesture.point:
        if (_handData != null) {
          final pointingHand = _handData!.leftHand.gesture == HandGesture.point
              ? _handData!.leftHand
              : _handData!.rightHand;
          setState(() => _gazePosition = pointingHand.position);
        }
      case HandGesture.fist:
        _triggerHapticFeedback(HapticPattern(name: 'grab', pattern: [0, 80, 40, 80], amplitude: 0.8));
      case HandGesture.open:
        _showVrMenu();
      case HandGesture.unknown:
        break;
      default:
        break;
    }
    _triggerHapticFeedback(HapticPattern(name: 'gesture', pattern: [0, 50, 25, 50], amplitude: 0.6));
  }

  void _handleHandInteractions(HandData leftHand, HandData rightHand) {}

  void _handleBlinkGesture() {}

  void _adjustTerminalDistance(double delta) {
    setState(() => _terminalDistance = (_terminalDistance + delta).clamp(1.0, 5.0));
  }

  void _showVrMenu() {}

  void _triggerHapticFeedback(HapticPattern pattern) {
    VrPlatformChannel.triggerHapticFeedback(pattern);
  }

  void _recenterView() {
    setState(() {
      _terminalDistance = 2.0;
      _terminalScale = 1.0;
      _terminalPosition = Offset.zero;
    });
    _triggerHapticFeedback(HapticPattern(name: 'recenter', pattern: [0, 100, 50, 100], amplitude: 0.7));
  }

  @override
  Widget build(BuildContext context) {
    if (!_vrActive) return _build2dFallback();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildStereoscopicView(),
          _buildVrControls(),
          if (_eyeTrackingActive)
            Positioned(
              left: _gazePosition.dx - 10,
              top: _gazePosition.dy - 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          if (_handTrackingActive && _handData != null) ...[
            _buildHandIndicator(_handData!.leftHand, Colors.blue),
            _buildHandIndicator(_handData!.rightHand, Colors.red),
          ],
          _buildStatusIndicator(),
        ],
      ),
    );
  }

  Widget _build2dFallback() {
    return Scaffold(
      backgroundColor: PkmTheme.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: PkmTheme.terminalBg,
            child: const Text(
              'Terminal - 2D Mode',
              style: TextStyle(color: PkmTheme.primary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_statusMessage, style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    widget.terminalWidget,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStereoscopicView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 1 / _terminalDistance)
// ignore: deprecated_member_use
            ..scale(_terminalScale, _terminalScale, _terminalScale)
            ..setEntry(0, 3, _terminalPosition.dx)
            ..setEntry(1, 3, _terminalPosition.dy),
          alignment: Alignment.center,
          child: Container(
            width: 1920,
            height: 1080,
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a1a),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.cyan.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)],
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(8), child: widget.terminalWidget),
          ),
        ),
      ),
    );
  }

  Widget _buildVrControls() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _VrButton(icon: Icons.center_focus_strong, onPressed: _recenterView, label: 'Recenter'),
          const SizedBox(width: 16),
          _VrButton(icon: Icons.menu, onPressed: _showVrMenu, label: 'Menu'),
          const SizedBox(width: 16),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _handTrackingActive ? Colors.green : Colors.red, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Widget _buildHandIndicator(HandData hand, Color color) {
    if (!hand.isTracked) return const SizedBox.shrink();
    return Positioned(
      left: hand.position.dx - 15,
      top: hand.position.dy - 15,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(_getGestureIcon(hand.gesture), color: Colors.white, size: 16),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(_statusMessage, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  IconData _getGestureIcon(HandGesture gesture) {
    switch (gesture) {
      case HandGesture.pinch:
        return Icons.touch_app;
      case HandGesture.point:
        return Icons.touch_app;
      case HandGesture.fist:
        return Icons.front_hand;
      case HandGesture.open:
        return Icons.pan_tool;
      case HandGesture.unknown:
        return Icons.pan_tool;
      default:
        return Icons.pan_tool;
    }
  }

  @override
  void dispose() {
    _deviceSubscription?.cancel();
    _handSubscription?.cancel();
    _eyeSubscription?.cancel();
    _gestureTimer?.cancel();
    _fadeController.dispose();
    VrPlatformChannel.stopVrSession();
    super.dispose();
  }
}

class _VrButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String label;

  const _VrButton({required this.icon, this.onPressed, required this.label});

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

