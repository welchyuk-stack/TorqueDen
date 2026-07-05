import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/feed_ad_slot.dart';
import 'package:torqueden/widgets/car/build_tab.dart' show LinkedModChip;
import 'package:torqueden/widgets/comments_sheet.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/like_button.dart';
import 'package:torqueden/widgets/post_media_view.dart';
import 'package:torqueden/widgets/notification_bell.dart';
import 'package:torqueden/widgets/settings_button.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Home feed — the latest *posted* build updates from cars the user follows,
/// newest first. Silent updates are excluded.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _client = Supabase.instance.client;
  // Rows are a mix of _FeedItem (real posts) and SponsoredPost (house ads).
  late Future<List<Object>> _feedFuture;

  @override
  void initState() {
    super.initState();
    _feedFuture = _load();
  }

  Future<List<Object>> _load() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];

    await Moderation.refreshBlocks();
    final follows =
        await _client.from('follows').select('car_id').eq('follower_id', uid);
    final ids = follows.map((r) => r['car_id'] as String).toList();
    if (ids.isEmpty) return const [];

    final rows = await _client
        .from('build_entries')
        .select(
          'id, title, body, created_at, '
          'car:cars(id, owner_id, make, model, nickname, photo_url), '
          'post_media(id, url, kind, position), '
          'linked:linked_build_entry_id(title, category), '
          'post_likes(user_id), post_comments(id)',
        )
        .inFilter('car_id', ids)
        .eq('silent', false)
        .order('created_at', ascending: false);

    final items = <_FeedItem>[];
    for (final row in rows) {
      final carMap = row['car'];
      if (carMap == null) continue;
      // Hide posts from blocked owners.
      if (Moderation.isBlocked((carMap as Map)['owner_id'] as String?)) continue;
      final media = ((row['post_media'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(PostMedia.fromMap)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      final likes = (row['post_likes'] as List?) ?? const [];
      items.add(
        _FeedItem(
          id: row['id'] as String,
          title: row['title'] as String,
          body: row['body'] as String?,
          createdAt: DateTime.parse(row['created_at'] as String),
          car: Car.fromMap(carMap as Map<String, dynamic>),
          media: media,
          likeCount: likes.length,
          likedByMe: likes.any((l) => (l as Map)['user_id'] == uid),
          commentCount: ((row['post_comments'] as List?) ?? const []).length,
          linkedModLabel: _linkedLabel(row['linked'] as Map<String, dynamic>?),
        ),
      );
    }
    if (items.isEmpty) return const [];

    // Premium/Partner get an ad-free feed (once enforced); everyone else has
    // ad slots woven in (filled by AdMob).
    await Entitlements.refresh();
    if (!Entitlements.adsEnabled) return items;
    return _weaveAdSlots(items);
  }

  /// One ad slot after every [_adEveryNPosts] real posts — never first, never
  /// two in a row. Each slot is filled by an AdMob ad (or collapses if unfilled).
  static const int _adEveryNPosts = 6;
  static List<Object> _weaveAdSlots(List<_FeedItem> posts) {
    final out = <Object>[];
    var slots = 0;
    for (var i = 0; i < posts.length; i++) {
      out.add(posts[i]);
      if ((i + 1) % _adEveryNPosts == 0) {
        out.add(const _AdSlot());
        slots++;
      }
    }
    // Feed too short to hit a slot — still add one so an ad can show.
    if (slots == 0 && posts.isNotEmpty) out.add(const _AdSlot());
    return out;
  }

  /// "Category · Title" for an embedded linked mod, or null.
  static String? _linkedLabel(Map<String, dynamic>? linked) {
    if (linked == null) return null;
    final title = linked['title'] as String?;
    if (title == null || title.isEmpty) return null;
    final category = linked['category'] as String?;
    return (category != null && category.isNotEmpty) ? '$category · $title' : title;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _feedFuture = future;
    });
    await future;
  }

  Future<void> _openCar(Car car) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Nudged right a touch and sized up a little from the default 22.
        title: const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Wordmark(fontSize: 24),
        ),
        actions: const [NotificationBell(), SettingsButton()],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Object>>(
          future: _feedFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.ember),
              );
            }
            if (snapshot.hasError) {
              return _ScrollableCenter(
                onRefresh: _refresh,
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load your feed',
                  message: '${snapshot.error}',
                  action: FilledButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const <Object>[];
            if (items.isEmpty) {
              return _ScrollableCenter(
                onRefresh: _refresh,
                child: const EmptyState(
                  icon: Icons.dynamic_feed_outlined,
                  title: 'Your feed is quiet',
                  message:
                      'Follow some cars in the Search tab and their build '
                      'updates show up here.',
                ),
              );
            }

            return RefreshIndicator(
              color: AppColors.ember,
              backgroundColor: AppColors.graphite,
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final row = items[i];
                  if (row is _AdSlot) return const FeedAdSlot();
                  final item = row as _FeedItem;
                  return _FeedCard(
                    item: item,
                    onOpenProfile: () => _openCar(item.car),
                    onChanged: _refresh,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pull-to-refreshable centered state (error / empty).
class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child, required this.onRefresh});

  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.ember,
      backgroundColor: AppColors.graphite,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FeedItem {
  const _FeedItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.car,
    this.body,
    this.media = const [],
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentCount = 0,
    this.linkedModLabel,
  });

  final String id;
  final String title;
  final String? body;
  final DateTime createdAt;
  final Car car;
  final List<PostMedia> media;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final String? linkedModLabel;
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, this.onOpenProfile, this.onChanged});

  final _FeedItem item;
  final VoidCallback? onOpenProfile;
  final Future<void> Function()? onChanged;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  Future<void> _openComments(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CommentsSheet(entryId: item.id),
    );
    await onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final car = item.car;
    final body = item.body?.trim() ?? '';
    final hasBody = body.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cream, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Thumbnail(car: car),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      car.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(item.createdAt),
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              // Dedicated button to open the profile, so tapping the post body
              // does nothing (better for scrolling on touch screens).
              IconButton(
                onPressed: onOpenProfile,
                icon: const Icon(Icons.arrow_forward, size: 20),
                color: AppColors.steel,
                tooltip: 'View car',
              ),
              IconButton(
                onPressed: () => showModerationSheet(
                  context,
                  targetType: 'post',
                  targetId: item.id,
                  authorId: car.ownerId,
                  onBlocked: () => onChanged?.call(),
                ),
                icon: const Icon(Icons.more_vert, size: 20),
                color: AppColors.steel,
                tooltip: 'More',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (item.media.isNotEmpty) ...[
            PostMediaView(media: item.media),
            const SizedBox(height: 12),
          ],
          Text(
            item.title,
            style: GoogleFonts.archivo(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.cream,
            ),
          ),
          if (hasBody) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          if (item.linkedModLabel != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: LinkedModChip(label: item.linkedModLabel!),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              LikeButton(
                entryId: item.id,
                initialLiked: item.likedByMe,
                initialCount: item.likeCount,
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _openComments(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mode_comment_outlined, size: 20, color: AppColors.steel),
                      const SizedBox(width: 6),
                      Text(
                        '${item.commentCount}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.steel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Marker in the feed list where an AdMob ad should render.
class _AdSlot {
  const _AdSlot();
}

/// 44x44 rounded car thumbnail with a graphiteRaised fallback.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.car});

  final Car car;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: 44,
        child: car.hasPhoto
            ? Image.network(
                car.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ThumbFallback(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _ThumbFallback(),
              )
            : const _ThumbFallback(),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_outlined, color: AppColors.steel, size: 22),
    );
  }
}
