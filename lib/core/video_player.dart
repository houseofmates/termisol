import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

/// Advanced video player for inline terminal video playback
/// Supports MP4, WebM, AVI, MOV, and other formats
class InlineVideoPlayer extends StatefulWidget {
  final String videoPath;
  final double? width;
  final double? height;
  final bool autoPlay;
  final bool showControls;
  final VoidCallback? onClose;

  const InlineVideoPlayer({
    super.key,
    required this.videoPath,
    this.width,
    this.height,
    this.autoPlay = false,
    this.showControls = true,
    this.onClose,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isLoading = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      if (File(widget.videoPath).existsSync()) {
        _controller = VideoPlayerController.file(File(widget.videoPath));
      } else {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoPath));
      }

      await _controller!.initialize();
      
      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _duration = _controller!.value.duration;
      });

      _controller!.addListener(_videoListener);
      
      if (widget.autoPlay) {
        _controller!.play();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Failed to initialize video: $e');
    }
  }

  void _videoListener() {
    if (_controller == null) return;
    
    final newPosition = _controller!.value.position;
    final isPlaying = _controller!.value.isPlaying;
    
    if (newPosition != _position || isPlaying != _isPlaying) {
      setState(() {
        _position = newPosition;
        _isPlaying = isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    
    setState(() {
      _isPlaying = !_isPlaying;
    });
    
    if (_isPlaying) {
      _controller!.play();
    } else {
      _controller!.pause();
    }
  }

  void _seekTo(Duration position) {
    if (_controller == null || !_isInitialized) return;
    _controller!.seekTo(position);
  }

  void _changeVolume(double volume) {
    if (_controller == null || !_isInitialized) return;
    _controller!.setVolume(volume);
    setState(() {
      _volume = volume;
    });
  }

  void _changePlaybackSpeed(double speed) {
    if (_controller == null || !_isInitialized) return;
    _controller!.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width ?? 400,
        height: widget.height ?? 300,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 8),
              Text(
                'Loading video...',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: widget.width ?? 400,
        height: widget.height ?? 300,
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.red, size: 48),
              SizedBox(height: 8),
              Text(
                'Failed to load video',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final videoWidget = AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );

    if (!widget.showControls) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: videoWidget,
      );
    }

    return Container(
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Video player
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Stack(
              children: [
                videoWidget,
                if (widget.onClose != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                // Center play/pause button
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _togglePlayPause,
                    child: AnimatedOpacity(
                      opacity: _isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.transparent,
                        child: const Center(
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Video controls
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Column(
              children: [
                // Progress bar
                AudioVideoProgressBar(
                  isVideo: true,
                  progress: _position,
                  total: _duration,
                  onSeek: _seekTo,
                  barHeight: 4.0,
                  baseBarColor: Colors.grey[600]!,
                  progressBarColor: Colors.blue,
                  bufferedBarColor: Colors.grey[400]!,
                  thumbColor: Colors.white,
                  thumbRadius: 6.0,
                ),
                
                const SizedBox(height: 8),
                
                // Control buttons
                Row(
                  children: [
                    // Play/Pause button
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    
                    // Volume control
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.volume_up, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                trackHeight: 2,
                              ),
                              child: Slider(
                                value: _volume,
                                min: 0.0,
                                max: 1.0,
                                onChanged: _changeVolume,
                                activeColor: Colors.blue,
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Speed control
                    PopupMenuButton<double>(
                      icon: const Icon(Icons.speed, color: Colors.white, size: 16),
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 0.5, child: Text('0.5x')),
                        const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                        const PopupMenuItem(value: 1.0, child: Text('1x')),
                        const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                        const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                        const PopupMenuItem(value: 2.0, child: Text('2x')),
                      ],
                      onSelected: _changePlaybackSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_playbackSpeed}x',
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Fullscreen button
                    IconButton(
                      onPressed: _toggleFullscreen,
                      icon: const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 16,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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

/// Video player manager for handling multiple video instances
class VideoPlayerManager {
  static final Map<String, InlineVideoPlayer> _activePlayers = {};
  
  static void registerPlayer(String id, InlineVideoPlayer player) {
    _activePlayers[id] = player;
  }
  
  static void unregisterPlayer(String id) {
    _activePlayers.remove(id);
  }
  
  static void pauseAll() {
    for (final player in _activePlayers.values) {
      // Access the state and pause if playing
      if (player.mounted) {
        final state = player.createState();
        if (state._isPlaying) {
          state._togglePlayPause();
        }
      }
    }
  }
  
  static void disposeAll() {
    for (final player in _activePlayers.values) {
      if (player.mounted) {
        player.dispose();
      }
    }
    _activePlayers.clear();
  }
}
