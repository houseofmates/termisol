import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Smooth Animations System
/// 
/// Provides advanced animation capabilities with physics-based motion,
/// custom easing functions, and performance optimization
class SmoothAnimations {
  final Map<String, AnimationController> _controllers = {};
  final Map<String, Animation> _animations = {};
  final Map<String, AnimationGroup> _animationGroups = {};
  final List<PhysicsAnimation> _physicsAnimations = [];
  
  // Performance optimization
  final Map<String, DateTime> _lastUsed = {};
  Timer? _cleanupTimer;
  static const Duration _cleanupInterval = Duration(minutes: 5);
  static const Duration _maxIdleTime = Duration(minutes: 10);
  
  // Global animation settings
  double _globalSpeedMultiplier = 1.0;
  bool _reduceMotion = false;
  
  /// Initialize smooth animations system
  void initialize() {
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _cleanupUnusedAnimations());
    debugPrint('🎬 Smooth Animations System initialized');
  }
  
  /// Create a simple fade animation
  Animation<double> createFadeAnimation({
    required String id,
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 300),
    double begin = 0.0,
    double end = 1.0,
    Curve curve = Curves.easeInOut,
  }) {
    return _createAnimation(
      id: id,
      vsync: vsync,
      duration: duration,
      begin: begin,
      end: end,
      curve: curve,
    );
  }
  
  /// Create a slide animation
  Animation<Offset> createSlideAnimation({
    required String id,
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 300),
    Offset begin = Offset.zero,
    Offset end = Offset.zero,
    Curve curve = Curves.easeInOut,
  }) {
    final controller = AnimationController(
      duration: duration,
      vsync: vsync,
    );
    
    final animation = Tween<Offset>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: curve,
    ));
    
    _controllers[id] = controller;
    _animations[id] = animation;
    _lastUsed[id] = DateTime.now();
    
    return animation;
  }
  
  /// Create a scale animation
  Animation<double> createScaleAnimation({
    required String id,
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 300),
    double begin = 0.0,
    double end = 1.0,
    Curve curve = Curves.elasticOut,
  }) {
    return _createAnimation(
      id: id,
      vsync: vsync,
      duration: duration,
      begin: begin,
      end: end,
      curve: curve,
    );
  }
  
  /// Create a rotation animation
  Animation<double> createRotationAnimation({
    required String id,
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 500),
    double begin = 0.0,
    double end = 1.0,
    Curve curve = Curves.easeInOut,
  }) {
    return _createAnimation(
      id: id,
      vsync: vsync,
      duration: duration,
      begin: begin,
      end: end,
      curve: curve,
    );
  }
  
  /// Create a physics-based spring animation
  PhysicsAnimation createSpringAnimation({
    required String id,
    required TickerProvider vsync,
    double mass = 1.0,
    double stiffness = 100.0,
    double damping = 10.0,
    double initialVelocity = 0.0,
  }) {
    final animation = PhysicsAnimation.spring(
      id: id,
      vsync: vsync,
      mass: mass,
      stiffness: stiffness,
      damping: damping,
      initialVelocity: initialVelocity,
    );
    
    _physicsAnimations.add(animation);
    _lastUsed[id] = DateTime.now();
    
    return animation;
  }
  
  /// Create a physics-based bounce animation
  PhysicsAnimation createBounceAnimation({
    required String id,
    required TickerProvider vsync,
    double gravity = 9.8,
    double bounce = 0.7,
    double friction = 0.1,
  }) {
    final animation = PhysicsAnimation.bounce(
      id: id,
      vsync: vsync,
      gravity: gravity,
      bounce: bounce,
      friction: friction,
    );
    
    _physicsAnimations.add(animation);
    _lastUsed[id] = DateTime.now();
    
    return animation;
  }
  
  /// Create a staggered animation group
  AnimationGroup createStaggeredAnimation({
    required String id,
    required List<AnimationConfig> animations,
    Duration staggerDelay = const Duration(milliseconds: 100),
  }) {
    final group = AnimationGroup.staggered(
      id: id,
      animations: animations,
      staggerDelay: staggerDelay,
    );
    
    _animationGroups[id] = group;
    _lastUsed[id] = DateTime.now();
    
    return group;
  }
  
  /// Create a parallel animation group
  AnimationGroup createParallelAnimation({
    required String id,
    required List<AnimationConfig> animations,
  }) {
    final group = AnimationGroup.parallel(
      id: id,
      animations: animations,
    );
    
    _animationGroups[id] = group;
    _lastUsed[id] = DateTime.now();
    
    return group;
  }
  
  /// Create a sequential animation group
  AnimationGroup createSequentialAnimation({
    required String id,
    required List<AnimationConfig> animations,
  }) {
    final group = AnimationGroup.sequential(
      id: id,
      animations: animations,
    );
    
    _animationGroups[id] = group;
    _lastUsed[id] = DateTime.now();
    
    return group;
  }
  
  /// Play animation
  Future<void> play(String id, {double? from, double? to}) async {
    _lastUsed[id] = DateTime.now();
    
    // Check regular animations
    final controller = _controllers[id];
    if (controller != null) {
      if (from != null) {
        controller.value = from;
      }
      await controller.forward();
      return;
    }
    
    // Check animation groups
    final group = _animationGroups[id];
    if (group != null) {
      await group.play(from: from, to: to);
      return;
    }
    
    // Check physics animations
    final physicsAnimation = _physicsAnimations.where((a) => a.id == id).firstOrNull;
    if (physicsAnimation != null) {
      await physicsAnimation.play();
      return;
    }
  }
  
  /// Reverse animation
  Future<void> reverse(String id) async {
    _lastUsed[id] = DateTime.now();
    
    final controller = _controllers[id];
    if (controller != null) {
      await controller.reverse();
      return;
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      await group.reverse();
      return;
    }
  }
  
  /// Stop animation
  void stop(String id) {
    final controller = _controllers[id];
    if (controller != null) {
      controller.stop();
      return;
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      group.stop();
      return;
    }
    
    final physicsAnimation = _physicsAnimations.where((a) => a.id == id).firstOrNull;
    if (physicsAnimation != null) {
      physicsAnimation.stop();
    }
  }
  
  /// Reset animation
  void reset(String id) {
    final controller = _controllers[id];
    if (controller != null) {
      controller.reset();
      return;
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      group.reset();
      return;
    }
    
    final physicsAnimation = _physicsAnimations.where((a) => a.id == id).firstOrNull;
    if (physicsAnimation != null) {
      physicsAnimation.reset();
    }
  }
  
  /// Set animation value
  void setValue(String id, double value) {
    _lastUsed[id] = DateTime.now();
    
    final controller = _controllers[id];
    if (controller != null) {
      controller.value = value;
      return;
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      group.setValue(value);
      return;
    }
  }
  
  /// Get animation value
  double getValue(String id) {
    final controller = _controllers[id];
    if (controller != null) {
      return controller.value;
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      return group.value;
    }
    
    final physicsAnimation = _physicsAnimations.where((a) => a.id == id).firstOrNull;
    if (physicsAnimation != null) {
      return physicsAnimation.value;
    }
    
    return 0.0;
  }
  
  /// Check if animation is running
  bool isRunning(String id) {
    final controller = _controllers[id];
    if (controller != null) {
      return controller.isAnimating;
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      return group.isRunning;
    }
    
    final physicsAnimation = _physicsAnimations.where((a) => a.id == id).firstOrNull;
    if (physicsAnimation != null) {
      return physicsAnimation.isRunning;
    }
    
    return false;
  }
  
  /// Set global speed multiplier
  void setGlobalSpeedMultiplier(double multiplier) {
    _globalSpeedMultiplier = multiplier.clamp(0.1, 3.0);
    
    // Update all animation controllers
    for (final controller in _controllers.values) {
      final originalDuration = controller.duration;
      if (originalDuration != null) {
        controller.duration = Duration(
          milliseconds: (originalDuration.inMilliseconds / _globalSpeedMultiplier).round(),
        );
      }
    }
  }
  
  /// Enable/disable reduce motion
  void setReduceMotion(bool enabled) {
    _reduceMotion = enabled;
    
    if (enabled) {
      // Apply reduced motion settings
      for (final controller in _controllers.values) {
        final originalDuration = controller.duration;
        if (originalDuration != null && originalDuration.inMilliseconds > 100) {
          controller.duration = const Duration(milliseconds: 100);
        }
      }
    }
  }
  
  /// Create custom easing curve
  Curve createCustomEasing({
    required List<double> controlPoints,
    CurveType type = CurveType.cubicBezier,
  }) {
    switch (type) {
      case CurveType.cubicBezier:
        return CubicBezierCurve(controlPoints);
      case CurveType.easeIn:
        return EaseInCurve(controlPoints);
      case CurveType.easeOut:
        return EaseOutCurve(controlPoints);
      case CurveType.easeInOut:
        return EaseInOutCurve(controlPoints);
      case CurveType.bounce:
        return BounceCurve(controlPoints);
      case CurveType.elastic:
        return ElasticCurve(controlPoints);
    }
  }
  
  /// Create animation with custom curve
  Animation<double> createCustomAnimation({
    required String id,
    required TickerProvider vsync,
    required Duration duration,
    double begin = 0.0,
    double end = 1.0,
    required Curve curve,
  }) {
    return _createAnimation(
      id: id,
      vsync: vsync,
      duration: duration,
      begin: begin,
      end: end,
      curve: curve,
    );
  }
  
  /// Internal animation creation helper
  Animation<double> _createAnimation({
    required String id,
    required TickerProvider vsync,
    required Duration duration,
    required double begin,
    required double end,
    required Curve curve,
  }) {
    // Apply global speed multiplier
    final adjustedDuration = Duration(
      milliseconds: (duration.inMilliseconds / _globalSpeedMultiplier).round(),
    );
    
    // Apply reduce motion
    final finalDuration = _reduceMotion && adjustedDuration.inMilliseconds > 100
        ? const Duration(milliseconds: 100)
        : adjustedDuration;
    
    final controller = AnimationController(
      duration: finalDuration,
      vsync: vsync,
    );
    
    final animation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: curve,
    ));
    
    _controllers[id] = controller;
    _animations[id] = animation;
    _lastUsed[id] = DateTime.now();
    
    return animation;
  }
  
  /// Clean up unused animations
  void _cleanupUnusedAnimations() {
    final now = DateTime.now();
    final toRemove = <String>[];
    
    // Check regular animations
    for (final entry in _lastUsed.entries) {
      if (now.difference(entry.value) > _maxIdleTime) {
        toRemove.add(entry.key);
      }
    }
    
    // Remove unused animations
    for (final id in toRemove) {
      removeAnimation(id);
    }
    
    if (toRemove.isNotEmpty) {
      debugPrint('🧹 Cleaned up ${toRemove.length} unused animations');
    }
  }
  
  /// Remove animation
  void removeAnimation(String id) {
    final controller = _controllers[id];
    if (controller != null) {
      controller.dispose();
      _controllers.remove(id);
    }
    
    _animations.remove(id);
    _animationGroups.remove(id);
    _lastUsed.remove(id);
    
    // Remove physics animation
    _physicsAnimations.removeWhere((a) => a.id == id);
  }
  
  /// Get animation status
  AnimationStatus getAnimationStatus(String id) {
    final controller = _controllers[id];
    if (controller != null) {
      return AnimationStatus(
        id: id,
        isRunning: controller.isAnimating,
        value: controller.value,
        duration: controller.duration,
        lastUsed: _lastUsed[id],
      );
    }
    
    final group = _animationGroups[id];
    if (group != null) {
      return AnimationStatus(
        id: id,
        isRunning: group.isRunning,
        value: group.value,
        duration: group.duration,
        lastUsed: _lastUsed[id],
      );
    }
    
    final physicsAnimation = _physicsAnimations.where((a) => a.id == id).firstOrNull;
    if (physicsAnimation != null) {
      return AnimationStatus(
        id: id,
        isRunning: physicsAnimation.isRunning,
        value: physicsAnimation.value,
        duration: physicsAnimation.duration,
        lastUsed: _lastUsed[id],
      );
    }
    
    return AnimationStatus(
      id: id,
      isRunning: false,
      value: 0.0,
      lastUsed: _lastUsed[id],
    );
  }
  
  /// Get all animation statuses
  List<AnimationStatus> getAllAnimationStatuses() {
    final statuses = <AnimationStatus>[];
    
    for (final id in _controllers.keys) {
      statuses.add(getAnimationStatus(id));
    }
    
    for (final id in _animationGroups.keys) {
      statuses.add(getAnimationStatus(id));
    }
    
    for (final animation in _physicsAnimations) {
      statuses.add(getAnimationStatus(animation.id));
    }
    
    return statuses;
  }
  
  /// Dispose smooth animations system
  void dispose() {
    // Dispose all controllers
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    
    // Clear all collections
    _controllers.clear();
    _animations.clear();
    _animationGroups.clear();
    _physicsAnimations.clear();
    _lastUsed.clear();
    
    // Cancel cleanup timer
    _cleanupTimer?.cancel();
    
    debugPrint('🎬 Smooth Animations System disposed');
  }
}

/// Animation configuration
class AnimationConfig {
  final String id;
  final Duration duration;
  final double begin;
  final double end;
  final Curve curve;
  final AnimationType type;
  
  AnimationConfig({
    required this.id,
    required this.duration,
    this.begin = 0.0,
    this.end = 1.0,
    this.curve = Curves.easeInOut,
    this.type = AnimationType.fade,
  });
}

/// Animation group
class AnimationGroup {
  final String id;
  final List<AnimationConfig> animations;
  final GroupType groupType;
  final Duration? staggerDelay;
  
  final Map<String, AnimationController> _controllers = {};
  bool _isRunning = false;
  
  AnimationGroup({
    required this.id,
    required this.animations,
    required this.groupType,
    this.staggerDelay,
  });
  
  factory AnimationGroup.staggered({
    required String id,
    required List<AnimationConfig> animations,
    Duration staggerDelay = const Duration(milliseconds: 100),
  }) {
    return AnimationGroup(
      id: id,
      animations: animations,
      groupType: GroupType.staggered,
      staggerDelay: staggerDelay,
    );
  }
  
  factory AnimationGroup.parallel({
    required String id,
    required List<AnimationConfig> animations,
  }) {
    return AnimationGroup(
      id: id,
      animations: animations,
      groupType: GroupType.parallel,
    );
  }
  
  factory AnimationGroup.sequential({
    required String id,
    required List<AnimationConfig> animations,
  }) {
    return AnimationGroup(
      id: id,
      animations: animations,
      groupType: GroupType.sequential,
    );
  }
  
  Future<void> play({double? from, double? to}) async {
    _isRunning = true;
    
    switch (groupType) {
      case GroupType.parallel:
        await _playParallel(from: from, to: to);
        break;
      case GroupType.sequential:
        await _playSequential(from: from, to: to);
        break;
      case GroupType.staggered:
        await _playStaggered(from: from, to: to);
        break;
    }
    
    _isRunning = false;
  }
  
  Future<void> reverse() async {
    _isRunning = true;
    
    switch (groupType) {
      case GroupType.parallel:
        await _reverseParallel();
        break;
      case GroupType.sequential:
        await _reverseSequential();
        break;
      case GroupType.staggered:
        await _reverseStaggered();
        break;
    }
    
    _isRunning = false;
  }
  
  void stop() {
    for (final controller in _controllers.values) {
      controller.stop();
    }
    _isRunning = false;
  }
  
  void reset() {
    for (final controller in _controllers.values) {
      controller.reset();
    }
    _isRunning = false;
  }
  
  void setValue(double value) {
    for (final controller in _controllers.values) {
      controller.value = value;
    }
  }
  
  bool get isRunning => _isRunning;
  double get value => _controllers.values.isNotEmpty ? _controllers.values.first.value : 0.0;
  Duration? get duration => _controllers.values.isNotEmpty ? _controllers.values.first.duration : null;
  
  Future<void> _playParallel({double? from, double? to}) async {
    final futures = <Future<void>>[];
    
    for (final config in animations) {
      if (from != null) {
        // Would need to set controller value
      }
      futures.add(_controllers[config.id]?.forward() ?? Future.value());
    }
    
    await Future.wait(futures);
  }
  
  Future<void> _playSequential({double? from, double? to}) async {
    for (final config in animations) {
      if (from != null) {
        // Would need to set controller value
      }
      await _controllers[config.id]?.forward() ?? Future.value();
    }
  }
  
  Future<void> _playStaggered({double? from, double? to}) async {
    for (int i = 0; i < animations.length; i++) {
      final config = animations[i];
      
      if (i > 0 && staggerDelay != null) {
        await Future.delayed(staggerDelay!);
      }
      
      if (from != null) {
        // Would need to set controller value
      }
      await _controllers[config.id]?.forward() ?? Future.value();
    }
  }
  
  Future<void> _reverseParallel() async {
    final futures = <Future<void>>[];
    
    for (final config in animations) {
      futures.add(_controllers[config.id]?.reverse() ?? Future.value());
    }
    
    await Future.wait(futures);
  }
  
  Future<void> _reverseSequential() async {
    for (final config in animations) {
      await _controllers[config.id]?.reverse() ?? Future.value();
    }
  }
  
  Future<void> _reverseStaggered() async {
    for (int i = 0; i < animations.length; i++) {
      final config = animations[i];
      
      if (i > 0 && staggerDelay != null) {
        await Future.delayed(staggerDelay!);
      }
      
      await _controllers[config.id]?.reverse() ?? Future.value();
    }
  }
}

/// Physics animation
class PhysicsAnimation {
  final String id;
  final TickerProvider vsync;
  final PhysicsType type;
  final Map<String, dynamic> parameters;
  
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isRunning = false;
  
  PhysicsAnimation({
    required this.id,
    required this.vsync,
    required this.type,
    required this.parameters,
  }) {
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: vsync,
    );
    
    _setupPhysicsAnimation();
  }
  
  factory PhysicsAnimation.spring({
    required String id,
    required TickerProvider vsync,
    double mass = 1.0,
    double stiffness = 100.0,
    double damping = 10.0,
    double initialVelocity = 0.0,
  }) {
    return PhysicsAnimation(
      id: id,
      vsync: vsync,
      type: PhysicsType.spring,
      parameters: {
        'mass': mass,
        'stiffness': stiffness,
        'damping': damping,
        'initialVelocity': initialVelocity,
      },
    );
  }
  
  factory PhysicsAnimation.bounce({
    required String id,
    required TickerProvider vsync,
    double gravity = 9.8,
    double bounce = 0.7,
    double friction = 0.1,
  }) {
    return PhysicsAnimation(
      id: id,
      vsync: vsync,
      type: PhysicsType.bounce,
      parameters: {
        'gravity': gravity,
        'bounce': bounce,
        'friction': friction,
      },
    );
  }
  
  void _setupPhysicsAnimation() {
    switch (type) {
      case PhysicsType.spring:
        final mass = parameters['mass'] as double;
        final stiffness = parameters['stiffness'] as double;
        final damping = parameters['damping'] as double;
        
        // Create spring physics curve
        final curve = SpringPhysicsCurve(
          mass: mass,
          stiffness: stiffness,
          damping: damping,
        );
        
        _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: curve),
        );
        break;
        
      case PhysicsType.bounce:
        final gravity = parameters['gravity'] as double;
        final bounce = parameters['bounce'] as double;
        final friction = parameters['friction'] as double;
        
        // Create bounce physics curve
        final curve = BouncePhysicsCurve(
          gravity: gravity,
          bounce: bounce,
          friction: friction,
        );
        
        _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: curve),
        );
        break;
    }
  }
  
  Future<void> play() async {
    _isRunning = true;
    await _controller.forward();
    _isRunning = false;
  }
  
  void stop() {
    _controller.stop();
    _isRunning = false;
  }
  
  void reset() {
    _controller.reset();
    _isRunning = false;
  }
  
  bool get isRunning => _isRunning;
  double get value => _animation.value;
  Duration get duration => _controller.duration;
}

/// Supporting enums and classes

enum AnimationType { fade, slide, scale, rotation, custom }
enum GroupType { parallel, sequential, staggered }
enum PhysicsType { spring, bounce }
enum CurveType { cubicBezier, easeIn, easeOut, easeInOut, bounce, elastic }

class AnimationStatus {
  final String id;
  final bool isRunning;
  final double value;
  final Duration? duration;
  final DateTime? lastUsed;
  
  AnimationStatus({
    required this.id,
    required this.isRunning,
    required this.value,
    this.duration,
    this.lastUsed,
  });
}

// Custom curve implementations
class CubicBezierCurve extends Curve {
  final List<double> controlPoints;
  
  CubicBezierCurve(this.controlPoints);
  
  @override
  double transform(double t) {
    // Simplified cubic bezier implementation
    if (controlPoints.length >= 4) {
      final p0x = 0.0, p0y = 0.0;
      final p1x = controlPoints[0], p1y = controlPoints[1];
      final p2x = controlPoints[2], p2y = controlPoints[3];
      final p3x = 1.0, p3y = 1.0;
      
      // Cubic bezier formula
      final u = 1 - t;
      final tt = t * t;
      final uu = u * u;
      final uuu = uu * u;
      final ttt = tt * t;
      
      final x = uuu * p0x + 3 * uu * t * p1x + 3 * u * tt * p2x + ttt * p3x;
      final y = uuu * p0y + 3 * uu * t * p1y + 3 * u * tt * p2y + ttt * p3y;
      
      return y;
    }
    return t;
  }
}

class EaseInCurve extends Curve {
  final List<double> parameters;
  
  EaseInCurve(this.parameters);
  
  @override
  double transform(double t) {
    final power = parameters.isNotEmpty ? parameters[0] : 2.0;
    return pow(t, power).toDouble();
  }
}

class EaseOutCurve extends Curve {
  final List<double> parameters;
  
  EaseOutCurve(this.parameters);
  
  @override
  double transform(double t) {
    final power = parameters.isNotEmpty ? parameters[0] : 2.0;
    return 1.0 - pow(1.0 - t, power).toDouble();
  }
}

class EaseInOutCurve extends Curve {
  final List<double> parameters;
  
  EaseInOutCurve(this.parameters);
  
  @override
  double transform(double t) {
    final power = parameters.isNotEmpty ? parameters[0] : 2.0;
    if (t < 0.5) {
      return pow(2.0 * t, power).toDouble() / 2.0;
    } else {
      return 1.0 - pow(2.0 * (1.0 - t), power).toDouble() / 2.0;
    }
  }
}

class BounceCurve extends Curve {
  final List<double> parameters;
  
  BounceCurve(this.parameters);
  
  @override
  double transform(double t) {
    final bounces = parameters.isNotEmpty ? parameters[0].floor() : 3;
    final amplitude = parameters.length > 1 ? parameters[1] : 0.3;
    
    if (t == 0.0 || t == 1.0) return t;
    
    double value = 0.0;
    for (int i = 0; i < bounces; i++) {
      final bounceTime = (i + 1) / bounces;
      if (t <= bounceTime) {
        final localT = (t - (i / bounces)) / (1.0 / bounces);
        value = amplitude * sin(pi * localT) * exp(-localT * 2);
        break;
      }
    }
    
    return value + (1.0 - amplitude * exp(-2));
  }
}

class ElasticCurve extends Curve {
  final List<double> parameters;
  
  ElasticCurve(this.parameters);
  
  @override
  double transform(double t) {
    final amplitude = parameters.isNotEmpty ? parameters[0] : 0.5;
    final frequency = parameters.length > 1 ? parameters[1] : 3.0;
    
    if (t == 0.0 || t == 1.0) return t;
    
    return amplitude * sin(2 * pi * frequency * t) * exp(-t * 5) + t;
  }
}

// Physics curve implementations
class SpringPhysicsCurve extends Curve {
  final double mass;
  final double stiffness;
  final double damping;
  
  SpringPhysicsCurve({
    required this.mass,
    required this.stiffness,
    required this.damping,
  });
  
  @override
  double transform(double t) {
    // Simplified spring physics
    final omega = sqrt(stiffness / mass);
    final zeta = damping / (2 * sqrt(mass * stiffness));
    
    if (zeta < 1.0) {
      // Underdamped
      final omegaD = omega * sqrt(1 - zeta * zeta);
      return 1.0 - exp(-zeta * omega * t) * cos(omegaD * t);
    } else if (zeta == 1.0) {
      // Critically damped
      return 1.0 - exp(-omega * t) * (1 + omega * t);
    } else {
      // Overdamped
      return 1.0 - exp(-zeta * omega * t);
    }
  }
}

class BouncePhysicsCurve extends Curve {
  final double gravity;
  final double bounce;
  final double friction;
  
  BouncePhysicsCurve({
    required this.gravity,
    required this.bounce,
    required this.friction,
  });
  
  @override
  double transform(double t) {
    // Simplified bounce physics
    double height = 1.0;
    double velocity = 0.0;
    double position = 0.0;
    double time = 0.0;
    
    while (time < t && height > 0.01) {
      velocity += gravity * 0.016; // 60fps timestep
      position += velocity * 0.016;
      
      if (position >= height) {
        position = height;
        velocity = -velocity * bounce;
        height *= bounce;
      }
      
      time += 0.016;
    }
    
    return 1.0 - position;
  }
}