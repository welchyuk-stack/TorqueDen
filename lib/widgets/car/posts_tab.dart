import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/post_viewer_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Posts tab for a car profile: an Instagram-style media grid of every photo
/// and clip the car has posted. Self-contained scrollable so it slots straight
/// into a TabBarView, with pull-to-refresh throughout (including the empty and
/// error states). When [isOwner] is true, long-pressing a tile offers to
/// delete the whole post.
class PostsTab extends StatefulWidget {
  const PostsTab({super.key, required this.car, this.isOwner = false});

  final Car car;

  /// Whether the signed-in user owns this car (enables deleting posts).
  final bool isOwner;

  @override
  State<PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<PostsTab> {
  final _client = Supabase.instance.client;
  late Future<List<PostMedia>> _mediaFuture;

  @override
  void initState() {
    super.initState();
    _mediaFuture = _load();
  }

  Future<List<PostMedia>> _load() async {
    final rows = await _client
        .from('post_media')
        .select('id, url, kind, position, build_entry_id, created_at')
        .eq('car_id', widget.car.id)
        .order('created_at', ascending: false);
    return rows.map(PostMedia.fromMap).toList();
  }

  Future<void> _refresh() async {
    // Block body, not an arrow: setState() throws if its callback returns the
    // Future.
    final future = _load();
    setState(() {
      _mediaFuture = future;
    });
    await future;
  }

  void _openViewer(PostMedia media) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PostViewerScreen(media: media),
      ),
    );
  }

  Future<void> _confirmDelete(PostMedia media) async {
    final entryId = media.buildEntryId;
    if (entryId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Delete this post?',
          style:
              GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes the post — and any photos or clips in it — from your '
          'garage and feeds. This can\'t be undone.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style:
                  GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deletePost(entryId);
  }

  Future<void> _deletePost(String entryId) async {
    try {
      // Cascades to this post's media, likes and comments (FKs ON DELETE
      // CASCADE); RLS allows it only for the car's owner.
      await _client.from('build_entries').delete().eq('id', entryId);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete the post. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PostMedia>>(
      future: _mediaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.ember),
          );
        }
        if (snapshot.hasError) {
          return _ScrollableState(
            onRefresh: _refresh,
            child: EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load posts',
              message: '${snapshot.error}',
              action: FilledButton(
                onPressed: _refresh,
                child: const Text('Try again'),
              ),
            ),
          );
        }
        final media = snapshot.data ?? const <PostMedia>[];
        if (media.isEmpty) {
          return _ScrollableState(
            onRefresh: _refresh,
            child: const EmptyState(
              icon: Icons.grid_on_outlined,
              title: 'No posts yet',
              message:
                  'Photos and clips from this car\'s updates will show up here.',
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.ember,
          backgroundColor: AppColors.graphite,
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = (constraints.maxWidth / 140).floor().clamp(3, 6);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(3, 3, 3, 3),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  childAspectRatio: 1,
                ),
                itemCount: media.length,
                itemBuilder: (_, i) => _MediaTile(
                  media: media[i],
                  onTap: () => _openViewer(media[i]),
                  onLongPress:
                      widget.isOwner ? () => _confirmDelete(media[i]) : null,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Wraps an [EmptyState] (or error state) in a scroll view so the parent
/// [RefreshIndicator] can still trigger a pull-to-refresh even when there is
/// nothing to scroll.
class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.ember,
      backgroundColor: AppColors.graphite,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// A single square grid tile. Images render via [Image.network] with the same
/// graphiteRaised fallback used elsewhere; videos show a graphiteRaised well.
/// Either way, a small play badge marks video tiles.
class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media, required this.onTap, this.onLongPress});

  final PostMedia media;
  final VoidCallback onTap;

  /// Long-press action (delete) — only wired for the car's owner.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.isVideo)
            _VideoThumb(url: media.url)
          else
            Image.network(
              media.url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _TileFallback(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const _TileFallback(),
            ),
          if (media.isVideo)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 22,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }
}

/// A video's first frame as a grid thumbnail. The controller is created lazily
/// once the tile scrolls into view (and disposed when it scrolls off), so the
/// grid never holds more decoders than are on screen. Shows the frame paused —
/// playback happens in the fullscreen viewer.
class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.url});

  final String url;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  final Key _visKey = UniqueKey();
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _error = false;
  bool _started = false;

  void _onVisibility(VisibilityInfo info) {
    if (_started || info.visibleFraction <= 0) return;
    _started = true;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setVolume(0);
      setState(() => _ready = true); // paused on frame 0
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visKey,
      onVisibilityChanged: _onVisibility,
      child: Builder(
        builder: (_) {
          final c = _controller;
          if (_error || !_ready || c == null) return const _TileFallback();
          return FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder well for a video tile, or a failed/loading image.
class _TileFallback extends StatelessWidget {
  const _TileFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: AppColors.steel, size: 28),
    );
  }
}

