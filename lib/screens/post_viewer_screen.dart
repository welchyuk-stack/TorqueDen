import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/comments_sheet.dart';
import 'package:torqueden/widgets/post_media_view.dart';

/// Fullscreen, reel-style media viewer. The clip/photo fills the screen (video
/// covers and plays with sound). A back button sits bottom-left and a like +
/// comment rail bottom-right. Tapping comments slides the media up to 75% and
/// reveals a scrollable comments panel in the bottom 25%.
class PostViewerScreen extends StatefulWidget {
  const PostViewerScreen({super.key, required this.media});

  final PostMedia media;

  @override
  State<PostViewerScreen> createState() => _PostViewerScreenState();
}

class _PostViewerScreenState extends State<PostViewerScreen> {
  final _client = Supabase.instance.client;

  bool _commentsOpen = false;
  bool _liked = false;
  int _likes = 0;
  int _comments = 0;
  bool _busy = false;

  String? get _entryId => widget.media.buildEntryId;

  // Comments take the bottom 75% when open (matching the Home comments sheet);
  // the media shifts up into the top 25%.
  static const double _commentsFraction = 0.75;

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
                child: _mediaArea(),
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

  Widget _mediaArea() {
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
        // Back — bottom-left.
        Positioned(
          left: 12,
          bottom: 20,
          child: _CircleButton(
            icon: Icons.arrow_back,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        // Like + comment rail — bottom-right.
        if (_entryId != null)
          Positioned(
            right: 12,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: _liked
                      ? Icons.local_fire_department
                      : Icons.local_fire_department_outlined,
                  color: _liked ? AppColors.ember : Colors.white,
                  label: '$_likes',
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 18),
                _RailButton(
                  icon: Icons.mode_comment_outlined,
                  color: Colors.white,
                  label: '$_comments',
                  onTap: _toggleComments,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _commentsPanel() {
    return DecoratedBox(
      decoration: const BoxDecoration(
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
      color: Colors.black.withValues(alpha: 0.45),
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
  final VoidCallback onTap;

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
