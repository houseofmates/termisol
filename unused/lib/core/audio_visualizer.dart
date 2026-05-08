import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// Advanced audio visualizer for inline terminal audio playback
/// Supports waveform, frequency bars, and circular visualizations
class AudioVisualizer extends StatefulWidget {
  final String audioPath;
  final VisualizationType type;
  final double? width;
  final double? height;
  final Color primaryColor;
  final Color secondaryColor;
  final bool autoPlay;
  final VoidCallback? onClose;

  const AudioVisualizer({
    super.key,
    required this.audioPath,
    this.type = VisualizationType.bars,
    this.width,
    this.height = 200,
    this.primaryColor = Colors.blue,
    this.secondaryColor = Colors.cyan,
    this.autoPlay = false,
    this.onClose,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with TickerProviderStateMixin {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0;
  
  // Animation controllers
  late AnimationController _animationController;
  late AnimationController _pulseController;
  
  // Visualization data
  final List<double> _frequencyData = List.filled(64, 0.0);
  final List<double> _waveformData = List.filled(128, 0.0);
  Timer? _visualizationTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _initializeAudio();
  }

  Future<void> _initializeAudio() async {
    try {
      _audioPlayer = AudioPlayer();
      
      // Set up audio session
      await _audioPlayer!.setPlayerMode(PlayerMode.lowLatency);
      
      // Listen to duration changes
      _audioPlayer!.onDurationChanged.listen((duration) {
        setState(() {
          _duration = duration;
        });
      });
      
      // Listen to position changes
      _audioPlayer!.onPositionChanged.listen((position) {
        setState(() {
          _position = position;
        });
      });
      
      // Listen to player state changes
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        
        if (_isPlaying) {
          _startVisualization();
          _pulseController.repeat(reverse: true);
        } else {
          _stopVisualization();
          _pulseController.stop();
        }
      });
      
      // Load the audio file
      if (widget.audioPath.startsWith('http')) {
        await _audioPlayer!.setSource(UrlSource(widget.audioPath));
      } else {
        await _audioPlayer!.setSource(DeviceFileSource(widget.audioPath));
      }
      
      setState(() {
        _isLoading = false;
      });
      
      if (widget.autoPlay) {
        await _audioPlayer!.resume();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Failed to initialize audio: $e');
    }
  }

  void _startVisualization() {
    _visualizationTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isPlaying && mounted) {
        _generateVisualizationData();
        setState(() {});
      }
    });
  }

  void _stopVisualization() {
    _visualizationTimer?.cancel();
    _visualizationTimer = null;
  }

  void _generateVisualizationData() {
    final random = math.Random();
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;
    
    // Generate simulated frequency data
    for (int i = 0; i < _frequencyData.length; i++) {
      final baseValue = math.sin(time * 2 + i * 0.1) * 0.5 + 0.5;
      final noise = random.nextDouble() * 0.3;
      _frequencyData[i] = (baseValue + noise) * (_isPlaying ? 1.0 : 0.1);
    }
    
    // Generate simulated waveform data
    for (int i = 0; i < _waveformData.length; i++) {
      final phase = (i / _waveformData.length) * 2 * math.pi;
      final amplitude = math.sin(time * 4 + phase) * 0.5 + 0.5;
      _waveformData[i] = amplitude * (_isPlaying ? 1.0 : 0.1);
    }
  }

  @override
  void dispose() {
    _stopVisualization();
    _audioPlayer?.dispose();
    _animationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_audioPlayer == null) return;
    
    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.resume();
    }
  }

  Future<void> _seekTo(Duration position) async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.seek(position);
  }

  Future<void> _changeVolume(double volume) async {
    if (_audioPlayer == null) return;
    await _audioPlayer!.setVolume(volume);
    setState(() {
      _volume = volume;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width ?? double.infinity,
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 8),
              Text(
                'Loading audio...',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: widget.width ?? double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Visualization area
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: _buildVisualization(),
            ),
          ),
          
          // Audio controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Column(
              children: [
                // Progress bar
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    max: _duration.inMilliseconds.toDouble().clamp(0.0, double.infinity),
                    onChanged: (value) {
                      _seekTo(Duration(milliseconds: value.round()));
                    },
                    activeColor: widget.primaryColor,
                    inactiveColor: Colors.grey[600],
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Control buttons
                Row(
                  children: [
                    // Play/Pause button
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isPlaying ? 1.0 + _pulseController.value * 0.1 : 1.0,
                          child: IconButton(
                            onPressed: _togglePlayPause,
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: widget.primaryColor,
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                    
                    // Volume control
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.volume_up, color: widget.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                                trackHeight: 2,
                              ),
                              child: Slider(
                                value: _volume,
                                min: 0.0,
                                max: 1.0,
                                onChanged: _changeVolume,
                                activeColor: widget.primaryColor,
                                inactiveColor: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Time display
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Close button
                    if (widget.onClose != null)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualization() {
    switch (widget.type) {
      case VisualizationType.bars:
        return _buildBarsVisualization();
      case VisualizationType.waveform:
        return _buildWaveformVisualization();
      case VisualizationType.circular:
        return _buildCircularVisualization();
      case VisualizationType.spectrum:
        return _buildSpectrumVisualization();
    }
  }

  Widget _buildBarsVisualization() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(_frequencyData.length, (index) {
        final height = _frequencyData[index] * (widget.height ?? 200 - 32);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          width: 4,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                widget.primaryColor,
                widget.secondaryColor,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildWaveformVisualization() {
    return CustomPaint(
      size: Size(
        widget.width ?? double.infinity,
        (widget.height ?? 200) - 32,
      ),
      painter: WaveformPainter(
        _waveformData,
        widget.primaryColor,
        widget.secondaryColor,
      ),
    );
  }

  Widget _buildCircularVisualization() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _animationController.value * 2 * math.pi,
          child: CustomPaint(
            size: Size(
              widget.width ?? double.infinity,
              (widget.height ?? 200) - 32,
            ),
            painter: CircularVisualizationPainter(
              _frequencyData,
              widget.primaryColor,
              widget.secondaryColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpectrumVisualization() {
    return CustomPaint(
      size: Size(
        widget.width ?? double.infinity,
        (widget.height ?? 200) - 32,
      ),
      painter: SpectrumPainter(
        _frequencyData,
        widget.primaryColor,
        widget.secondaryColor,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }
}

enum VisualizationType {
  bars,
  waveform,
  circular,
  spectrum,
}

class WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color primaryColor;
  final Color secondaryColor;

  WaveformPainter(this.data, this.primaryColor, this.secondaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;
    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = centerY + (data[i] - 0.5) * size.height * 0.8;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CircularVisualizationPainter extends CustomPainter {
  final List<double> data;
  final Color primaryColor;
  final Color secondaryColor;

  CircularVisualizationPainter(this.data, this.primaryColor, this.secondaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 3;

    for (int i = 0; i < data.length; i++) {
      final angle = (i / data.length) * 2 * math.pi;
      final barHeight = data[i] * radius;
      
      final startOffset = Offset(
        center.dx + math.cos(angle) * radius * 0.5,
        center.dy + math.sin(angle) * radius * 0.5,
      );
      
      final endOffset = Offset(
        center.dx + math.cos(angle) * (radius * 0.5 + barHeight),
        center.dy + math.sin(angle) * (radius * 0.5 + barHeight),
      );

      final paint = Paint()
        ..color = primaryColor.withOpacity(0.8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(startOffset, endOffset, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SpectrumPainter extends CustomPainter {
  final List<double> data;
  final Color primaryColor;
  final Color secondaryColor;

  SpectrumPainter(this.data, this.primaryColor, this.secondaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / data.length;
    
    for (int i = 0; i < data.length; i++) {
      final height = data[i] * size.height;
      final x = i * barWidth;
      
      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          primaryColor,
          secondaryColor.withOpacity(0.3),
        ],
      );
      
      final paint = Paint()
        ..shader = gradient.createShader(
          Rect.fromLTWH(x, size.height - height, barWidth, height),
        );

      canvas.drawRect(
        Rect.fromLTWH(x, size.height - height, barWidth - 1, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
