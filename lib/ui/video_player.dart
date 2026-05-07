import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Inline video player for Termisol terminal
/// 
/// Supports:
/// - Inline video playback in terminal
/// - Multiple video formats
/// - Terminal-integrated controls
/// - Performance optimization
class TerminalVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool showControls;
  final double? width;
  final double? height;
  final VoidCallback? onEnded;
  
  const TerminalVideoPlayer({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
    this.showControls = true,
    this.width,
    this.height,
    this.onEnded,
  });
  
  @override
  State<TerminalVideoPlayer> createState() => _TerminalVideoPlayerState();
}

class _TerminalVideoPlayerState extends State<TerminalVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isLoading = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }
  
  Future<void> _initializeVideo() async {
    try {
      setState(() => _isLoading = true);
      
      // Support multiple video formats
      final uri = Uri.parse(widget.videoUrl);
      _controller = VideoPlayerController.networkUrl(uri);
      
      await _controller!.initialize();
      
      _controller!.addListener(() {
        if (_controller!.value.isInitialized) {
          setState(() {
            _duration = _controller!.value.duration;
            _position = _controller!.value.position;
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      });
      
      if (widget.autoPlay) {
        await _controller!.play();
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load video: $e';
        _isLoading = false;
      });
    }
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
  
  void _togglePlayPause() async {
    if (_controller == null) return;
    
    if (_isPlaying) {
      await _controller!.pause();
    } else {
      await _controller!.play();
    }
  }
  
  void _seekToStart() async {
    if (_controller == null) return;
    await _controller!.seekTo(Duration.zero);
  }
  
  void _handleVideoEnd() {
    widget.onEnded?.call();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        width: widget.width ?? 400,
        height: widget.height ?? 225,
        decoration: BoxDecoration(
          color: Colors.red[900],
          border: Border.all(color: Colors.red[700]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    if (_isLoading) {
      return Container(
        width: widget.width ?? 400,
        height: widget.height ?? 225,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          border: Border.all(color: Colors.grey[700]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.grey[400]),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video player
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          
          // Controls
          if (widget.showControls) _buildControls(),
          
          // Progress bar
          _buildProgressBar(),
        ],
      ),
    );
  }
  
  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        border: Border(top: BorderSide(color: Colors.grey[700]!)),
      ),
      child: Row(
        children: [
          // Play/Pause button
          IconButton(
            onPressed: _togglePlayPause,
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 20,
            ),
            iconSize: 20,
          ),
          
          const SizedBox(width: 8),
          
          // Restart button
          IconButton(
            onPressed: _seekToStart,
            icon: const Icon(Icons.replay, color: Colors.white, size: 20),
            iconSize: 20,
          ),
          
          const SizedBox(width: 8),
          
          // Time display
          Expanded(
            child: Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressBar() {
    if (_duration.inMilliseconds == 0) return const SizedBox.shrink();
    
    final progress = _position.inMilliseconds / _duration.inMilliseconds;
    
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[800],
      ),
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0.0, 1.0),
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue[600],
            gradient: LinearGradient(
              colors: [Colors.blue[400]!, Colors.blue[600]!],
            ),
          ),
        ),
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
