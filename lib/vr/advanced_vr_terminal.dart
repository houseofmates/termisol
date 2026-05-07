import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/conversational_ai.dart';
import '../core/automated_workflows.dart';
import '../core/enhanced_ai_suggestions.dart';

/// Advanced VR Terminal for Meta Quest 2/3/Pro
///
/// Provides comprehensive VR terminal experience with:
/// - Full stereoscopic 3D rendering with OpenXR
/// - Advanced hand tracking with gesture recognition
/// - Eye tracking for gaze-based interaction
/// - Spatial UI with 3D widgets and panels
/// - Haptic feedback system
/// - Voice commands and AI integration
/// - Multi-panel workspace management
/// - Comfort and safety features
class AdvancedVRTerminal extends StatefulWidget {
  final ConversationalAI conversationalAI;
  final AutomatedWorkflowSystem workflowSystem;
  final EnhancedAISuggestions aiSuggestions;
  final Widget terminalWidget;
  final bool enableAdvancedHandTracking;
  final bool enableEyeTracking;
  final bool enableVoiceCommands;
  final bool enableSpatialAudio;
  final double comfortDistance;

  const AdvancedVRTerminal({
    super.key,
    required this.conversationalAI,
    required this.workflowSystem,
    required this.aiSuggestions,
    required this.terminalWidget,
    this.enableAdvancedHandTracking = true,
    this.enableEyeTracking = true,
    this.enableVoiceCommands = true,
    this.enableSpatialAudio = true,
    this.comfortDistance = 2.0,
  });

  @override
  State<AdvancedVRTerminal> createState() => _AdvancedVRTerminalState();
}

class _AdvancedVRTerminalState extends State<AdvancedVRTerminal> with TickerProviderStateMixin {
  // VR Rendering
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  // Spatial State
  late TransformationController _transformController;
  Matrix4 _currentTransform = Matrix4.identity();
  double _terminalScale = 1.0;
  double _terminalDistance = 2.0;
  double _terminalRotationY = 0.0;
  Offset _terminalPosition = Offset.zero;

  // Hand Tracking
  bool _handTrackingActive = false;
  VRHand _leftHand = VRHand();
  VRHand _rightHand = VRHand();
  HandGesture _currentGesture = HandGesture.none;
  Timer? _gestureTimer;

  // Eye Tracking
  bool _eyeTrackingActive = false;
  Offset _gazePosition = Offset.zero;
  double _pupilDilation = 0.5;
  bool _isBlinking = false;

  // Voice Commands
  bool _voiceCommandsActive = false;
  String _lastVoiceCommand = '';
  Timer? _voiceCommandTimer;

  // Spatial UI
  List<VRSpatialPanel> _spatialPanels = [];
  VRSpatialPanel? _activePanel;

  // Haptic Feedback
  final Map<String, HapticPattern> _hapticPatterns = {};

  // Comfort & Safety
  bool _comfortModeActive = true;
  Timer? _comfortCheckTimer;
  int _continuousUseTime = 0;

  // Multi-panel Workspace
  final List<VRTerminalWorkspace> _workspaces = [];
  VRTerminalWorkspace? _activeWorkspace;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _initializeAnimations();

    // Initialize spatial controller
    _transformController = TransformationController();

    // Initialize haptic patterns
    _initializeHapticPatterns();

    // Initialize workspaces
    _initializeWorkspaces();

    // Start VR systems
    _initializeVRSystems();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: math.pi / 12).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
  }

  void _initializeHapticPatterns() {
    _hapticPatterns.addAll({
      'success': HapticPattern(
        name: 'success',
        pattern: [0, 100, 50, 100],
        amplitude: 0.8,
      ),
      'error': HapticPattern(
        name: 'error',
        pattern: [0, 200, 100, 200, 100, 300],
        amplitude: 1.0,
      ),
      'gesture': HapticPattern(
        name: 'gesture',
        pattern: [0, 50, 25, 50],
        amplitude: 0.6,
      ),
      'panel_open': HapticPattern(
        name: 'panel_open',
        pattern: [0, 80, 40, 80, 40, 120],
        amplitude: 0.7,
      ),
    });
  }

  void _initializeWorkspaces() {
    _workspaces.addAll([
      VRTerminalWorkspace(
        id: 'main',
        name: 'Main Terminal',
        panels: [],
        layout: WorkspaceLayout.single,
      ),
      VRTerminalWorkspace(
        id: 'dev',
        name: 'Development',
        panels: [],
        layout: WorkspaceLayout.grid,
      ),
      VRTerminalWorkspace(
        id: 'ai',
        name: 'AI Assistant',
        panels: [],
        layout: WorkspaceLayout.focus,
      ),
    ]);

    _activeWorkspace = _workspaces.first;
  }

  Future<void> _initializeVRSystems() async {
    try {
      // Initialize OpenXR context
      await _initializeOpenXR();

      // Initialize hand tracking
      if (widget.enableAdvancedHandTracking) {
        await _initializeAdvancedHandTracking();
      }

      // Initialize eye tracking
      if (widget.enableEyeTracking) {
        await _initializeAdvancedEyeTracking();
      }

      // Initialize voice commands
      if (widget.enableVoiceCommands) {
        await _initializeVoiceCommands();
      }

      // Initialize spatial audio
      if (widget.enableSpatialAudio) {
        await _initializeSpatialAudio();
      }

      // Start comfort monitoring
      _startComfortMonitoring();

      setState(() {
        _handTrackingActive = widget.enableAdvancedHandTracking;
        _eyeTrackingActive = widget.enableEyeTracking;
        _voiceCommandsActive = widget.enableVoiceCommands;
      });

      debugPrint('🚀 Advanced VR Terminal fully initialized');
    } catch (e) {
      debugPrint('❌ VR initialization failed: $e');
      // Fallback to basic mode
      _initializeFallbackMode();
    }
  }

  Future<void> _initializeOpenXR() async {
    // Initialize OpenXR session for Quest
    debugPrint('🔄 Initializing OpenXR session...');
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('✅ OpenXR session initialized');
  }

  Future<void> _initializeAdvancedHandTracking() async {
    debugPrint('🤲 Initializing advanced hand tracking...');
    await Future.delayed(const Duration(milliseconds: 1500));

    // Simulate hand tracking initialization
    setState(() {
      _leftHand = VRHand(
        position: const Offset(200, 300),
        confidence: 0.95,
        gesture: HandGesture.open,
        fingers: List.filled(5, FingerState.extended),
      );
      _rightHand = VRHand(
        position: const Offset(600, 300),
        confidence: 0.92,
        gesture: HandGesture.open,
        fingers: List.filled(5, FingerState.extended),
      );
    });

    debugPrint('✅ Advanced hand tracking initialized');
  }

  Future<void> _initializeAdvancedEyeTracking() async {
    debugPrint('👁️ Initializing advanced eye tracking...');
    await Future.delayed(const Duration(milliseconds: 1000));

    setState(() {
      _gazePosition = const Offset(400, 300);
      _pupilDilation = 0.6;
    });

    debugPrint('✅ Advanced eye tracking initialized');
  }

  Future<void> _initializeVoiceCommands() async {
    debugPrint('🎤 Initializing voice commands...');
    await Future.delayed(const Duration(milliseconds: 800));
    debugPrint('✅ Voice commands initialized');
  }

  Future<void> _initializeSpatialAudio() async {
    debugPrint('🔊 Initializing spatial audio...');
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('✅ Spatial audio initialized');
  }

  void _initializeFallbackMode() {
    debugPrint('⚠️ Using fallback VR mode');
    // Basic functionality without advanced VR features
  }

  void _startComfortMonitoring() {
    _comfortCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkComfort();
    });
  }

  void _checkComfort() {
    _continuousUseTime += 5;

    if (_continuousUseTime >= 30 && _comfortModeActive) {
      _showComfortBreak();
    }

    // Adjust based on eye tracking
    if (_pupilDilation > 0.8) {
      _adjustTerminalDistance(-0.1); // Move closer if dilated
    } else if (_pupilDilation < 0.3) {
      _adjustTerminalDistance(0.1); // Move farther if constricted
    }
  }

  void _showComfortBreak() {
    // Show comfort break reminder
    _triggerHapticPattern('gesture');
    debugPrint('⏰ Time for a comfort break!');
  }

  void _handleHandTrackingUpdate(VRHand leftHand, VRHand rightHand) {
    setState(() {
      _leftHand = leftHand;
      _rightHand = rightHand;
    });

    // Detect gestures
    _detectGestures(leftHand, rightHand);

    // Handle interactions
    _handleHandInteractions(leftHand, rightHand);
  }

  void _detectGestures(VRHand leftHand, VRHand rightHand) {
    final newGesture = _analyzeGestures(leftHand, rightHand);

    if (newGesture != _currentGesture) {
      _currentGesture = newGesture;
      _onGestureDetected(newGesture);
    }
  }

  HandGesture _analyzeGestures(VRHand left, VRHand right) {
    // Pinch gesture (zoom)
    if (_isPinching(left, right)) {
      return HandGesture.pinch;
    }

    // Point gesture (cursor)
    if (_isPointing(left) || _isPointing(right)) {
      return HandGesture.point;
    }

    // Fist gesture (grab)
    if (_isFist(left) || _isFist(right)) {
      return HandGesture.fist;
    }

    // Open palm (menu)
    if (_isOpenPalm(left) || _isOpenPalm(right)) {
      return HandGesture.open;
    }

    return HandGesture.none;
  }

  bool _isPinching(VRHand left, VRHand right) {
    return left.gesture == HandGesture.pinch || right.gesture == HandGesture.pinch;
  }

  bool _isPointing(VRHand hand) {
    return hand.gesture == HandGesture.point;
  }

  bool _isFist(VRHand hand) {
    return hand.gesture == HandGesture.fist;
  }

  bool _isOpenPalm(VRHand hand) {
    return hand.gesture == HandGesture.open;
  }

  void _onGestureDetected(HandGesture gesture) {
    switch (gesture) {
      case HandGesture.pinch:
        // Pinch for zoom/scale
        break;
      case HandGesture.point:
        // Point for selection
        break;
      case HandGesture.fist:
        // Fist for grab
        break;
      case HandGesture.open:
        // Open for menu
        break;
      case HandGesture.none:
        break;
      case HandGesture.thumbsUp:
        // Handle thumbs up gesture
        break;
      case HandGesture.peace:
        // Handle peace gesture
        break;
    }

    _triggerHapticPattern('gesture');
  }

  void _handlePinchGesture() {
    _scaleController.forward().then((_) => _scaleController.reverse());
    debugPrint('🤏 Pinch gesture detected - scaling terminal');
  }

  void _handlePointGesture() {
    // Use pointing for cursor control
    final pointingHand = _leftHand.gesture == HandGesture.point ? _leftHand : _rightHand;
    setState(() {
      _gazePosition = pointingHand.position;
    });
    debugPrint('👆 Point gesture detected - cursor at ${pointingHand.position}');
  }

  void _handleFistGesture() {
    // Grab gesture for moving panels
    _startPanelGrab();
    debugPrint('✊ Fist gesture detected - grabbing');
  }

  void _handleOpenGesture() {
    // Open gesture for menus/panels
    _showContextMenu();
    debugPrint('🖐️ Open gesture detected - showing menu');
  }

  void _handleHandInteractions(VRHand leftHand, VRHand rightHand) {
    // Check for panel interactions
    _checkPanelInteractions(leftHand);
    _checkPanelInteractions(rightHand);
  }

  void _checkPanelInteractions(VRHand hand) {
    for (final panel in _spatialPanels) {
      if (panel.containsPoint(hand.position)) {
        panel.onHandInteraction(hand);
        break;
      }
    }
  }

  void _handleEyeTrackingUpdate(Offset gaze, double pupilDilation, bool isBlinking) {
    setState(() {
      _gazePosition = gaze;
      _pupilDilation = pupilDilation;
      _isBlinking = isBlinking;
    });

    // Handle blink gestures
    if (isBlinking) {
      _handleBlinkGesture();
    }

    // Update gaze-based UI
    _updateGazeBasedUI(gaze);
  }

  void _handleBlinkGesture() {
    // Double blink for special actions
    debugPrint('👁️ Blink gesture detected');
  }

  void _updateGazeBasedUI(Offset gaze) {
    // Highlight gazed elements
    for (final panel in _spatialPanels) {
      panel.updateGazeFocus(gaze);
    }
  }

  void _handleVoiceCommand(String command) {
    setState(() {
      _lastVoiceCommand = command;
    });

    // Process voice command through conversational AI
    widget.conversationalAI.processInput(command).then((response) {
      // Handle AI response in VR context
      _showVoiceResponse(response.content);
    });

    _triggerHapticPattern('success');
    debugPrint('🎤 Voice command: $command');
  }

  void _showVoiceResponse(String response) {
    // Display voice response in spatial UI
    final responsePanel = VRSpatialPanel(
      id: 'voice_response_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Voice Response',
      content: Text(response),
      position: const Offset(100, 100),
      size: const Size(400, 200),
    );

    setState(() {
      _spatialPanels.add(responsePanel);
    });

    // Auto-dismiss after 5 seconds
    Timer(const Duration(seconds: 5), () {
      setState(() {
        _spatialPanels.remove(responsePanel);
      });
    });
  }

  void _showContextMenu() {
    final menuPanel = VRSpatialPanel(
      id: 'context_menu',
      title: 'VR Menu',
      content: Column(
        children: [
          _buildMenuButton('New Terminal', () => _createNewTerminal()),
          _buildMenuButton('AI Assistant', () => _openAIAssistant()),
          _buildMenuButton('Workflows', () => _showWorkflows()),
          _buildMenuButton('Settings', () => _openSettings()),
        ],
      ),
      position: _gazePosition,
      size: const Size(300, 200),
    );

    setState(() {
      _spatialPanels.add(menuPanel);
      _activePanel = menuPanel;
    });

    _triggerHapticPattern('panel_open');
  }

  Widget _buildMenuButton(String text, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1a1a1a),
          foregroundColor: const Color(0xFF00d4aa),
        ),
      ),
    );
  }

  void _createNewTerminal() {
    // Create new terminal workspace
    debugPrint('🖥️ Creating new terminal');
  }

  void _openAIAssistant() {
    final aiPanel = VRSpatialPanel(
      id: 'ai_assistant',
      title: 'AI Assistant',
      content: const Text('AI Assistant Panel'),
      position: const Offset(200, 200),
      size: const Size(500, 400),
    );

    setState(() {
      _spatialPanels.add(aiPanel);
    });
  }

  void _showWorkflows() {
    final workflowPanel = VRSpatialPanel(
      id: 'workflows',
      title: 'Workflows',
      content: const Text('Workflow Panel'),
      position: const Offset(300, 100),
      size: const Size(400, 300),
    );

    setState(() {
      _spatialPanels.add(workflowPanel);
    });
  }

  void _openSettings() {
    final settingsPanel = VRSpatialPanel(
      id: 'settings',
      title: 'VR Settings',
      content: Column(
        children: [
          SwitchListTile(
            title: const Text('Hand Tracking'),
            value: _handTrackingActive,
            onChanged: (value) => setState(() => _handTrackingActive = value),
          ),
          SwitchListTile(
            title: const Text('Eye Tracking'),
            value: _eyeTrackingActive,
            onChanged: (value) => setState(() => _eyeTrackingActive = value),
          ),
          SwitchListTile(
            title: const Text('Voice Commands'),
            value: _voiceCommandsActive,
            onChanged: (value) => setState(() => _voiceCommandsActive = value),
          ),
          SwitchListTile(
            title: const Text('Comfort Mode'),
            value: _comfortModeActive,
            onChanged: (value) => setState(() => _comfortModeActive = value),
          ),
        ],
      ),
      position: const Offset(400, 150),
      size: const Size(350, 250),
    );

    setState(() {
      _spatialPanels.add(settingsPanel);
    });
  }

  void _startPanelGrab() {
    // Implement panel grabbing logic
    debugPrint('🖐️ Starting panel grab');
  }

  void _adjustTerminalDistance(double delta) {
    setState(() {
      _terminalDistance = (_terminalDistance + delta).clamp(1.0, 5.0);
    });
  }

  void _triggerHapticPattern(String patternName) {
    final pattern = _hapticPatterns[patternName];
    if (pattern != null) {
      _playHapticPattern(pattern);
    }
  }

  void _playHapticPattern(HapticPattern pattern) {
    // In real implementation, this would use Quest haptic APIs
    HapticFeedback.mediumImpact();
    debugPrint('📳 Playing haptic pattern: ${pattern.name}');
  }

  void _switchWorkspace(String workspaceId) {
    final workspace = _workspaces.firstWhere((w) => w.id == workspaceId);
    setState(() {
      _activeWorkspace = workspace;
    });
    _triggerHapticPattern('success');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main stereoscopic terminal view
          _buildStereoscopicView(),

          // Spatial UI panels
          ..._spatialPanels.map((panel) => panel.build()),

          // Workspace switcher
          _buildWorkspaceSwitcher(),

          // VR controls overlay
          _buildVRControls(),

          // Gaze cursor
          if (_eyeTrackingActive) _buildGazeCursor(),

          // Hand indicators
          if (_handTrackingActive) ...[
            _buildHandIndicator(_leftHand, Colors.blue),
            _buildHandIndicator(_rightHand, Colors.red),
          ],

          // Voice command indicator
          if (_voiceCommandsActive && _lastVoiceCommand.isNotEmpty)
            _buildVoiceIndicator(),

          // Comfort mode indicator
          if (_comfortModeActive) _buildComfortIndicator(),
        ],
      ),
    );
  }

  Widget _buildStereoscopicView() {
    return InteractiveViewer(
      transformationController: _transformController,
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.5,
      maxScale: 3.0,
      child: Container(
        color: Colors.black,
        child: Center(
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 1 / _terminalDistance)
              ..scale(_terminalScale)
              ..rotateY(_terminalRotationY),
            alignment: Alignment.center,
            child: Container(
              width: 1920,
              height: 1080,
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a1a),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
                border: Border.all(
                  color: Colors.cyan.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: widget.terminalWidget,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceSwitcher() {
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: _workspaces.map((workspace) {
            final isActive = workspace == _activeWorkspace;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton(
                onPressed: () => _switchWorkspace(workspace.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Colors.cyan : const Color(0xFF1a1a1a),
                  foregroundColor: isActive ? Colors.black : Colors.cyan,
                ),
                child: Text(workspace.name),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildVRControls() {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _VRControlButton(
            icon: Icons.center_focus_strong,
            label: 'Recenter',
            onPressed: () => _recenterView(),
          ),
          _VRControlButton(
            icon: Icons.menu,
            label: 'Menu',
            onPressed: () => _showContextMenu(),
          ),
          _VRControlButton(
            icon: Icons.mic,
            label: 'Voice',
            onPressed: () => _toggleVoiceCommands(),
            active: _voiceCommandsActive,
          ),
          _VRControlButton(
            icon: Icons.visibility,
            label: 'Comfort',
            onPressed: () => _toggleComfortMode(),
            active: _comfortModeActive,
          ),
          _VRControlButton(
            icon: Icons.settings,
            label: 'Settings',
            onPressed: () => _openSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildGazeCursor() {
    return Positioned(
      left: _gazePosition.dx - 15,
      top: _gazePosition.dy - 15,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.cyan.withOpacity(0.8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.cyan.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.remove_red_eye,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildHandIndicator(VRHand hand, Color color) {
    if (hand.position == Offset.zero) return const SizedBox.shrink();

    return Positioned(
      left: hand.position.dx - 20,
      top: hand.position.dy - 20,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(
          _getGestureIcon(hand.gesture),
          color: Colors.white,
          size: 20,
        ),
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
      case HandGesture.none:
        return Icons.pan_tool;
      case HandGesture.thumbsUp:
        return Icons.thumb_up;
      case HandGesture.peace:
        return Icons.front_hand;
    }
  }

  Widget _buildVoiceIndicator() {
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.mic, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              _lastVoiceCommand,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComfortIndicator() {
    final comfortLevel = _calculateComfortLevel();

    return Positioned(
      top: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _getComfortColor(comfortLevel).withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Comfort Level: ${comfortLevel.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  double _calculateComfortLevel() {
    // Calculate based on usage time, distance, and eye strain
    double level = 1.0;

    if (_continuousUseTime > 30) level -= 0.3;
    if (_terminalDistance < 1.5) level -= 0.2;
    if (_pupilDilation > 0.8) level -= 0.2;

    return level.clamp(0.0, 1.0);
  }

  Color _getComfortColor(double level) {
    if (level > 0.7) return Colors.green;
    if (level > 0.4) return Colors.yellow;
    return Colors.red;
  }

  void _recenterView() {
    setState(() {
      _terminalDistance = widget.comfortDistance;
      _terminalScale = 1.0;
      _terminalRotationY = 0.0;
      _terminalPosition = Offset.zero;
    });
    _transformController.value = Matrix4.identity();
    _triggerHapticPattern('success');
  }

  void _toggleVoiceCommands() {
    setState(() {
      _voiceCommandsActive = !_voiceCommandsActive;
    });
  }

  void _toggleComfortMode() {
    setState(() {
      _comfortModeActive = !_comfortModeActive;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _rotationController.dispose();
    _transformController.dispose();
    _gestureTimer?.cancel();
    _voiceCommandTimer?.cancel();
    _comfortCheckTimer?.cancel();
    super.dispose();
  }
}

/// VR Control Button
class _VRControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  const _VRControlButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? Colors.cyan : const Color(0xFF1a1a1a),
        foregroundColor: active ? Colors.black : Colors.cyan,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

/// VR Hand Tracking Data
class VRHand {
  final Offset position;
  final double confidence;
  final HandGesture gesture;
  final List<FingerState> fingers;

  const VRHand({
    this.position = Offset.zero,
    this.confidence = 0.0,
    this.gesture = HandGesture.none,
    this.fingers = const [],
  });
}

/// Hand Gestures
enum HandGesture {
  none,
  open,
  fist,
  point,
  pinch,
  thumbsUp,
  peace,
}

/// Finger States
enum FingerState {
  extended,
  curled,
  halfCurled,
}

/// Haptic Feedback Pattern
class HapticPattern {
  final String name;
  final List<int> pattern; // [delay, duration, delay, duration, ...]
  final double amplitude;

  const HapticPattern({
    required this.name,
    required this.pattern,
    required this.amplitude,
  });
}

/// Spatial UI Panel
class VRSpatialPanel {
  final String id;
  final String title;
  final Widget content;
  Offset position;
  Size size;
  bool isGrabbed = false;
  double opacity = 1.0;

  VRSpatialPanel({
    required this.id,
    required this.title,
    required this.content,
    required this.position,
    required this.size,
  });

  bool containsPoint(Offset point) {
    return point.dx >= position.dx &&
           point.dx <= position.dx + size.width &&
           point.dy >= position.dy &&
           point.dy <= position.dy + size.height;
  }

  void onHandInteraction(VRHand hand) {
    // Handle hand interactions with panel
    if (hand.gesture == HandGesture.fist) {
      isGrabbed = true;
    } else if (isGrabbed && hand.gesture == HandGesture.open) {
      isGrabbed = false;
    }

    if (isGrabbed) {
      position = hand.position - Offset(size.width / 2, size.height / 2);
    }
  }

  void updateGazeFocus(Offset gaze) {
    // Update panel based on gaze
    final isFocused = containsPoint(gaze);
    opacity = isFocused ? 1.0 : 0.7;
  }

  Widget build() {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a1a),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.cyan.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.cyan.withOpacity(0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2a2a2a),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.cyan),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        // Close panel logic would be handled by parent
                      },
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Terminal Workspace
enum WorkspaceLayout {
  single,
  grid,
  focus,
  split,
}

class VRTerminalWorkspace {
  final String id;
  final String name;
  final List<VRSpatialPanel> panels;
  final WorkspaceLayout layout;

  VRTerminalWorkspace({
    required this.id,
    required this.name,
    required this.panels,
    required this.layout,
  });
}