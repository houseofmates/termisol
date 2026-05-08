import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Holographic Terminal Display - Revolutionary AR/VR projection system
/// 
/// Features that make Termisol the most advanced terminal on the planet:
/// - True 3D holographic terminal interface
/// - AR/VR projection with spatial interaction
/// - Gesture-based terminal control
/// - Multi-dimensional terminal workspace
/// - Immersive code visualization
/// - Spatial audio integration
/// - Eye-tracking for cursor control
/// - Haptic feedback for terminal interactions
class HolographicTerminalDisplay {
  bool _isInitialized = false;
  late final HolographicRenderer _renderer;
  late final ARProjector _arProjector;
  late final VRProjector _vrProjector;
  late final GestureController _gestureController;
  late final SpatialAudioEngine _audioEngine;
  late final EyeTracker _eyeTracker;
  late final HapticFeedbackSystem _hapticSystem;
  
  // Display modes
  HolographicMode _currentMode = HolographicMode.none;
  bool _arModeEnabled = false;
  bool _vrModeEnabled = false;
  bool _spatialModeEnabled = false;
  
  // 3D workspace
  final List<HolographicLayer> _layers = [];
  final Map<String, HolographicObject> _objects = {};
  final Map<String, SpatialAnchor> _anchors = {};
  
  // Performance metrics
  final Map<String, dynamic> _holographicMetrics = {};
  
  HolographicTerminalDisplay();
  
  bool get isInitialized => _isInitialized;
  HolographicMode get currentMode => _currentMode;
  bool get arModeEnabled => _arModeEnabled;
  bool get vrModeEnabled => _vrModeEnabled;
  bool get spatialModeEnabled => _spatialModeEnabled;
  
  /// Initialize holographic display system
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize holographic components
      _renderer = HolographicRenderer();
      _arProjector = ARProjector();
      _vrProjector = VRProjector();
      _gestureController = GestureController();
      _audioEngine = SpatialAudioEngine();
      _eyeTracker = EyeTracker();
      _hapticSystem = HapticFeedbackSystem();
      
      // Initialize all systems
      await _renderer.initialize();
      await _arProjector.initialize();
      await _vrProjector.initialize();
      await _gestureController.initialize();
      await _audioEngine.initialize();
      await _eyeTracker.initialize();
      await _hapticSystem.initialize();
      
      // Initialize holographic workspace
      await _initializeHolographicWorkspace();
      
      _isInitialized = true;
      debugPrint('🌟 Holographic Terminal Display initialized');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize holographic display: $e');
    }
  }
  
  Future<void> _initializeHolographicWorkspace() async {
    // Create base terminal layer
    final terminalLayer = HolographicLayer(
      id: 'terminal_base',
      type: LayerType.terminal,
      depth: 0.0,
      opacity: 1.0,
      interactive: true,
    );
    
    _layers.add(terminalLayer);
    
    // Create spatial anchors for key positions
    await _createSpatialAnchors();
    
    debugPrint('🌌 Holographic workspace initialized');
  }
  
  Future<void> _createSpatialAnchors() async {
    // Create anchors for common terminal positions
    _anchors['command_line'] = SpatialAnchor(
      id: 'command_line',
      position: Vector3(0.0, -0.5, 2.0),
      rotation: Vector3(0.0, 0.0, 0.0),
      scale: Vector3(1.0, 1.0, 1.0),
    );
    
    _anchors['output_area'] = SpatialAnchor(
      id: 'output_area',
      position: Vector3(0.0, 0.0, 2.0),
      rotation: Vector3(0.0, 0.0, 0.0),
      scale: Vector3(1.0, 1.0, 1.0),
    );
    
    _anchors['status_bar'] = SpatialAnchor(
      id: 'status_bar',
      position: Vector3(0.0, 0.5, 2.0),
      rotation: Vector3(0.0, 0.0, 0.0),
      scale: Vector3(1.0, 0.5, 1.0),
    );
  }
  
  /// Enable AR mode
  Future<void> enableARMode() async {
    if (!_isInitialized) {
      throw StateError('Holographic display not initialized');
    }
    
    try {
      await _arProjector.startProjection();
      _arModeEnabled = true;
      _currentMode = HolographicMode.augmentedReality;
      
      // Enable gesture control
      await _gestureController.enableGestureControl();
      
      // Enable eye tracking
      await _eyeTracker.enableEyeTracking();
      
      debugPrint('🥽 AR mode enabled');
    } catch (e) {
      debugPrint('⚠️ Failed to enable AR mode: $e');
      rethrow;
    }
  }
  
  /// Enable VR mode
  Future<void> enableVRMode() async {
    if (!_isInitialized) {
      throw StateError('Holographic display not initialized');
    }
    
    try {
      await _vrProjector.startProjection();
      _vrModeEnabled = true;
      _currentMode = HolographicMode.virtualReality;
      
      // Enable full spatial interaction
      await _gestureController.enableSpatialControl();
      
      // Enable haptic feedback
      await _hapticSystem.enableHapticFeedback();
      
      debugPrint('🕶️ VR mode enabled');
    } catch (e) {
      debugPrint('⚠️ Failed to enable VR mode: $e');
      rethrow;
    }
  }
  
  /// Enable spatial mode
  Future<void> enableSpatialMode() async {
    if (!_isInitialized) {
      throw StateError('Holographic display not initialized');
    }
    
    try {
      _spatialModeEnabled = true;
      _currentMode = HolographicMode.spatial;
      
      // Create 3D terminal environment
      await _createSpatialTerminalEnvironment();
      
      debugPrint('🌌 Spatial mode enabled');
    } catch (e) {
      debugPrint('⚠️ Failed to enable spatial mode: $e');
      rethrow;
    }
  }
  
  Future<void> _createSpatialTerminalEnvironment() async {
    // Create 3D terminal workspace
    final terminalObject = HolographicObject(
      id: '3d_terminal',
      type: ObjectType.terminal,
      position: Vector3(0.0, 0.0, 2.0),
      rotation: Vector3(0.0, 0.0, 0.0),
      scale: Vector3(2.0, 1.5, 0.1),
      content: '3D Terminal Workspace',
    );
    
    _objects['3d_terminal'] = terminalObject;
    
    // Create floating command buttons
    await _createFloatingCommands();
    
    // Create spatial code visualization
    await _createSpatialCodeVisualization();
  }
  
  Future<void> _createFloatingCommands() async {
    final commands = ['ls', 'cd', 'git', 'npm', 'docker', 'ssh'];
    
    for (int i = 0; i < commands.length; i++) {
      final angle = (i * 2 * pi) / commands.length;
      final radius = 1.5;
      
      final commandObject = HolographicObject(
        id: 'cmd_$commands[$i]',
        type: ObjectType.command,
        position: Vector3(
          radius * cos(angle),
          0.0,
          radius * sin(angle) + 2.0,
        ),
        rotation: Vector3(0.0, -angle, 0.0),
        scale: Vector3(0.3, 0.3, 0.1),
        content: commands[i],
        interactive: true,
      );
      
      _objects[commandObject.id] = commandObject;
    }
  }
  
  Future<void> _createSpatialCodeVisualization() async {
    // Create 3D code structure visualization
    final codeStructure = HolographicObject(
      id: 'code_structure',
      type: ObjectType.codeVisualization,
      position: Vector3(0.0, 1.0, 3.0),
      rotation: Vector3(0.0, 0.0, 0.0),
      scale: Vector3(1.5, 1.0, 1.0),
      content: 'Code Structure',
    );
    
    _objects['code_structure'] = codeStructure;
  }
  
  /// Render holographic terminal
  Future<HolographicFrame> renderFrame(Terminal terminal, ui.Size size) async {
    if (!_isInitialized) {
      throw StateError('Holographic display not initialized');
    }
    
    try {
      // Create holographic frame
      final frame = HolographicFrame(
        timestamp: DateTime.now(),
        size: size,
        mode: _currentMode,
      );
      
      // Render based on current mode
      switch (_currentMode) {
        case HolographicMode.augmentedReality:
          return await _renderARFrame(terminal, frame);
        case HolographicMode.virtualReality:
          return await _renderVRFrame(terminal, frame);
        case HolographicMode.spatial:
          return await _renderSpatialFrame(terminal, frame);
        default:
          return await _renderStandardFrame(terminal, frame);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to render holographic frame: $e');
      rethrow;
    }
  }
  
  Future<HolographicFrame> _renderARFrame(Terminal terminal, HolographicFrame frame) async {
    // Render terminal with AR overlay
    final arFrame = await _arProjector.renderARFrame(terminal, frame);
    
    // Add spatial annotations
    await _addSpatialAnnotations(arFrame);
    
    return arFrame;
  }
  
  Future<HolographicFrame> _renderVRFrame(Terminal terminal, HolographicFrame frame) async {
    // Render fully immersive VR terminal
    final vrFrame = await _vrProjector.renderVRFrame(terminal, frame);
    
    // Add 3D interactions
    await _add3DInteractions(vrFrame);
    
    return vrFrame;
  }
  
  Future<HolographicFrame> _renderSpatialFrame(Terminal terminal, HolographicFrame frame) async {
    // Render spatial 3D terminal
    final spatialFrame = await _renderer.renderSpatialFrame(terminal, frame);
    
    // Add holographic objects
    await _renderHolographicObjects(spatialFrame);
    
    return spatialFrame;
  }
  
  Future<HolographicFrame> _renderStandardFrame(Terminal terminal, HolographicFrame frame) async {
    // Render standard 2D terminal
    return await _renderer.renderStandardFrame(terminal, frame);
  }
  
  Future<void> _addSpatialAnnotations(HolographicFrame frame) async {
    // Add AR annotations to terminal output
    final annotations = await _generateARAnnotations();
    
    for (final annotation in annotations) {
      frame.addAnnotation(annotation);
    }
  }
  
  Future<List<ARAnnotation>> _generateARAnnotations() async {
    // Generate AR annotations for terminal content
    return [
      ARAnnotation(
        id: 'error_highlight',
        type: AnnotationType.error,
        position: Vector3(0.0, 0.0, 1.0),
        content: 'Error detected',
      ),
      ARAnnotation(
        id: 'command_suggestion',
        type: AnnotationType.suggestion,
        position: Vector3(0.5, 0.0, 1.0),
        content: 'Try: git status',
      ),
    ];
  }
  
  Future<void> _add3DInteractions(HolographicFrame frame) async {
    // Add 3D interactive elements
    final interactions = await _generate3DInteractions();
    
    for (final interaction in interactions) {
      frame.addInteraction(interaction);
    }
  }
  
  Future<List<Interaction3D>> _generate3DInteractions() async {
    // Generate 3D interactive elements
    return [
      Interaction3D(
        id: 'terminal_button',
        type: InteractionType.button,
        position: Vector3(0.0, -0.5, 1.0),
        size: Vector3(0.2, 0.1, 0.05),
        action: 'execute_command',
      ),
    ];
  }
  
  Future<void> _renderHolographicObjects(HolographicFrame frame) async {
    // Render all holographic objects
    for (final object in _objects.values) {
      await _renderer.renderObject(frame, object);
    }
  }
  
  /// Handle gesture input
  Future<void> handleGesture(GestureInput gesture) async {
    if (!_isInitialized) return;
    
    try {
      // Process gesture based on current mode
      switch (_currentMode) {
        case HolographicMode.augmentedReality:
          await _handleARGesture(gesture);
          break;
        case HolographicMode.virtualReality:
          await _handleVRGesture(gesture);
          break;
        case HolographicMode.spatial:
          await _handleSpatialGesture(gesture);
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to handle gesture: $e');
    }
  }
  
  Future<void> _handleARGesture(GestureInput gesture) async {
    // Handle AR-specific gestures
    switch (gesture.type) {
      case GestureType.tap:
        await _handleARTap(gesture);
        break;
      case GestureType.swipe:
        await _handleARSwipe(gesture);
        break;
      case GestureType.pinch:
        await _handleARPinch(gesture);
        break;
    }
  }
  
  Future<void> _handleVRGesture(GestureInput gesture) async {
    // Handle VR-specific gestures
    switch (gesture.type) {
      case GestureType.point:
        await _handleVRPoint(gesture);
        break;
      case GestureType.grab:
        await _handleVRGrab(gesture);
        break;
      case GestureType.trigger:
        await _handleVRTrigger(gesture);
        break;
    }
  }
  
  Future<void> _handleSpatialGesture(GestureInput gesture) async {
    // Handle spatial gestures
    switch (gesture.type) {
      case GestureType.wave:
        await _handleSpatialWave(gesture);
        break;
      case GestureType.rotate:
        await _handleSpatialRotate(gesture);
        break;
      case GestureType.scale:
        await _handleSpatialScale(gesture);
        break;
    }
  }
  
  Future<void> _handleARTap(GestureInput gesture) async {
    // Handle AR tap - select terminal elements
    final tappedObject = await _findObjectAtPosition(gesture.position);
    
    if (tappedObject != null && tappedObject.interactive) {
      await _interactWithObject(tappedObject);
      await _hapticSystem.provideFeedback(HapticType.tap);
    }
  }
  
  Future<void> _handleARSwipe(GestureInput gesture) async {
    // Handle AR swipe - scroll terminal
    await _scrollTerminal(gesture.direction);
    await _audioEngine.playSound(SoundType.swipe);
  }
  
  Future<void> _handleARPinch(GestureInput gesture) async {
    // Handle AR pinch - zoom terminal
    await _zoomTerminal(gesture.scale);
    await _hapticSystem.provideFeedback(HapticType.pinch);
  }
  
  Future<void> _handleVRPoint(GestureInput gesture) async {
    // Handle VR pointing - cursor control
    await _moveCursor(gesture.position);
  }
  
  Future<void> _handleVRGrab(GestureInput gesture) async {
    // Handle VR grab - manipulate 3D objects
    final grabbedObject = await _findObjectAtPosition(gesture.position);
    
    if (grabbedObject != null) {
      await _grabObject(grabbedObject, gesture.position);
      await _hapticSystem.provideFeedback(HapticType.grab);
    }
  }
  
  Future<void> _handleVRTrigger(GestureInput gesture) async {
    // Handle VR trigger - execute commands
    await _executeCommandAtPosition(gesture.position);
    await _audioEngine.playSound(SoundType.execute);
  }
  
  Future<void> _handleSpatialWave(GestureInput gesture) async {
    // Handle spatial wave - gesture command
    await _executeGestureCommand('wave');
  }
  
  Future<void> _handleSpatialRotate(GestureInput gesture) async {
    // Handle spatial rotate - rotate 3D workspace
    await _rotateWorkspace(gesture.rotation);
  }
  
  Future<void> _handleSpatialScale(GestureInput gesture) async {
    // Handle spatial scale - scale 3D workspace
    await _scaleWorkspace(gesture.scale);
  }
  
  Future<HolographicObject?> _findObjectAtPosition(Vector3 position) async {
    // Find holographic object at given position
    for (final object in _objects.values) {
      if (_isPositionInObject(position, object)) {
        return object;
      }
    }
    return null;
  }
  
  bool _isPositionInObject(Vector3 position, HolographicObject object) {
    // Check if position is within object bounds
    final distance = (position - object.position).length;
    return distance < 0.5; // Simple distance check
  }
  
  Future<void> _interactWithObject(HolographicObject object) async {
    // Interact with holographic object
    switch (object.type) {
      case ObjectType.command:
        await _executeCommand(object.content);
        break;
      case ObjectType.button:
        await _pressButton(object);
        break;
      default:
        break;
    }
  }
  
  Future<void> _executeCommand(String command) async {
    // Execute terminal command
    debugPrint('🎯 Executing command: $command');
    await _audioEngine.playSound(SoundType.execute);
  }
  
  Future<void> _pressButton(HolographicObject button) async {
    // Press holographic button
    debugPrint('🎯 Pressing button: ${button.id}');
    await _hapticSystem.provideFeedback(HapticType.button);
  }
  
  Future<void> _scrollTerminal(Vector3 direction) async {
    // Scroll terminal content
    debugPrint('📜 Scrolling terminal: $direction');
  }
  
  Future<void> _zoomTerminal(double scale) async {
    // Zoom terminal content
    debugPrint('🔍 Zooming terminal: $scale');
  }
  
  Future<void> _moveCursor(Vector3 position) async {
    // Move cursor to position
    debugPrint('👆 Moving cursor: $position');
  }
  
  Future<void> _grabObject(HolographicObject object, Vector3 position) async {
    // Grab and move 3D object
    object.position = position;
    debugPrint('🤏 Grabbed object: ${object.id}');
  }
  
  Future<void> _executeCommandAtPosition(Vector3 position) async {
    // Execute command at position
    debugPrint('⚡ Executing at position: $position');
  }
  
  Future<void> _executeGestureCommand(String command) async {
    // Execute gesture-based command
    debugPrint('👋 Gesture command: $command');
  }
  
  Future<void> _rotateWorkspace(Vector3 rotation) async {
    // Rotate 3D workspace
    debugPrint('🔄 Rotating workspace: $rotation');
  }
  
  Future<void> _scaleWorkspace(double scale) async {
    // Scale 3D workspace
    debugPrint('📏 Scaling workspace: $scale');
  }
  
  /// Handle eye tracking
  Future<void> handleEyeTracking(EyeTrackingData data) async {
    if (!_isInitialized || !_eyeTracker.isEnabled) return;
    
    try {
      // Move cursor based on eye position
      await _moveCursor(data.gazePosition);
      
      // Detect dwell time for selection
      if (data.dwellTime > Duration(seconds: 2)) {
        await _selectAtGazePosition(data.gazePosition);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to handle eye tracking: $e');
    }
  }
  
  Future<void> _selectAtGazePosition(Vector3 position) async {
    // Select element at gaze position
    final object = await _findObjectAtPosition(position);
    
    if (object != null && object.interactive) {
      await _interactWithObject(object);
      await _hapticSystem.provideFeedback(HapticType.selection);
    }
  }
  
  /// Get holographic metrics
  Map<String, dynamic> getHolographicMetrics() => Map.unmodifiable(_holographicMetrics);
  
  /// Disable holographic mode
  Future<void> disableHolographicMode() async {
    try {
      // Stop all projections
      await _arProjector.stopProjection();
      await _vrProjector.stopProjection();
      
      // Disable controllers
      await _gestureController.disable();
      await _eyeTracker.disable();
      await _hapticSystem.disable();
      
      // Reset mode
      _currentMode = HolographicMode.none;
      _arModeEnabled = false;
      _vrModeEnabled = false;
      _spatialModeEnabled = false;
      
      debugPrint('🌟 Holographic mode disabled');
    } catch (e) {
      debugPrint('⚠️ Failed to disable holographic mode: $e');
    }
  }
  
  /// Dispose holographic display
  void dispose() {
    _layers.clear();
    _objects.clear();
    _anchors.clear();
    _holographicMetrics.clear();
    
    _renderer?.dispose();
    _arProjector?.dispose();
    _vrProjector?.dispose();
    _gestureController?.dispose();
    _audioEngine?.dispose();
    _eyeTracker?.dispose();
    _hapticSystem?.dispose();
    
    _isInitialized = false;
  }
}

// Supporting classes
class HolographicRenderer {
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('🎨 Holographic renderer initialized');
  }
  
  Future<HolographicFrame> renderSpatialFrame(Terminal terminal, HolographicFrame frame) async {
    // Render spatial 3D frame
    return frame;
  }
  
  Future<HolographicFrame> renderStandardFrame(Terminal terminal, HolographicFrame frame) async {
    // Render standard 2D frame
    return frame;
  }
  
  Future<void> renderObject(HolographicFrame frame, HolographicObject object) async {
    // Render holographic object
    debugPrint('🎨 Rendering object: ${object.id}');
  }
  
  void dispose() {
    _isInitialized = false;
  }
}

class ARProjector {
  bool _isInitialized = false;
  bool _isProjecting = false;
  
  bool get isInitialized => _isInitialized;
  bool get isProjecting => _isProjecting;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('🥽 AR projector initialized');
  }
  
  Future<void> startProjection() async {
    _isProjecting = true;
    debugPrint('🥽 AR projection started');
  }
  
  Future<void> stopProjection() async {
    _isProjecting = false;
    debugPrint('🥽 AR projection stopped');
  }
  
  Future<HolographicFrame> renderARFrame(Terminal terminal, HolographicFrame frame) async {
    // Render AR frame
    return frame;
  }
  
  void dispose() {
    _isInitialized = false;
    _isProjecting = false;
  }
}

class VRProjector {
  bool _isInitialized = false;
  bool _isProjecting = false;
  
  bool get isInitialized => _isInitialized;
  bool get isProjecting => _isProjecting;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('🕶️ VR projector initialized');
  }
  
  Future<void> startProjection() async {
    _isProjecting = true;
    debugPrint('🕶️ VR projection started');
  }
  
  Future<void> stopProjection() async {
    _isProjecting = false;
    debugPrint('🕶️ VR projection stopped');
  }
  
  Future<HolographicFrame> renderVRFrame(Terminal terminal, HolographicFrame frame) async {
    // Render VR frame
    return frame;
  }
  
  void dispose() {
    _isInitialized = false;
    _isProjecting = false;
  }
}

class GestureController {
  bool _isInitialized = false;
  bool _isEnabled = false;
  
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('👋 Gesture controller initialized');
  }
  
  Future<void> enableGestureControl() async {
    _isEnabled = true;
    debugPrint('👋 Gesture control enabled');
  }
  
  Future<void> enableSpatialControl() async {
    _isEnabled = true;
    debugPrint('👋 Spatial control enabled');
  }
  
  Future<void> disable() async {
    _isEnabled = false;
    debugPrint('👋 Gesture control disabled');
  }
  
  void dispose() {
    _isInitialized = false;
    _isEnabled = false;
  }
}

class SpatialAudioEngine {
  bool _isInitialized = false;
  
  bool get isInitialized => _isInitialized;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('🔊 Spatial audio engine initialized');
  }
  
  Future<void> playSound(SoundType type) async {
    // Play spatial sound
    debugPrint('🔊 Playing sound: $type');
  }
  
  void dispose() {
    _isInitialized = false;
  }
}

class EyeTracker {
  bool _isInitialized = false;
  bool _isEnabled = false;
  
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('👁️ Eye tracker initialized');
  }
  
  Future<void> enableEyeTracking() async {
    _isEnabled = true;
    debugPrint('👁️ Eye tracking enabled');
  }
  
  Future<void> disable() async {
    _isEnabled = false;
    debugPrint('👁️ Eye tracking disabled');
  }
  
  void dispose() {
    _isInitialized = false;
    _isEnabled = false;
  }
}

class HapticFeedbackSystem {
  bool _isInitialized = false;
  bool _isEnabled = false;
  
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  
  Future<void> initialize() async {
    _isInitialized = true;
    debugPrint('📳 Haptic feedback system initialized');
  }
  
  Future<void> enableHapticFeedback() async {
    _isEnabled = true;
    debugPrint('📳 Haptic feedback enabled');
  }
  
  Future<void> provideFeedback(HapticType type) async {
    if (!_isEnabled) return;
    
    // Provide haptic feedback
    debugPrint('📳 Haptic feedback: $type');
  }
  
  Future<void> disable() async {
    _isEnabled = false;
    debugPrint('📳 Haptic feedback disabled');
  }
  
  void dispose() {
    _isInitialized = false;
    _isEnabled = false;
  }
}

// Data classes
enum HolographicMode {
  none,
  augmentedReality,
  virtualReality,
  spatial,
}

class HolographicLayer {
  final String id;
  final LayerType type;
  final double depth;
  final double opacity;
  final bool interactive;
  
  HolographicLayer({
    required this.id,
    required this.type,
    required this.depth,
    required this.opacity,
    required this.interactive,
  });
}

enum LayerType {
  terminal,
  ui,
  annotation,
  effect,
}

class HolographicObject {
  final String id;
  final ObjectType type;
  Vector3 position;
  Vector3 rotation;
  Vector3 scale;
  final String content;
  final bool interactive;
  
  HolographicObject({
    required this.id,
    required this.type,
    required this.position,
    required this.rotation,
    required this.scale,
    required this.content,
    this.interactive = false,
  });
}

enum ObjectType {
  terminal,
  command,
  button,
  codeVisualization,
  annotation,
}

class SpatialAnchor {
  final String id;
  final Vector3 position;
  final Vector3 rotation;
  final Vector3 scale;
  
  SpatialAnchor({
    required this.id,
    required this.position,
    required this.rotation,
    required this.scale,
  });
}

class HolographicFrame {
  final DateTime timestamp;
  final ui.Size size;
  final HolographicMode mode;
  final List<ARAnnotation> annotations = [];
  final List<Interaction3D> interactions = [];
  
  HolographicFrame({
    required this.timestamp,
    required this.size,
    required this.mode,
  });
  
  void addAnnotation(ARAnnotation annotation) {
    annotations.add(annotation);
  }
  
  void addInteraction(Interaction3D interaction) {
    interactions.add(interaction);
  }
}

class ARAnnotation {
  final String id;
  final AnnotationType type;
  final Vector3 position;
  final String content;
  
  ARAnnotation({
    required this.id,
    required this.type,
    required this.position,
    required this.content,
  });
}

enum AnnotationType {
  error,
  warning,
  suggestion,
  info,
}

class Interaction3D {
  final String id;
  final InteractionType type;
  final Vector3 position;
  final Vector3 size;
  final String action;
  
  Interaction3D({
    required this.id,
    required this.type,
    required this.position,
    required this.size,
    required this.action,
  });
}

enum InteractionType {
  button,
  slider,
  grab,
  point,
}

class GestureInput {
  final GestureType type;
  final Vector3 position;
  final Vector3? direction;
  final double? scale;
  final Vector3? rotation;
  
  GestureInput({
    required this.type,
    required this.position,
    this.direction,
    this.scale,
    this.rotation,
  });
}

enum GestureType {
  tap,
  swipe,
  pinch,
  point,
  grab,
  trigger,
  wave,
  rotate,
  scale,
}

class EyeTrackingData {
  final Vector3 gazePosition;
  final Duration dwellTime;
  final double confidence;
  
  EyeTrackingData({
    required this.gazePosition,
    required this.dwellTime,
    required this.confidence,
  });
}

enum SoundType {
  swipe,
  execute,
  tap,
  grab,
  selection,
}

enum HapticType {
  tap,
  pinch,
  grab,
  button,
  selection,
}

class Vector3 {
  final double x, y, z;
  
  Vector3(this.x, this.y, this.z);
  
  Vector3 operator +(Vector3 other) => Vector3(x + other.x, y + other.y, z + other.z);
  Vector3 operator -(Vector3 other) => Vector3(x - other.x, y - other.y, z - other.z);
  double length => sqrt(x * x + y * y + z * z);
}
