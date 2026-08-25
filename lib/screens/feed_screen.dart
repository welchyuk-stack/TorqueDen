import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:torqueden/main_shell.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/screens/discover_screen.dart';
import 'package:torqueden/screens/post_viewer_screen.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/time_ago.dart';
import 'package:torqueden/widgets/feed_ad_slot.dart';
import 'package:torqueden/widgets/car/build_tab.dart' show LinkedModChip;
import 'package:torqueden/widgets/comments_sheet.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/like_button.dart';
import 'package:torqueden/widgets/post_media_view.dart';
import 'package:torqueden/screens/create_post_screen.dart';
import 'package:torqueden/services/feed_prefs.dart';
import 'package:torqueden/services/challenge_service.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/widgets/guest_nudge_sheet.dart';
import 'package:torqueden/widgets/notification_bell.dart';
import 'package:torqueden/models/challenge.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Home feed — the latest *posted* build updates from cars the user follows,
/// newest first. Silent updates are excluded.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  /// Fire this to trigger a reload from anywhere (e.g. when the tab is
  /// re-selected after a follow/unfollow on another screen).
  static final refreshSignal = StreamController<void>.broadcast();

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Object>> _feedFuture;
  Set<String> _shotTags = {};
  StreamSubscription<void>? _refreshSub;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _feedFuture = _load();
    _refreshSub = FeedScreen.refreshSignal.stream.listen((_) {
      if (mounted) _refresh();
    });
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.signedOut) {
        if (mounted) _refresh();
      }
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Future<List<Object>> _load() async {
    // Keep challenge tags fresh so the hide-shot filter stays accurate.
    ChallengeService.instance.fetchAll().then((challenges) {
      if (mounted) setState(() => _shotTags = {for (final c in challenges) c.tag});
    });
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return _loadPublic();

    await Moderation.refreshBlocks();
    final follows = await _client
        .from('follows')
        .select('car_id')
        .eq('follower_id', uid);
    final ids = follows.map((r) => r['car_id'] as String).toList();
    if (ids.isEmpty) return const [];

    final rows = await _client
        .from('build_entries')
        .select(
          'id, title, body, created_at, location_name, tags, '
          'car:cars(id, owner_id, make, model, nickname, photo_url), '
          'post_media(id, url, kind, position), '
          'linked:linked_build_entry_id(title, category), '
          'post_likes(user_id), post_comments(id)',
        )
        .inFilter('car_id', ids)
        .eq('silent', false)
        .order('created_at', ascending: false)
        .limit(50);

    final items = <_FeedItem>[];
    for (final row in rows) {
      final carMap = row['car'];
      if (carMap == null) continue;
      // Hide posts from blocked owners.
      if (Moderation.isBlocked((carMap as Map)['owner_id'] as String?))
        continue;
      final media =
          ((row['post_media'] as List?) ?? const [])
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
          locationName: row['location_name'] as String?,
          tags: (row['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
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

  /// Public feed for unauthenticated users — latest posts by timestamp.
  Future<List<Object>> _loadPublic() async {
    final rows = await _client
        .from('build_entries')
        .select(
          'id, title, body, created_at, location_name, tags, '
          'car:cars(id, owner_id, make, model, nickname, photo_url), '
          'post_media(id, url, kind, position), '
          'linked:linked_build_entry_id(title, category)',
        )
        .eq('silent', false)
        .order('created_at', ascending: false)
        .limit(50);

    final items = <_FeedItem>[];
    for (final row in rows) {
      final carMap = row['car'];
      if (carMap == null) continue;
      final media = ((row['post_media'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(PostMedia.fromMap)
          .toList()
        ..sort((a, b) => a.position.compareTo(b.position));
      items.add(
        _FeedItem(
          id: row['id'] as String,
          title: row['title'] as String,
          body: row['body'] as String?,
          createdAt: DateTime.parse(row['created_at'] as String),
          car: Car.fromMap(carMap as Map<String, dynamic>),
          media: media,
          likeCount: 0,
          likedByMe: false,
          commentCount: 0,
          linkedModLabel: _linkedLabel(row['linked'] as Map<String, dynamic>?),
          locationName: row['location_name'] as String?,
          tags: (row['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
        ),
      );
    }
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
    return (category != null && category.isNotEmpty)
        ? '$category · $title'
        : title;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _feedFuture = future;
    });
    await future;
  }

  Future<void> _openCar(Car car) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)));
    // Refresh so any follow/unfollow change is reflected immediately.
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: const Wordmark(fontSize: 24),
            leadingWidth: 56,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: const NotificationBell(),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.add, color: AppColors.cream, size: 32),
                  onPressed: () async {
                    if (GuestMode.isGuest) {
                      await showGuestNudge(context, reason: 'post build updates');
                      return;
                    }
                    final posted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                    );
                    if (posted == true && mounted) _refresh();
                  },
                ),
              ),
            ],
          ),
        ],
        body: ValueListenableBuilder<bool>(
          valueListenable: FeedPrefs.mediaOnly,
          builder: (context, _, __) => ValueListenableBuilder<bool>(
            valueListenable: FeedPrefs.hideShot,
            builder: (context, _, __) => FutureBuilder<List<Object>>(
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
                final rawItems = snapshot.data ?? const <Object>[];
                final mediaOnly = FeedPrefs.mediaOnly.value;
                final hideShot = FeedPrefs.hideShot.value;
                final items = rawItems.where((obj) {
                  if (obj is! _FeedItem) return true;
                  if (mediaOnly && obj.media.isEmpty) return false;
                  if (hideShot && obj.tags.any(_shotTags.contains)) return false;
                  return true;
                }).toList();
                final isLoggedIn = _client.auth.currentUser != null;
                if (items.isEmpty) {
                  return _ScrollableCenter(
                    onRefresh: _refresh,
                    child: EmptyState(
                      icon: Icons.dynamic_feed_outlined,
                      title: isLoggedIn ? 'Your feed is quiet' : 'Welcome to TorqueDen',
                      message: isLoggedIn
                          ? 'Follow some cars to see their build updates here.'
                          : 'Discover and follow car builds from the community.',
                      action: FilledButton.icon(
                        onPressed: () => MainShell.jumpToDiscover.add(null),
                        icon: const Icon(Icons.search, size: 18),
                        label: Text(isLoggedIn ? 'Find cars to follow' : 'Explore builds'),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.ember,
                  backgroundColor: AppColors.graphite,
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    itemCount: items.length,
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
    this.locationName,
    this.tags = const [],
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
  final String? locationName;
  final List<String> tags;
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, this.onOpenProfile, this.onChanged});

  final _FeedItem item;
  final VoidCallback? onOpenProfile;
  final Future<void> Function()? onChanged;

  String? get _location => (item.locationName?.trim().isNotEmpty == true
          ? item.locationName
          : item.car.locationName)
      ?.trim()
      .nullIfEmpty;

  Future<void> _showOwnerActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: AppColors.cream),
              title: Text('Edit caption',
                  style: GoogleFonts.inter(color: AppColors.cream, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text('Delete post',
                  style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'edit' && context.mounted) await _editCaption(context);
    if (action == 'delete' && context.mounted) await _confirmDeletePost(context);
  }

  Future<void> _editCaption(BuildContext context) async {
    final ctrl = TextEditingController(text: item.title);
    final newCaption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Edit caption',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          maxLength: 500,
          style: GoogleFonts.inter(color: AppColors.cream),
          cursorColor: AppColors.ember,
          decoration: InputDecoration(
            hintText: 'Caption…',
            hintStyle: GoogleFonts.inter(color: AppColors.steel),
            counterStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.ember),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { ctrl.dispose(); Navigator.pop(ctx); },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              ctrl.dispose();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: Text('Save',
                style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (newCaption == null || !context.mounted) return;
    try {
      await Supabase.instance.client
          .from('build_entries')
          .update({'title': newCaption})
          .eq('id', item.id);
      await onChanged?.call();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update post: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeletePost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Delete post?',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text('This will permanently remove the post and all its media.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final client = Supabase.instance.client;
      // Fetch storage paths before deleting (cascade will remove post_media rows).
      final mediaRows = await client
          .from('post_media')
          .select('url')
          .eq('build_entry_id', item.id);
      final paths = (mediaRows as List)
          .map((r) => PostMedia.fromMap(r as Map<String, dynamic>).storagePath)
          .whereType<String>()
          .toList();
      if (paths.isNotEmpty) {
        await client.storage.from('car-photos').remove(paths);
      }
      await client.from('build_entries').delete().eq('id', item.id);
      await onChanged?.call();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete post: $e')),
        );
      }
    }
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: onOpenProfile,
                child: _Thumbnail(car: car),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onOpenProfile,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        car.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.cream,
                        ),
                      ),
                      _MetaRow(
                        when: timeAgo(item.createdAt),
                        location: _location,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final uid = Supabase.instance.client.auth.currentUser?.id;
                  if (uid != null && uid == car.ownerId) {
                    _showOwnerActions(context);
                  } else {
                    showModerationSheet(
                      context,
                      targetType: 'post',
                      targetId: item.id,
                      authorId: car.ownerId,
                      onBlocked: () => onChanged?.call(),
                    );
                  }
                },
                icon: const Icon(Icons.more_vert, size: 20),
                color: AppColors.steel,
              ),
            ],
          ),
        ),
        // ── Media / text card ────────────────────────────────────
        if (item.media.isEmpty)
          Container(
            width: double.infinity,
            color: AppColors.graphite,
            padding: const EdgeInsets.fromLTRB(0, 14, 20, 14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: AppColors.ember, margin: const EdgeInsets.only(left: 16, right: 14)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.cream,
                            height: 1.35,
                          ),
                        ),
                        if ((item.body?.trim() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _ExpandableBody(body: item.body!.trim()),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (item.media.isNotEmpty)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostViewerScreen(
                  media: PostMedia(
                    id: item.media.first.id,
                    url: item.media.first.url,
                    kind: item.media.first.kind,
                    position: item.media.first.position,
                    buildEntryId: item.id,
                    caption: item.title,
                    tags: item.tags,
                  ),
                ),
              ),
            ),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: PostMediaView(media: item.media, fill: true),
            ),
          ),
        // ── Caption + body (media posts only — text posts show title in card) ─
        if (item.media.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cream,
                ),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
              if (item.linkedModLabel != null) ...[
                const SizedBox(height: 8),
                LinkedModChip(label: item.linkedModLabel!),
              ],
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                _TagRow(tags: item.tags),
              ],
            ],
          ),
        ),
        // ── Footer ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              LikeButton(
                entryId: item.id,
                initialLiked: item.likedByMe,
                initialCount: item.likeCount,
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _openComments(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mode_comment_outlined, size: 20, color: AppColors.steel),
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
        ),
        // ── Divider ──────────────────────────────────────────────
        const Divider(height: 24, thickness: 0.5),
      ],
    );
  }
}

class _ExpandableBody extends StatefulWidget {
  const _ExpandableBody({required this.body});
  final String body;

  @override
  State<_ExpandableBody> createState() => _ExpandableBodyState();
}

class _ExpandableBodyState extends State<_ExpandableBody> {
  bool _expanded = false;
  static const _maxLines = 4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(
          text: widget.body,
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.55),
        );
        final tp = TextPainter(text: span, maxLines: _maxLines, textDirection: TextDirection.ltr)
          ..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.body,
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.55),
              maxLines: _expanded ? null : _maxLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (overflows) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'Show less' : 'Read more',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ember,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Horizontally scrollable row of tappable hashtag chips.
/// Tapping one pushes a Discover screen pre-filtered to that tag.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tag in tags) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiscoverScreen(initialQuery: '#$tag'),
                ),
              ),
              child: Text(
                '#$tag',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ember,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
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
                car.thumbnailUrl()!,
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

/// "2h" or "2h · 📍 Manchester" — time always first, then an optional ember
/// pin icon + location label. Kept as a widget so the icon can be coloured.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.when, required this.style, this.location});
  final String when;
  final String? location;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (location == null || location!.isEmpty) {
      return Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    return Row(
      children: [
        Text('$when · ', style: style),
        Icon(Icons.location_on, size: 11, color: AppColors.ember),
        const SizedBox(width: 2),
        Expanded(
          child: Text(location!, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: Icon(
        Icons.directions_car_outlined,
        color: AppColors.steel,
        size: 22,
      ),
    );
  }
}

class _ShowdownPill extends StatefulWidget {
  const _ShowdownPill({required this.challenge});
  final Challenge challenge;

  @override
  State<_ShowdownPill> createState() => _ShowdownPillState();
}

class _ShowdownPillState extends State<_ShowdownPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const w = 140.0;
    const h = 34.0;
    const pad = 8.0;

    return SizedBox(
      width: w + pad * 2,
      height: h + pad * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: Container(
                width: w + pad * 2,
                height: h + pad * 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(h / 2 + pad),
                  gradient: const SweepGradient(
                    colors: [
                      Color(0x00E85A00),
                      Color(0xAAE85A00),
                      Color(0xFFFF9500),
                      Color(0xAAE85A00),
                      Color(0x00E85A00),
                    ],
                    stops: [0.0, 0.2, 0.5, 0.8, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(h / 2),
            ),
            child: Center(
              child: Text(
                'THE SHOT',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
