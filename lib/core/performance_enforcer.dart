import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Monitors frame times using Flutter's [Ticker] and provides adaptive
/// performance management.
///
/// When frame times consistently exceed the 16ms budget, it triggers an
/// adaptive reduction flag that the UI can respond to (e.g. by reducing
/// terminal font size or disabling effects).
class PerformanceEnforcer extends ChangeNotifier {
  static const double _targetFrameTimeMs = 16.0;
  static const double _criticalFrameTimeMs = 33.0;
  static const int _historySize = 120;
  static const int _consecutiveCriticalThreshold = 6;

  bool _isRunning = false;
  Ticker? _ticker;
  DateTime? _lastTickTime;

  final List<double> _frameTimeHistory = List.filled(_historySize, 0.0);
  final List<double> _fpsHistory = List.filled(_historySize, 0.0);
  int _historyIndex = 0;

  int _droppedFrames = 0;
  int _criticalFrames = 0;
  int _consecutiveCritical = 0;
  double _currentFps = 0.0;
  double _currentFrameTime = 0.0;
  bool _adaptiveReductionActive = false;

  double get currentFps => _currentFps;
  double get currentFrameTime => _currentFrameTime;
  List<double> get frameTimeHistory => List.unmodifiable(_frameTimeHistory);
  List<double> get fpsHistory => List.unmodifiable(_fpsHistory);
  int get droppedFrames => _droppedFrames;
  int get criticalFrames => _criticalFrames;
  bool get isRunning => _isRunning;
  bool get adaptiveReductionActive => _adaptiveReductionActive;

  final _fpsController = StreamController<double>.broadcast();
  Stream<double> get fpsStream => _fpsController.stream;

  /// Start monitoring frame times via a [Ticker].
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _ticker = Ticker(_onTick);
    _ticker!.start();
    notifyListeners();
  }

  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _ticker?.dispose();
    _ticker = null;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    if (_lastTickTime != null) {
      final frameTimeUs = now.difference(_lastTickTime!).inMicroseconds;
      final frameTimeMs = frameTimeUs / 1000.0;
      _recordFrameTime(frameTimeMs);
    }
    _lastTickTime = now;
  }

  void _recordFrameTime(double frameTimeMs) {
    _currentFrameTime = frameTimeMs;
    _currentFps = frameTimeMs > 0 ? 1000.0 / frameTimeMs : 0.0;

    _frameTimeHistory[_historyIndex] = frameTimeMs;
    _fpsHistory[_historyIndex] = _currentFps;
    _historyIndex = (_historyIndex + 1) % _historySize;

    if (frameTimeMs > _targetFrameTimeMs) {
      _droppedFrames++;
      if (frameTimeMs > _criticalFrameTimeMs) {
        _criticalFrames++;
        _consecutiveCritical++;
        if (_consecutiveCritical >= _consecutiveCriticalThreshold) {
          _triggerAdaptiveReduction();
        }
      } else {
        _consecutiveCritical = 0;
      }
    } else {
      _consecutiveCritical = 0;
      if (_adaptiveReductionActive && _isMeetingTarget) {
        _adaptiveReductionActive = false;
        debugPrint('[PERF] Adaptive reduction deactivated');
        notifyListeners();
      }
    }

    _fpsController.add(_currentFps);
  }

  void _triggerAdaptiveReduction() {
    if (_adaptiveReductionActive) return;
    _adaptiveReductionActive = true;
    debugPrint(
      '[PERF] Adaptive reduction activated: '
      '$_consecutiveCritical consecutive critical frames',
    );
    notifyListeners();
  }

  /// Returns true if the recent average is within the sub-16ms budget.
  bool get _isMeetingTarget {
    if (_frameTimeHistory.every((t) => t == 0.0)) return true;
    final recent = _frameTimeHistory.where((t) => t > 0.0).toList();
    if (recent.isEmpty) return true;
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    return avg <= _targetFrameTimeMs;
  }

  @override
  void dispose() {
    stop();
    _fpsController.close();
    super.dispose();
  }
}
