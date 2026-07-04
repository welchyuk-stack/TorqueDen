import 'package:flutter/material.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/theme.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Shows a build update's attached media as a swipeable carousel.
///
/// Videos autoplay muted when scrolled into view and pause when they leave
/// (short-form style); tap a clip to unmute. Set [startMuted] false to open a
/// clip with sound (e.g. the fullscreen viewer). Build only when [media] is
/// non-empty.
class PostMediaView extends StatefulWidget {
  const PostMediaView({
    super.key,
    required this.media,
    this.aspectRatio = 4 / 3,
    this.startMuted = true,
    this.fill = false,
  });

  final List<PostMedia> media;
  final double aspectRatio;
  final bool startMuted;

  /// Fullscreen mode: fill the parent (no fixed aspect / rounded corners),
  /// photos fit within the screen, video covers reel-style.
  final bool fill;

  @override
  State<PostMediaView> createState() => _PostMediaViewState();
}

class _PostMediaViewState extends State<PostMediaView> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media.isEmpty) return const SizedBox.shrink();

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: media.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _MediaItem(
            media: media[i],
            startMuted: widget.startMuted,
            imageFit: widget.fill ? BoxFit.contain : BoxFit.cover,
          ),
        ),
        if (media.length > 1) ...[
          Positioned(
            top: 10,
            right: 10,
            child: _Pill(text: '${_page + 1}/${media.length}'),
          ),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: _Dots(count: media.length, index: _page),
          ),
        ],
      ],
    );

    // Fullscreen: fill the parent as-is. Otherwise a rounded, fixed-ratio card.
    if (widget.fill) return stack;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(aspectRatio: widget.aspectRatio, child: stack),
    );
  }
}

class _MediaItem extends StatelessWidget {
  const _MediaItem({
    required this.media,
    this.startMuted = true,
    this.imageFit = BoxFit.cover,
  });

  final PostMedia media;
  final bool startMuted;
  final BoxFit imageFit;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return _VideoItem(url: media.url, startMuted: startMuted);
    }
    return Image.network(
      media.url,
      fit: imageFit,
      errorBuilder: (_, _, _) => const _MediaFallback(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _MediaFallback(),
    );
  }
}

/// Inline short-form video: autoplays muted (looping) once it scrolls into
/// view, pauses when it leaves. Tap toggles mute; a thin progress bar and a
/// speaker chip sit on top.
class _VideoItem extends StatefulWidget {
  const _VideoItem({required this.url, this.startMuted = true});

  final String url;
  final bool startMuted;

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  final Key _visKey = UniqueKey();
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _error = false;
  bool _muted = true;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _muted = widget.startMuted;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      c.setVolume(_muted ? 0 : 1);
      setState(() => _ready = true);
      _syncPlayback();
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Play while on screen, pause while off — keeps only visible clips running.
  void _syncPlayback() {
    final c = _controller;
    if (c == null || !_ready) return;
    if (_visible && !c.value.isPlaying) {
      c.play();
    } else if (!_visible && c.value.isPlaying) {
      c.pause();
    }
  }

  void _onVisibility(VisibilityInfo info) {
    final visible = info.visibleFraction > 0.6;
    if (visible == _visible) return;
    _visible = visible;
    _syncPlayback();
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_error) {
      return Container(
        color: AppColors.graphiteRaised,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_off_outlined, color: AppColors.steel, size: 40),
      );
    }
    if (!_ready || c == null) {
      return Container(
        color: AppColors.graphiteRaised,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: AppColors.ember),
      );
    }
    return VisibilityDetector(
      key: _visKey,
      onVisibilityChanged: _onVisibility,
      child: GestureDetector(
        onTap: _toggleMute,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            ),
            // Mute/unmute chip.
            Positioned(
              right: 10,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _muted ? Icons.volume_off : Icons.volume_up,
                  color: AppColors.cream,
                  size: 16,
                ),
              ),
            ),
            // Slim progress bar along the bottom edge.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: false,
                padding: EdgeInsets.zero,
                colors: const VideoProgressColors(
                  playedColor: AppColors.ember,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppColors.steel, size: 40),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.cream, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == index ? AppColors.ember : Colors.white.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }
}
