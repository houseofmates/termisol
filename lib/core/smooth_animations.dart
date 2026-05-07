import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/animation.dart';

class SmoothAnimations {
  static const int _maxConcurrentAnimations = 50;
  static const int _animationQueueSize = 100;
  static const int _defaultDuration = 300; // 300ms
  static const double _defaultEasingPower = 2.0;
  
  final Map<String, Animation> _activeAnimations = {};
  final Queue<AnimationRequest> _animationQueue = Queue();
  final Map<String, AnimationProfile> _profiles = {};
  final Map<String, List<AnimationFrame>> _frameCache = {};
  
  Timer? _animationTimer;
  int _totalAnimations = 0;
  int _droppedFrames = 0;
  double _currentFPS = 60.0;
  
  final StreamController<AnimationEvent> _animationController = 
      StreamController<AnimationEvent>.broadcast();

  void initialize() {
    _initializeProfiles();
    _startAnimationLoop();
    developer.log('🎬 Smooth Animations initialized');
  }

  void _initializeProfiles() {
    // Default profiles for common animations
    _profiles['fade'] = AnimationProfile(
      id: 'fade',
      name: 'Fade',
      duration: Duration(milliseconds: 300),
      easing: EasingType.easeInOut,
      curve: Curves.easeInOut,
      repeat: false,
      autoReverse: false,
    );
    
    _profiles['slide'] = AnimationProfile(
      id: 'slide',
      name: 'Slide',
      duration: Duration(milliseconds: 250),
      easing: EasingType.easeOut,
      curve: Curves.easeOut,
      repeat: false,
      autoReverse: false,
    );
    
    _profiles['scale'] = AnimationProfile(
      id: 'scale',
      name: 'Scale',
      duration: Duration(milliseconds: 200),
      easing: EasingType.easeOutBack,
      curve: Curves.easeOutBack,
      repeat: false,
      autoReverse: false,
    );
    
    _profiles['rotate'] = AnimationProfile(
      id: 'rotate',
      name: 'Rotate',
      duration: Duration(milliseconds: 400),
      easing: EasingType.easeInOut,
      curve: Curves.easeInOut,
      repeat: false,
      autoReverse: false,
    );
    
    _profiles['bounce'] = AnimationProfile(
      id: 'bounce',
      name: 'Bounce',
      duration: Duration(milliseconds: 600),
      easing: EasingType.elasticOut,
      curve: Curves.elasticOut,
      repeat: false,
      autoReverse: false,
    );
    
    _profiles['pulse'] = AnimationProfile(
      id: 'pulse',
      name: 'Pulse',
      duration: Duration(milliseconds: 1000),
      easing: EasingType.easeInOut,
      curve: Curves.easeInOut,
      repeat: true,
      autoReverse: true,
    );
    
    _profiles['shake'] = AnimationProfile(
      id: 'shake',
      name: 'Shake',
      duration: Duration(milliseconds: 500),
      easing: EasingType.linear,
      curve: Curves.linear,
      repeat: true,
      autoReverse: false,
    );
    
    developer.log('🎬 Initialized ${_profiles.length} animation profiles');
  }

  void _startAnimationLoop() {
    _animationTimer = Timer.periodic(
      Duration(microseconds: 16667), // ~60 FPS
      (_) => _updateAnimations(),
    );
  }

  String animate({
    required String targetId,
    required AnimationType type,
    Map<String, dynamic>? from,
    Map<String, dynamic>? to,
    String? profileId,
    Duration? duration,
    EasingType? easing,
    bool? repeat,
    bool? autoReverse,
    Function(double)? onUpdate,
    Function()? onComplete,
    Function()? onCancel,
  }) {
    if (_activeAnimations.length >= _maxConcurrentAnimations) {
      // Queue the animation
      final request = AnimationRequest(
        id: _generateRequestId(),
        targetId: targetId,
        type: type,
        from: from ?? {},
        to: to ?? {},
        profileId: profileId ?? 'default',
        duration: duration,
        easing: easing,
        repeat: repeat ?? false,
        autoReverse: autoReverse ?? false,
        onUpdate: onUpdate,
        onComplete: onComplete,
        onCancel: onCancel,
        timestamp: DateTime.now(),
      );
      
      _animationQueue.add(request);
      
      developer.log('🎬 Queued animation: $type for $targetId');
      
      _emitEvent(AnimationEvent(
        type: AnimationEventType.queued,
        animationId: request.id,
        targetId: targetId,
        animationType: type,
      ));
      
      return request.id;
    }
    
    final animationId = _generateAnimationId();
    final profile = _getProfile(profileId ?? 'default');
    
    final animation = Animation(
      id: animationId,
      targetId: targetId,
      type: type,
      from: from ?? {},
      to: to ?? {},
      profile: profile,
      duration: duration ?? profile.duration,
      easing: easing ?? profile.easing,
      curve: profile.curve,
      repeat: repeat ?? profile.repeat,
      autoReverse: autoReverse ?? profile.autoReverse,
      onUpdate: onUpdate,
      onComplete: onComplete,
      onCancel: onCancel,
      startTime: DateTime.now(),
      currentTime: 0.0,
      isRunning: true,
      isPaused: false,
      isCompleted: false,
      isCancelled: false,
      currentValues: from ?? {},
      previousValues: {},
    );
    
    _activeAnimations[animationId] = animation;
    _totalAnimations++;
    
    developer.log('🎬 Started animation: $type for $targetId');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.started,
      animationId: animationId,
      targetId: targetId,
      animationType: type,
    ));
    
    return animationId;
  }

  AnimationProfile _getProfile(String profileId) {
    return _profiles[profileId] ?? _profiles['fade']!;
  }

  void _updateAnimations() {
    final now = DateTime.now();
    final animationsToRemove = <String>[];
    
    for (final entry in _activeAnimations.entries) {
      final animationId = entry.key;
      final animation = entry.value;
      
      if (!animation.isRunning || animation.isCompleted || animation.isCancelled) {
        continue;
      }
      
      // Calculate progress
      final elapsed = now.difference(animation.startTime).inMicroseconds;
      final duration = animation.duration.inMicroseconds.toDouble();
      var progress = elapsed / duration;
      
      // Handle repeat and auto-reverse
      if (animation.repeat) {
        progress = progress % 1.0;
      } else if (animation.autoReverse) {
        final cycle = (progress / 2.0).floor();
        progress = (progress % 2.0);
        if (cycle % 2 == 1) {
          progress = 1.0 - progress;
        }
      }
      
      // Clamp progress
      progress = progress.clamp(0.0, 1.0);
      
      // Apply easing
      final easedProgress = _applyEasing(progress, animation.easing, animation.curve);
      
      // Calculate current values
      animation.previousValues = Map.from(animation.currentValues);
      
      for (final property in animation.to.keys) {
        final fromValue = animation.from[property] ?? 0.0;
        final toValue = animation.to[property] ?? 0.0;
        
        if (fromValue is num && toValue is num) {
          final currentValue = fromValue + (toValue - fromValue) * easedProgress;
          animation.currentValues[property] = currentValue;
        } else if (fromValue is List && toValue is List) {
          final fromList = fromValue as List;
          final toList = toValue as List;
          final currentList = <dynamic>[];
          
          for (int i = 0; i < fromList.length && i < toList.length; i++) {
            final fromItem = fromList[i];
            final toItem = toList[i];
            
            if (fromItem is num && toItem is num) {
              final currentItem = fromItem + (toItem - fromItem) * easedProgress;
              currentList.add(currentItem);
            } else {
              currentList.add(easedProgress > 0.5 ? toItem : fromItem);
            }
          }
          
          animation.currentValues[property] = currentList;
        }
      }
      
      animation.currentTime = progress;
      
      // Call update callback
      if (animation.onUpdate != null) {
        try {
          animation.onUpdate!(easedProgress);
        } catch (e) {
          developer.log('🎬 Animation update callback error: $e');
        }
      }
      
      // Check completion
      if (progress >= 1.0 && !animation.repeat) {
        animation.isCompleted = true;
        animation.isRunning = false;
        animationsToRemove.add(animationId);
        
        if (animation.onComplete != null) {
          try {
            animation.onComplete!();
          } catch (e) {
            developer.log('🎬 Animation complete callback error: $e');
          }
        }
        
        _emitEvent(AnimationEvent(
          type: AnimationEventType.completed,
          animationId: animationId,
          targetId: animation.targetId,
          animationType: animation.type,
        ));
      }
    }
    
    // Remove completed animations
    for (final animationId in animationsToRemove) {
      _activeAnimations.remove(animationId);
    }
    
    // Process queued animations
    _processQueuedAnimations();
    
    // Update FPS
    _updateFPS();
  }

  double _applyEasing(double progress, EasingType easing, Curve curve) {
    switch (easing) {
      case EasingType.linear:
        return progress;
      case EasingType.easeIn:
        return curve.transform(progress);
      case EasingType.easeOut:
        return curve.transform(progress);
      case EasingType.easeInOut:
        return curve.transform(progress);
      case EasingType.easeInBack:
        return Curves.easeInBack.transform(progress);
      case EasingType.easeOutBack:
        return Curves.easeOutBack.transform(progress);
      case EasingType.easeInOutBack:
        return Curves.easeInOutBack.transform(progress);
      case EasingType.easeInCubic:
        return Curves.easeInCubic.transform(progress);
      case EasingType.easeOutCubic:
        return Curves.easeOutCubic.transform(progress);
      case EasingType.easeInOutCubic:
        return Curves.easeInOutCubic.transform(progress);
      case EasingType.elasticIn:
        return Curves.elasticIn.transform(progress);
      case EasingType.elasticOut:
        return Curves.elasticOut.transform(progress);
      case EasingType.elasticInOut:
        return Curves.elasticInOut.transform(progress);
      case EasingType.bounceIn:
        return Curves.bounceIn.transform(progress);
      case EasingType.bounceOut:
        return Curves.bounceOut.transform(progress);
      case EasingType.bounceInOut:
        return Curves.bounceInOut.transform(progress);
    }
  }

  void _processQueuedAnimations() {
    while (_animationQueue.isNotEmpty && _activeAnimations.length < _maxConcurrentAnimations) {
      final request = _animationQueue.removeFirst();
      
      // Execute queued animation
      animate(
        targetId: request.targetId,
        type: request.type,
        from: request.from,
        to: request.to,
        profileId: request.profileId,
        duration: request.duration,
        easing: request.easing,
        repeat: request.repeat,
        autoReverse: request.autoReverse,
        onUpdate: request.onUpdate,
        onComplete: request.onComplete,
        onCancel: request.onCancel,
      );
      
      _emitEvent(AnimationEvent(
        type: AnimationEventType.dequeued,
        animationId: request.id,
        targetId: request.targetId,
        animationType: request.type,
      ));
    }
  }

  int _frameCount = 0;
  DateTime _lastFPSUpdate = DateTime.now();

  void _updateFPS() {
    
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFPSUpdate).inMilliseconds;
    
    if (elapsed >= 1000) { // Update every second
      _currentFPS = _frameCount * 1000.0 / elapsed;
      _frameCount = 0;
      _lastFPSUpdate = now;
    }
  }

  void pauseAnimation(String animationId) {
    final animation = _activeAnimations[animationId];
    if (animation == null) {
      throw Exception('Animation not found: $animationId');
    }
    
    animation.isPaused = true;
    
    developer.log('🎬 Paused animation: $animationId');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.paused,
      animationId: animationId,
      targetId: animation.targetId,
    ));
  }

  void resumeAnimation(String animationId) {
    final animation = _activeAnimations[animationId];
    if (animation == null) {
      throw Exception('Animation not found: $animationId');
    }
    
    animation.isPaused = false;
    animation.startTime = DateTime.now().subtract(Duration(
      microseconds: (animation.currentTime * animation.duration.inMicroseconds).round(),
    ));
    
    developer.log('🎬 Resumed animation: $animationId');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.resumed,
      animationId: animationId,
      targetId: animation.targetId,
    ));
  }

  void cancelAnimation(String animationId) {
    final animation = _activeAnimations.remove(animationId);
    if (animation == null) {
      throw Exception('Animation not found: $animationId');
    }
    
    animation.isCancelled = true;
    animation.isRunning = false;
    
    if (animation.onCancel != null) {
      try {
        animation.onCancel!();
      } catch (e) {
        developer.log('🎬 Animation cancel callback error: $e');
      }
    }
    
    developer.log('🎬 Cancelled animation: $animationId');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.cancelled,
      animationId: animationId,
      targetId: animation.targetId,
    ));
  }

  void cancelAllAnimations({String? targetId}) {
    final animationsToRemove = <String>[];
    
    for (final entry in _activeAnimations.entries) {
      if (targetId != null && entry.value.targetId != targetId) {
        continue;
      }
      
      animationsToRemove.add(entry.key);
      
      final animation = entry.value;
      animation.isCancelled = true;
      animation.isRunning = false;
      
      if (animation.onCancel != null) {
        try {
          animation.onCancel!();
        } catch (e) {
          developer.log('🎬 Animation cancel callback error: $e');
        }
      }
    }
    
    for (final animationId in animationsToRemove) {
      _activeAnimations.remove(animationId);
    }
    
    developer.log('🎬 Cancelled ${animationsToRemove.length} animations');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.allCancelled,
      targetId: targetId,
      count: animationsToRemove.length,
    ));
  }

  String createProfile({
    required String name,
    required Duration duration,
    required EasingType easing,
    bool repeat = false,
    bool autoReverse = false,
    Curve? curve,
  }) {
    final profileId = _generateProfileId();
    
    final profile = AnimationProfile(
      id: profileId,
      name: name,
      duration: duration,
      easing: easing,
      curve: curve ?? _getDefaultCurve(easing),
      repeat: repeat,
      autoReverse: autoReverse,
    );
    
    _profiles[profileId] = profile;
    
    developer.log('🎬 Created animation profile: $name');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.profileCreated,
      profileId: profileId,
      profileName: name,
    ));
    
    return profileId;
  }

  Curve _getDefaultCurve(EasingType easing) {
    switch (easing) {
      case EasingType.linear:
        return Curves.linear;
      case EasingType.easeIn:
        return Curves.easeIn;
      case EasingType.easeOut:
        return Curves.easeOut;
      case EasingType.easeInOut:
        return Curves.easeInOut;
      case EasingType.easeInBack:
        return Curves.easeInBack;
      case EasingType.easeOutBack:
        return Curves.easeOutBack;
      case EasingType.easeInOutBack:
        return Curves.easeInOutBack;
      case EasingType.easeInCubic:
        return Curves.easeInCubic;
      case EasingType.easeOutCubic:
        return Curves.easeOutCubic;
      case EasingType.easeInOutCubic:
        return Curves.easeInOutCubic;
      case EasingType.elasticIn:
        return Curves.elasticIn;
      case EasingType.elasticOut:
        return Curves.elasticOut;
      case EasingType.elasticInOut:
        return Curves.elasticInOut;
      case EasingType.bounceIn:
        return Curves.bounceIn;
      case EasingType.bounceOut:
        return Curves.bounceOut;
      case EasingType.bounceInOut:
        return Curves.bounceInOut;
    }
  }

  void deleteProfile(String profileId) {
    final profile = _profiles.remove(profileId);
    if (profile == null) {
      throw Exception('Animation profile not found: $profileId');
    }
    
    developer.log('🎬 Deleted animation profile: ${profile.name}');
    
    _emitEvent(AnimationEvent(
      type: AnimationEventType.profileDeleted,
      profileId: profileId,
      profileName: profile.name,
    ));
  }

  AnimationProfile? getProfile(String profileId) {
    return _profiles[profileId];
  }

  List<AnimationProfile> getProfiles() {
    return _profiles.values.toList();
  }

  Animation? getAnimation(String animationId) {
    return _activeAnimations[animationId];
  }

  List<Animation> getActiveAnimations({String? targetId}) {
    final animations = _activeAnimations.values.toList();
    
    if (targetId != null) {
      return animations.where((anim) => anim.targetId == targetId).toList();
    }
    
    return animations;
  }

  List<AnimationRequest> getQueuedAnimations() {
    return _animationQueue.toList();
  }

  Future<void> preloadAnimation({
    required String targetId,
    required AnimationType type,
    Map<String, dynamic>? from,
    Map<String, dynamic>? to,
    String? profileId,
  }) async {
    // Pre-calculate animation frames for smoother playback
    final profile = _getProfile(profileId ?? 'default');
    final duration = profile.duration.inMicroseconds.toDouble();
    final frames = <AnimationFrame>[];
    
    const frameCount = 60; // Pre-calculate 60 frames
    for (int i = 0; i <= frameCount; i++) {
      final progress = i / frameCount;
      final easedProgress = _applyEasing(progress, profile.easing, profile.curve);
      
      final frameValues = <String, dynamic>{};
      
      for (final property in (to ?? {}).keys) {
        final fromValue = (from ?? {})[property] ?? 0.0;
        final toValue = to![property] ?? 0.0;
        
        if (fromValue is num && toValue is num) {
          final currentValue = fromValue + (toValue - fromValue) * easedProgress;
          frameValues[property] = currentValue;
        }
      }
      
      frames.add(AnimationFrame(
        progress: progress,
        values: frameValues,
      ));
    }
    
    _frameCache['${targetId}_${type.name}'] = frames;
    
    developer.log('🎬 Preloaded animation frames: ${targetId}_${type.name}');
  }

  List<AnimationFrame>? getPreloadedFrames(String targetId, AnimationType type) {
    return _frameCache['${targetId}_${type.name}'];
  }

  void setGlobalAnimationSettings({
    double? maxFPS,
    int? maxConcurrentAnimations,
    bool? enablePreloading,
    bool? enableFrameSkipping,
  }) {
    if (maxFPS != null) {
      // Adjust animation timer for target FPS
      final interval = (1000.0 / maxFPS!).round();
      _animationTimer?.cancel();
      _animationTimer = Timer.periodic(
        Duration(milliseconds: interval),
        (_) => _updateAnimations(),
      );
    }
    
    if (enablePreloading != null && enablePreloading!) {
      // Enable preloading for common animations
      _preloadCommonAnimations();
    }
    
    developer.log('🎬 Updated global animation settings');
  }

  void _preloadCommonAnimations() {
    // Preload common animation combinations
    final commonAnimations = [
      {'type': AnimationType.fade, 'profile': 'fade'},
      {'type': AnimationType.slide, 'profile': 'slide'},
      {'type': AnimationType.scale, 'profile': 'scale'},
    ];
    
    for (final anim in commonAnimations) {
      preloadAnimation(
        targetId: 'common',
        type: anim['type'] as AnimationType,
        profileId: anim['profile'] as String?,
        from: {'opacity': 0.0},
        to: {'opacity': 1.0},
      );
    }
  }

  String _generateAnimationId() {
    return 'anim_${DateTime.now().millisecondsSinceEpoch}_$_totalAnimations';
  }

  String _generateRequestId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generateProfileId() {
    return 'profile_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _emitEvent(AnimationEvent event) {
    _animationController.add(event);
  }

  Stream<AnimationEvent> get animationEventStream => _animationController.stream;

  AnimationStats getStats() {
    return AnimationStats(
      totalAnimations: _totalAnimations,
      activeAnimations: _activeAnimations.length,
      queuedAnimations: _animationQueue.length,
      currentFPS: _currentFPS,
      droppedFrames: _droppedFrames,
      preloadedFrames: _frameCache.values.fold(0, (sum, frames) => sum + frames.length),
    );
  }

  void dispose() {
    _animationTimer?.cancel();
    
    // Cancel all active animations
    cancelAllAnimations();
    
    _activeAnimations.clear();
    _animationQueue.clear();
    _profiles.clear();
    _frameCache.clear();
    _animationController.close();
    
    developer.log('🎬 Smooth Animations disposed');
  }
}

class Animation {
  final String id;
  final String targetId;
  final AnimationType type;
  final Map<String, dynamic> from;
  final Map<String, dynamic> to;
  final AnimationProfile profile;
  final Duration duration;
  final EasingType easing;
  final Curve curve;
  final bool repeat;
  final bool autoReverse;
  final Function(double)? onUpdate;
  final Function()? onComplete;
  final Function()? onCancel;
  
  DateTime startTime;
  double currentTime;
  bool isRunning;
  bool isPaused;
  bool isCompleted;
  bool isCancelled;
  Map<String, dynamic> currentValues;
  Map<String, dynamic> previousValues;

  Animation({
    required this.id,
    required this.targetId,
    required this.type,
    required this.from,
    required this.to,
    required this.profile,
    required this.duration,
    required this.easing,
    required this.curve,
    required this.repeat,
    required this.autoReverse,
    this.onUpdate,
    this.onComplete,
    this.onCancel,
    required this.startTime,
    required this.currentTime,
    required this.isRunning,
    required this.isPaused,
    required this.isCompleted,
    required this.isCancelled,
    required this.currentValues,
    required this.previousValues,
  });
}

class AnimationProfile {
  final String id;
  final String name;
  final Duration duration;
  final EasingType easing;
  final Curve curve;
  final bool repeat;
  final bool autoReverse;

  AnimationProfile({
    required this.id,
    required this.name,
    required this.duration,
    required this.easing,
    required this.curve,
    required this.repeat,
    required this.autoReverse,
  });
}

class AnimationRequest {
  final String id;
  final String targetId;
  final AnimationType type;
  final Map<String, dynamic> from;
  final Map<String, dynamic> to;
  final String profileId;
  final Duration? duration;
  final EasingType? easing;
  final bool repeat;
  final bool autoReverse;
  final Function(double)? onUpdate;
  final Function()? onComplete;
  final Function()? onCancel;
  final DateTime timestamp;

  AnimationRequest({
    required this.id,
    required this.targetId,
    required this.type,
    required this.from,
    required this.to,
    required this.profileId,
    this.duration,
    this.easing,
    required this.repeat,
    required this.autoReverse,
    this.onUpdate,
    this.onComplete,
    this.onCancel,
    required this.timestamp,
  });
}

class AnimationFrame {
  final double progress;
  final Map<String, dynamic> values;

  AnimationFrame({
    required this.progress,
    required this.values,
  });
}

enum AnimationType {
  fade,
  slide,
  scale,
  rotate,
  bounce,
  shake,
  pulse,
  custom,
}

enum EasingType {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  easeInBack,
  easeOutBack,
  easeInOutBack,
  easeInCubic,
  easeOutCubic,
  easeInOutCubic,
  elasticIn,
  elasticOut,
  elasticInOut,
  bounceIn,
  bounceOut,
  bounceInOut,
}

enum AnimationEventType {
  started,
  completed,
  cancelled,
  paused,
  resumed,
  queued,
  dequeued,
  allCancelled,
  profileCreated,
  profileDeleted,
}

class AnimationEvent {
  final AnimationEventType type;
  final String? animationId;
  final String? targetId;
  final AnimationType? animationType;
  final String? profileId;
  final String? profileName;
  final int? count;

  AnimationEvent({
    required this.type,
    this.animationId,
    this.targetId,
    this.animationType,
    this.profileId,
    this.profileName,
    this.count,
  });
}

class AnimationStats {
  final int totalAnimations;
  final int activeAnimations;
  final int queuedAnimations;
  final double currentFPS;
  final int droppedFrames;
  final int preloadedFrames;

  AnimationStats({
    required this.totalAnimations,
    required this.activeAnimations,
    required this.queuedAnimations,
    required this.currentFPS,
    required this.droppedFrames,
    required this.preloadedFrames,
  });
}
