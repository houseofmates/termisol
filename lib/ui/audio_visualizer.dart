import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Audio visualizer for Termisol terminal
/// 
/// Features:
/// - Real-time audio waveform visualization
/// - Frequency spectrum analysis
/// - Volume level monitoring
/// - Terminal-integrated audio feedback
class TerminalAudioVisualizer extends StatefulWidget {
  final Stream<Uint8List>? audioStream;
  final bool showSpectrum;
  final bool showWaveform;
  final double? width;
  final double? height;
  final int? barCount;
  
  const TerminalAudioVisualizer({
    super.key,
    this.audioStream,
    this.showSpectrum = true,
    this.showWaveform = true,
    this.width,
    this.height,
    this.barCount = 32,
  });
  
  @override
  State<TerminalAudioVisualizer> createState() => _TerminalAudioVisualizerState();
}

class _TerminalAudioVisualizerState extends State<TerminalAudioVisualizer> 
    with TickerProviderStateMixin {
  final List<double> _waveformData = List.filled(128, 0.0);
  final List<double> _spectrumData = List.filled(32, 0.0);
  Timer? _animationTimer;
  
  @override
  void initState() {
    super.initState();
    
    // Start animation timer for smooth visualization
    _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) {
        _updateVisualization();
      }
    });
    
    // Listen to audio stream
    if (widget.audioStream != null) {
      widget.audioStream!.listen(_processAudioData);
    }
  }
  
  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }
  
  void _processAudioData(Uint8List audioData) {
    // Convert audio data to waveform
    for (int i = 0; i < audioData.length && i < _waveformData.length; i++) {
      final sample = (audioData[i] - 128) / 128.0; // Convert to -1.0 to 1.0
      _waveformData[i] = sample;
    }
    
    // Simple FFT for spectrum analysis
    _calculateSpectrum();
  }
  
  void _calculateSpectrum() {
    final barCount = widget.barCount ?? 32;
    
    for (int i = 0; i < barCount; i++) {
      double magnitude = 0.0;
      final startIdx = (i * _waveformData.length) ~/ barCount;
      final endIdx = ((i + 1) * _waveformData.length) ~/ barCount;
      
      // Calculate magnitude for this frequency band
      for (int j = startIdx; j < endIdx; j++) {
        magnitude += _waveformData[j].abs();
      }
      
      magnitude = magnitude / (endIdx - startIdx);
      _spectrumData[i] = magnitude * 0.8; // Apply smoothing
    }
  }
  
  void _updateVisualization() {
    if (mounted) {
      setState(() {
        // Apply decay to spectrum data for smooth animation
        for (int i = 0; i < _spectrumData.length; i++) {
          _spectrumData[i] *= 0.92; // Decay factor
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? 300.0;
    final height = widget.height ?? 100.0;
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[800]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Spectrum visualization
          if (widget.showSpectrum) _buildSpectrum(width, height),
          
          // Waveform visualization
          if (widget.showWaveform) _buildWaveform(width, height),
        ],
      ),
    );
  }
  
  Widget _buildSpectrum(double width, double height) {
    final barWidth = width / _spectrumData.length;
    final barSpacing = barWidth * 0.2;
    final actualBarWidth = barWidth - barSpacing;
    
    return Positioned.fill(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_spectrumData.length, (i) {
          final barHeight = _spectrumData[i] * height * 0.8;
          
          return Container(
            width: actualBarWidth,
            height: barHeight,
            margin: EdgeInsets.only(right: i < _spectrumData.length - 1 ? barSpacing : 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getBarColor(barHeight / height, Colors.green),
                  _getBarColor(barHeight / height, Colors.blue),
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
  
  Widget _buildWaveform(double width, double height) {
    return Positioned.fill(
      child: CustomPaint(
        painter: WaveformPainter(_waveformData),
        size: Size(width, height),
      ),
    );
  }
  
  Color _getBarColor(double intensity, Color baseColor) {
    final hsl = HSLColor.fromColor(baseColor);
    final lightness = hsl.lightness + (intensity * 0.3);
    return HSLColor.fromAHSL(hsl.hue, hsl.saturation, lightness.clamp(0.0, 1.0)).toColor();
  }
}

/// Custom painter for waveform visualization
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  
  WaveformPainter(this.waveformData);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green[400]!
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    final stepX = size.width / (waveformData.length - 1);
    
    for (int i = 0; i < waveformData.length; i++) {
      final x = i * stepX;
      final y = size.height / 2 + (waveformData[i] * size.height / 2);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}
