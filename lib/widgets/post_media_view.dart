import 'package:flutter/material.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/theme.dart';
import 'package:video_player/video_player.dart';

/// Shows a build update's attached media as a swipeable carousel.
///
/// Images render now; a video shows a placeholder tile until the player lands.
/// The caller should only build this when [media] is non-empty.
class PostMediaView extends StatefulWidget {
  const PostMediaView({super.key, required this.media, this.aspectRatio = 4 / 3});

  final List<PostMedia> media;
  final double aspectRatio;

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: media.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _MediaItem(media: media[i]),
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
        ),
      ),
    );
  }
}

class _MediaItem extends StatelessWidget {
  const _MediaItem({required this.media});

  final PostMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return _VideoItem(url: media.url);
    }
    return Image.network(
      media.url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _MediaFallback(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _MediaFallback(),
    );
  }
}

/// Inline video player: tap to play/pause, loops, fills the frame (cover).
class _VideoItem extends StatefulWidget {
  const _VideoItem({required this.url});

  final String url;

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setLooping(true);
      setState(() => _ready = true);
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
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
    return GestureDetector(
      onTap: _toggle,
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
          if (!c.value.isPlaying)
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 56),
            ),
        ],
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
