import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/screens/discover_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/comments_sheet.dart';
import 'package:torqueden/widgets/guest_nudge_sheet.dart';
import 'package:torqueden/widgets/share_sheet.dart';
import 'package:torqueden/widgets/post_media_view.dart';

/// Fullscreen, reel-style media viewer. The clip/photo fills the screen (video
/// covers and plays with sound). A back button sits bottom-left and a like +
/// comment rail bottom-right. Tapping comments slides the media up to 75% and
/// reveals a scrollable comments panel in the bottom 25%.
class PostViewerScreen extends StatefulWidget {
  const PostViewerScreen({
    super.key,
    required this.media,
    this.car,
    this.voteCount,
    this.isMyVote = false,
    this.canVote = false,
    this.onVote,
  });

  final PostMedia media;

  /// When supplied, a tappable car name chip appears at the top so the user
  /// can navigate to the car profile from this view.
  final Car? car;

  /// Shot challenge vote params — only passed when opened from the challenge screen.
  final int? voteCount;
  final bool isMyVote;
  final bool canVote;
  final VoidCallback? onVote;

  @override
  State<PostViewerScreen> createState() => _PostViewerScreenState();
}

class _PostViewerScreenState extends State<PostViewerScreen> {
  final _client = Supabase.instance.client;

  bool _commentsOpen = false;
  bool _liked = false;
  int _likes = 0;
  int _comments = 0;
  late int? _voteCount = widget.voteCount;
  late bool _isMyVote = widget.isMyVote;
  bool _busy = false;

  String? get _entryId => widget.media.buildEntryId;

  // Comments take the bottom 75% when open (matching the Home comments sheet);
  // the media shifts up into the top 25%.
  static const double _commentsFraction = 0.50;

  @override
  void initState() {
    super.initState();
    if (_entryId != null) _load();
  }

  Future<void> _load() async {
    final uid = _client.auth.currentUser?.id;
    try {
      final likes = await _client
          .from('post_likes')
          .select('user_id')
          .eq('build_entry_id', _entryId!);
      final comments = await _client
          .from('post_comments')
          .select('id')
          .eq('build_entry_id', _entryId!);
      if (!mounted) return;
      setState(() {
        _likes = likes.length;
        _liked = uid != null && likes.any((l) => (l as Map)['user_id'] == uid);
        _comments = comments.length;
      });
    } catch (_) {/* leave counts as-is */}
  }

  Future<void> _toggleLike() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || _busy || _entryId == null) return;
    final wasLiked = _liked;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _liked = !wasLiked;
      _likes += wasLiked ? -1 : 1;
    });
    try {
      if (wasLiked) {
        await _client
            .from('post_likes')
            .delete()
            .eq('build_entry_id', _entryId!)
            .eq('user_id', uid);
      } else {
        await _client.from('post_likes').upsert(
          {'build_entry_id': _entryId!, 'user_id': uid},
          onConflict: 'build_entry_id,user_id',
          ignoreDuplicates: true,
        );
      }
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likes += wasLiked ? 1 : -1;
        _busy = false;
      });
    }
  }

  void _handleVote() {
    if (!widget.canVote) {
      showGuestNudge(context, reason: 'vote on challenge entries');
      return;
    }
    if (widget.onVote == null) return;
    setState(() {
      if (_isMyVote) {
        _isMyVote = false;
        _voteCount = (_voteCount ?? 1) - 1;
      } else {
        _isMyVote = true;
        _voteCount = (_voteCount ?? 0) + 1;
      }
    });
    widget.onVote!();
  }

  void _toggleComments() {
    if (_commentsOpen) {
      FocusScope.of(context).unfocus();
      setState(() => _commentsOpen = false);
      _load(); // pick up any newly posted comments in the count
    } else {
      setState(() => _commentsOpen = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final commentsH = h * _commentsFraction;
          const dur = Duration(milliseconds: 260);
          const curve = Curves.easeOut;

          return Stack(
            children: [
              // Media area — full height, shrinking to (1 - fraction) when open.
              AnimatedPositioned(
                duration: dur,
                curve: curve,
                top: 0,
                left: 0,
                right: 0,
                height: _commentsOpen ? h - commentsH : h,
                child: _mediaArea(_commentsOpen ? h - commentsH : h),
              ),
              // Comments panel — slides up from below into the bottom slice.
              AnimatedPositioned(
                duration: dur,
                curve: curve,
                left: 0,
                right: 0,
                height: commentsH,
                bottom: _commentsOpen ? keyboardInset : -commentsH,
                child: (_commentsOpen && _entryId != null)
                    ? _commentsPanel()
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _mediaArea(double mediaHeight) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PostMediaView(media: [widget.media], fill: true, startMuted: false),
        // Legibility gradient behind the controls.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 160,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
        ),
        // Back — top-left, safe-area aware.
        Positioned(
          left: 12,
          top: MediaQuery.of(context).padding.top + 8,
          child: _CircleButton(
            icon: Icons.arrow_back,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        // Car link + caption + hashtags — bottom-left, leaving the right rail clear.
        if (widget.car != null ||
            (widget.media.caption?.isNotEmpty ?? false) ||
            widget.media.tags.isNotEmpty)
          Positioned(
            left: 14,
            right: 80,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.car != null) ...[
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CarDetailScreen(car: widget.car!),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.car!.title,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right,
                            size: 16,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (widget.media.caption?.isNotEmpty ?? false)
                  Text(
                    widget.media.caption!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                if (widget.media.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      for (final tag in widget.media.tags)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DiscoverScreen(initialQuery: '#$tag'),
                            ),
                          ),
                          child: Text(
                            '#$tag',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ember,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        // Like + comment rail — bottom-right corner, safe-area aware.
        Positioned(
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_voteCount != null) ...[
                  _RailButton(
                    icon: _isMyVote
                        ? Icons.arrow_upward
                        : Icons.arrow_upward_outlined,
                    color: _isMyVote ? AppColors.ember : AppColors.cream,
                    label: '$_voteCount',
                    onTap: _handleVote,
                  ),
                  const SizedBox(height: 18),
                ],
                _RailButton(
                  icon: _liked
                      ? Icons.local_fire_department
                      : Icons.local_fire_department_outlined,
                  color: _liked ? AppColors.ember : AppColors.cream,
                  label: '$_likes',
                  onTap: _entryId != null ? _toggleLike : null,
                ),
                const SizedBox(height: 18),
                _RailButton(
                  icon: Icons.mode_comment_outlined,
                  color: AppColors.cream,
                  label: '$_comments',
                  onTap: _entryId != null ? _toggleComments : null,
                ),
                if (widget.car != null) ...[
                  const SizedBox(height: 18),
                  _RailButton(
                    icon: Icons.ios_share_outlined,
                    color: AppColors.cream,
                    label: 'Share',
                    onTap: () => showShareSheet(context, car: widget.car!),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _commentsPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: CommentsSheet(
          entryId: _entryId!,
          fillParent: true,
          reserveKeyboardInset: false, // host lifts the panel above the keyboard
          onClose: _toggleComments,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.20),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, color: AppColors.cream, size: 22),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 34, shadows: const [
            Shadow(color: Colors.black54, blurRadius: 6),
          ]),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}
