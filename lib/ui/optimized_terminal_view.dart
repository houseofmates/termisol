import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../core/terminal_session.dart';
import '../core/production_gpu_renderer.dart';
import '../core/sub_16ms_latency_optimizer.dart';
import '../core/memory_optimizer.dart';
import '../config/production_config_system.dart';
import '../config/pkm_theme.dart';
import 'clipboard_manager.dart';

/// Production-optimized terminal view with GPU acceleration
/// 
/// Integrates:
/// - Hardware-accelerated rendering
/// - Sub-16ms latency optimization
/// - Adaptive performance scaling
/// - Configuration-driven behavior
class OptimizedTerminalView extends StatefulWidget {
  final TerminalSession session;
  final ProductionGpuRenderer gpuRenderer;
  final Sub16msLatencyOptimizer latencyOptimizer;
  final ProductionConfigSystem configSystem;
  final bool autofocus;

  const OptimizedTerminalView({
    super.key,
    required this.session,
    required this.gpuRenderer,
    required this.latencyOptimizer,
    required this.configSystem,
    this.autofocus = true,
  });

  @override
  State<OptimizedTerminalView> createState() => _OptimizedTerminalViewState();
}

class _OptimizedTerminalViewState extends State<OptimizedTerminalView> 
    with WidgetsBindingObserver {
  late final TerminalClipboardManager _clipboard;
  late final FocusNode _focusNode;
  late final StreamSubscription _configSubscription;
  late final MemoryOptimizer _memoryOptimizer;
  late final WidgetMemoryManager _widgetManager;
  
  // Performance optimization
  bool _isHighPerformance = true;
  double _renderQuality = 1.0;
  Timer? _performanceTimer;
  
  // Rendering optimization
  final GlobalKey _terminalKey = GlobalKey();
  ui.PictureRecorder? _recorder;
  ui.Canvas? _canvas;
  bool _needsFullRedraw = true;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize memory optimization
    _memoryOptimizer = MemoryOptimizer();
    _memoryOptimizer.initialize();
    _widgetManager = WidgetMemoryManager(_memoryOptimizer);
    
    _clipboard = TerminalClipboardManager(
      widget.session.terminal,
      widget.session.controller,
    );
    _focusNode = FocusNode();
    
    // Register for memory tracking
    _widgetManager.registerWidget('terminal_view', widget);
    
    // Setup performance monitoring
    _setupPerformanceMonitoring();
    
    // Setup configuration changes
    _configSubscription = widget.configSystem.configChanges.listen(_onConfigChanged);
    
    widget.session.addListener(_onSessionChanged);
    
    // Initialize GPU renderer for this view
    widget.gpuRenderer.markAllDirty();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSessionChanged);
    _configSubscription.cancel();
    _performanceTimer?.cancel();
    _focusNode.dispose();
    _recorder = null; // Don't dispose PictureRecorder
    
    // Cleanup memory optimization
    _widgetManager.dispose();
    _memoryOptimizer.dispose();
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Reduce performance when app is backgrounded
        _setPerformanceMode(false);
        break;
      case AppLifecycleState.resumed:
        // Restore high performance when app is active
        _setPerformanceMode(true);
        break;
      default:
        break;
    }
  }

  void _setupPerformanceMonitoring() {
    _performanceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updatePerformanceMode();
      }
    });
  }

  void _updatePerformanceMode() {
    final frameTime = widget.latencyOptimizer.averageFrameTime;
    final targetFps = widget.latencyOptimizer.currentTargetFps;
    
    // Adaptive performance based on frame times
    if (frameTime > 20.0) { // Struggling to maintain 50fps
      _isHighPerformance = false;
      _renderQuality = widget.latencyOptimizer.recommendedRenderQuality;
    } else if (frameTime < 12.0) { // Easily maintaining 80fps+
      _isHighPerformance = true;
      _renderQuality = 1.0;
    }
    
    if (mounted) setState(() {});
  }

  void _setPerformanceMode(bool highPerformance) {
    _isHighPerformance = highPerformance;
    widget.latencyOptimizer.setAdaptiveMode(highPerformance);
    
    if (mounted) setState(() {});
  }

  void _onConfigChanged(TermisolConfig newConfig) {
    if (mounted) {
      setState(() {
        // Apply configuration changes
        _needsFullRedraw = true;
      });
    }
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {
        _needsFullRedraw = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.configSystem.performance;
    
    return RepaintBoundary(
      child: Container(
        color: PkmTheme.terminalBg,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _handleKeyEvent,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                  () => _handleCtrlC(),
              const SingleActivator(
                LogicalKeyboardKey.keyC,
                control: true,
                shift: true,
              ): () => _clipboard.sendSigInt(),
              const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                  () => _handlePaste(),
              const SingleActivator(
                LogicalKeyboardKey.keyV,
                control: true,
                shift: true,
              ): () => _clipboard.pasteBracketed(),
            },
            child: _buildOptimizedTerminal(),
          ),
        ),
      ),
    );
  }

  Widget _buildOptimizedTerminal() {
    final config = widget.configSystem.theme;
    
    if (_isHighPerformance) {
      // High performance mode with GPU acceleration
      return _buildGpuTerminal();
    } else {
      // Battery saving mode with reduced features
      return _buildBatteryTerminal();
    }
  }

  Widget _buildGpuTerminal() {
    final config = widget.configSystem.theme;
    
    return CustomPaint(
      painter: _GpuTerminalPainter(
        terminal: widget.session.terminal,
        controller: widget.session.controller,
        gpuRenderer: widget.gpuRenderer,
        config: config,
        renderQuality: _renderQuality,
        needsFullRedraw: _needsFullRedraw,
        onRedrawComplete: () => _needsFullRedraw = false,
      ),
      child: Container(),
    );
  }

  Widget _buildBatteryTerminal() {
    final config = widget.configSystem.theme;
    
    return TerminalView(
      widget.session.terminal,
      controller: widget.session.controller,
      textStyle: TerminalStyle(
        fontSize: config.fontSize * _renderQuality,
        fontFamily: config.fontFamily,
      ),
      backgroundOpacity: 1.0,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Queue input for latency optimization
    widget.latencyOptimizer.queueInput('keypress', event);
    
    // Handle special keys
    if (event is KeyDownEvent) {
      switch (event.logicalKey.keyLabel) {
        case 'F11':
          _toggleFullscreen();
          return KeyEventResult.handled;
        default:
          break;
      }
    }
    
    return KeyEventResult.ignored;
  }

  Future<void> _handleCtrlC() async {
    if (_clipboard.hasSelection) {
      await _clipboard.copy();
    } else {
      _clipboard.sendSigInt();
    }
  }

  Future<void> _handlePaste() async {
    // Optimize paste operations
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    widget.latencyOptimizer.queueInput('paste', clipboardData?.text ?? '');
    await _clipboard.paste();
  }

  void _toggleFullscreen() {
    // Toggle fullscreen mode
    if (mounted) {
      // Implementation would depend on platform
      debugPrint('Toggle fullscreen requested');
    }
  }
}

/// GPU-accelerated terminal painter
class _GpuTerminalPainter extends CustomPainter {
  final Terminal terminal;
  final TerminalController controller;
  final ProductionGpuRenderer gpuRenderer;
  final ThemeConfig config;
  final double renderQuality;
  final bool needsFullRedraw;
  final VoidCallback onRedrawComplete;

  _GpuTerminalPainter({
    required this.terminal,
    required this.controller,
    required this.gpuRenderer,
    required this.config,
    required this.renderQuality,
    required this.needsFullRedraw,
    required this.onRedrawComplete,
  }) : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    final stopwatch = Stopwatch()..start();
    
    // Begin GPU-optimized render frame
    gpuRenderer.beginFrame(canvas, size);
    
    try {
      // Render terminal buffer with GPU acceleration
      gpuRenderer.renderTerminal(
        terminal,
        _convertTheme(config),
        TerminalStyle(
          fontSize: config.fontSize * renderQuality,
          fontFamily: config.fontFamily,
        ),
      );
    } finally {
      // End frame and record metrics
      gpuRenderer.endFrame();
      stopwatch.stop();
      
      // Record frame time for optimization
      final frameTime = stopwatch.elapsedMicroseconds / 1000.0;
      debugPrint('🎯 GPU frame time: ${frameTime.toStringAsFixed(2)}ms');
    }
    
    onRedrawComplete();
  }

  @override
  bool shouldRepaint(_GpuTerminalPainter oldDelegate) {
    return needsFullRedraw || 
           oldDelegate.renderQuality != renderQuality ||
           oldDelegate.config != config;
  }

  /// Convert theme config to xterm theme
  TerminalTheme _convertTheme(ThemeConfig config) {
    return TerminalTheme(
      foreground: _parseColor(config.foreground),
      background: _parseColor(config.background),
      cursor: _parseColor(config.cursor),
      selection: _parseColor(config.selection),
      black: _parseColor('#000000'),
      red: _parseColor('#ff5252'),
      green: _parseColor('#4caf50'),
      yellow: _parseColor('#ffeb3b'),
      blue: _parseColor('#2196f3'),
      magenta: _parseColor('#9c27b0'),
      cyan: _parseColor('#00bcd4'),
      white: _parseColor('#ffffff'),
      brightBlack: _parseColor('#424242'),
      brightRed: _parseColor('#ff8a80'),
      brightGreen: _parseColor('#81c784'),
      brightYellow: _parseColor('#ffeb3b'),
      brightBlue: _parseColor('#82b1ff'),
      brightMagenta: _parseColor('#ba68c8'),
      brightCyan: _parseColor('#84ffff'),
      brightWhite: _parseColor('#ffffff'),
      searchHitBackground: _parseColor('#ffeb3b'),
      searchHitBackgroundCurrent: _parseColor('#f6b012'),
      searchHitForeground: _parseColor('#000000'),
    );
  }

  /// Parse color string to Color
  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      return Color(int.parse(colorString.substring(1), radix: 16));
    } else if (colorString.startsWith('0x')) {
      return Color(int.parse(colorString.substring(2), radix: 16));
    }
    return Colors.white; // fallback
  }
}
