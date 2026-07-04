import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/post_viewer_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// Posts tab for a car profile: an Instagram-style media grid of every photo
/// and clip the car has posted. Self-contained scrollable so it slots straight
/// into a TabBarView, with pull-to-refresh throughout (including the empty and
/// error states).
class PostsTab extends StatefulWidget {
  const PostsTab({super.key, required this.car});

  final Car car;

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
  const _MediaTile({required this.media, required this.onTap});

  final PostMedia media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.isVideo)
            const _TileFallback()
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

