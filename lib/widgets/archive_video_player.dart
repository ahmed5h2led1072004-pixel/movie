import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class ArchiveVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String title;
  final VideoPlayerController? controller; // Injectable for tests
  final VoidCallback? onClose;

  const ArchiveVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.title,
    this.controller,
    this.onClose,
  });

  @override
  State<ArchiveVideoPlayer> createState() => _ArchiveVideoPlayerState();
}

class _ArchiveVideoPlayerState extends State<ArchiveVideoPlayer> {
  static const Color _yellow = Color(0xFFFFC400);

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _initTimer;
  int _initToken = 0;
  Duration _lastPosition = Duration.zero;

  static const Duration _initializeTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer({bool restart = false}) async {
    final token = ++_initToken;
    _initTimer?.cancel();
    _hideTimer?.cancel();

    final previousPosition = _lastPosition;
    if (restart && widget.controller == null && _controller != null) {
      final previous = _controller;
      _controller = null;
      previous?.removeListener(_onControllerUpdate);
      // Release the old controller without blocking the fresh attempt; a
      // wedged platform dispose must not prevent retry from starting.
      unawaited(previous?.dispose());
    }

    if (!mounted) return;
    setState(() {
      _hasError = false;
      _isInitialized = false;
      _errorMessage = '';
      _showControls = true;
    });

    try {
      final controller = widget.controller ??
          VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      _controller = controller;

      _initTimer = Timer(_initializeTimeout, () {
        if (!mounted || token != _initToken || _isInitialized) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Timed out while opening the video stream. '
              'Check your connection and retry.';
        });
      });

      await controller.initialize().timeout(_initializeTimeout);
      _initTimer?.cancel();
      if (!mounted || token != _initToken || _hasError) return;

      controller.addListener(_onControllerUpdate);

      if (previousPosition > Duration.zero) {
        try {
          await controller.seekTo(previousPosition);
        } catch (_) {
          // Position restore is best-effort; playback can still continue.
        }
      }

      if (!mounted || token != _initToken || _hasError) return;
      setState(() {
        _isInitialized = true;
      });
      _startHideTimer();
    } on TimeoutException {
      _initTimer?.cancel();
      if (mounted && token == _initToken) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Timed out while opening the video stream. '
              'Check your connection and retry.';
        });
      }
    } catch (e) {
      _initTimer?.cancel();
      if (mounted && token == _initToken) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Could not load video stream: $e';
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;

    final value = controller.value;
    if (value.hasError && !_hasError) {
      _hideTimer?.cancel();
      setState(() {
        _hasError = true;
        _errorMessage = value.errorDescription?.trim().isNotEmpty == true
            ? 'Playback error: ${value.errorDescription}'
            : 'Playback stopped because the stream became unavailable.';
      });
      return;
    }

    if (_isInitialized) {
      _lastPosition = value.position;
    }
    setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _seekRelative(Duration delta) {
    if (_controller == null || !_isInitialized) return;
    final current = _controller!.value.position;
    final total = _controller!.value.duration;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    _controller!.seekTo(target);
    _startHideTimer();
  }

  void _openFullscreen() {
    if (_controller == null || !_isInitialized) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ArchiveFullscreenVideoPage(
          controller: _controller!,
          title: widget.title,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _initToken++;
    _initTimer?.cancel();
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    key: const Key('player-close-button'),
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),

          // Video content area
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_hasError)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            key: const Key('player-retry-button'),
                            onPressed: () => _initializePlayer(restart: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _yellow,
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry Playback'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!_isInitialized)
                  const Center(
                    child: CircularProgressIndicator(color: _yellow),
                  )
                else ...[
                  GestureDetector(
                    key: const Key('player-video-tap-area'),
                    onTap: _toggleControls,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio > 0
                            ? _controller!.value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),

                  // Buffering indicator
                  if (_controller!.value.isBuffering)
                    const Center(
                      child: CircularProgressIndicator(color: _yellow),
                    ),

                  // Overlay controls
                  if (_showControls)
                    Container(
                      color: Colors.black45,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(height: 1), // spacer

                          // Center controls: Rewind, Play/Pause, Fast Forward
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                key: const Key('player-seek-backward-button'),
                                iconSize: 36,
                                color: Colors.white,
                                tooltip: 'Rewind 10s',
                                icon: const Icon(Icons.replay_10_rounded),
                                onPressed: () =>
                                    _seekRelative(const Duration(seconds: -10)),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                key: const Key('player-play-pause-button'),
                                iconSize: 52,
                                color: _yellow,
                                icon: Icon(
                                  _controller!.value.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_fill,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_controller!.value.isPlaying) {
                                      _controller!.pause();
                                    } else {
                                      _controller!.play();
                                    }
                                  });
                                  _startHideTimer();
                                },
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                key: const Key('player-seek-forward-button'),
                                iconSize: 36,
                                color: Colors.white,
                                tooltip: 'Forward 10s',
                                icon: const Icon(Icons.forward_10_rounded),
                                onPressed: () =>
                                    _seekRelative(const Duration(seconds: 10)),
                              ),
                            ],
                          ),

                          // Bottom scrub bar, duration, and fullscreen button
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                Text(
                                  _formatDuration(_controller!.value.position),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    _controller!,
                                    allowScrubbing: true,
                                    colors: const VideoProgressColors(
                                      playedColor: _yellow,
                                      bufferedColor: Colors.white24,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDuration(_controller!.value.duration),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  key: const Key('player-fullscreen-button'),
                                  icon: const Icon(Icons.fullscreen,
                                      color: _yellow, size: 24),
                                  tooltip: 'Fullscreen',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: _openFullscreen,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen Landscape Video Player Page
class ArchiveFullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;

  const ArchiveFullscreenVideoPage({
    super.key,
    required this.controller,
    required this.title,
  });

  @override
  State<ArchiveFullscreenVideoPage> createState() =>
      _ArchiveFullscreenVideoPageState();
}

class _ArchiveFullscreenVideoPageState
    extends State<ArchiveFullscreenVideoPage> {
  static const Color _yellow = Color(0xFFFFC400);

  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // Force landscape orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide system UI overlays (status bar and navigation bar)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    widget.controller.addListener(_onControllerUpdate);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onControllerUpdate);

    // Restore orientation and system UI overlays
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _seekRelative(Duration delta) {
    final current = widget.controller.value.position;
    final total = widget.controller.value.duration;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    widget.controller.seekTo(target);
    _startHideTimer();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Handled in dispose(): restores orientations and system overlays
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            // Video view preserving aspect ratio
            GestureDetector(
              key: const Key('fullscreen-video-tap-area'),
              onTap: _toggleControls,
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio > 0
                      ? widget.controller.value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(widget.controller),
                ),
              ),
            ),

            // Buffering indicator
            if (widget.controller.value.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: _yellow),
              ),

            // Stream error overlay
            if (widget.controller.value.hasError)
              ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          widget.controller.value.errorDescription?.trim().isNotEmpty ==
                                  true
                              ? 'Playback error: ${widget.controller.value.errorDescription}'
                              : 'The stream became unavailable.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          key: const Key('fullscreen-error-close-button'),
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _yellow,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Back to Movies'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Fullscreen Overlay Controls
            if (_showControls)
              Container(
                color: Colors.black45,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top bar with Title and Exit button
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            IconButton(
                              key: const Key('fullscreen-exit-button'),
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white, size: 26),
                              tooltip: 'Exit Fullscreen',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('fullscreen-exit-icon-button'),
                              icon: const Icon(Icons.fullscreen_exit,
                                  color: _yellow, size: 26),
                              tooltip: 'Exit Fullscreen',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),

                      // Center playback controls: -10s, Play/Pause, +10s
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            key: const Key('fullscreen-seek-backward-button'),
                            iconSize: 48,
                            color: Colors.white,
                            tooltip: 'Rewind 10s',
                            icon: const Icon(Icons.replay_10_rounded),
                            onPressed: () =>
                                _seekRelative(const Duration(seconds: -10)),
                          ),
                          const SizedBox(width: 32),
                          IconButton(
                            key: const Key('fullscreen-play-pause-button'),
                            iconSize: 64,
                            color: _yellow,
                            icon: Icon(
                              widget.controller.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                            ),
                            onPressed: () {
                              setState(() {
                                if (widget.controller.value.isPlaying) {
                                  widget.controller.pause();
                                } else {
                                  widget.controller.play();
                                }
                              });
                              _startHideTimer();
                            },
                          ),
                          const SizedBox(width: 32),
                          IconButton(
                            key: const Key('fullscreen-seek-forward-button'),
                            iconSize: 48,
                            color: Colors.white,
                            tooltip: 'Forward 10s',
                            icon: const Icon(Icons.forward_10_rounded),
                            onPressed: () =>
                                _seekRelative(const Duration(seconds: 10)),
                          ),
                        ],
                      ),

                      // Bottom scrubber bar
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              _formatDuration(
                                  widget.controller.value.position),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: VideoProgressIndicator(
                                widget.controller,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: _yellow,
                                  bufferedColor: Colors.white30,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatDuration(
                                  widget.controller.value.duration),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
