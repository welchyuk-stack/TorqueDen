import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/post_comment.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';

/// A modal-bottom-sheet body that shows the comment thread for a build update
/// and lets the signed-in user add comments or replies.
///
/// Shown via:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: AppColors.graphite,
///   shape: const RoundedRectangleBorder(
///     borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
///   ),
///   builder: (_) => CommentsSheet(entryId: entry.id),
/// );
/// ```
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.entryId,
    this.fillParent = false,
    this.onClose,
    this.reserveKeyboardInset = true,
  });

  final String entryId;

  /// When true, fills the parent's height instead of a fixed 75% sheet — used
  /// to embed the panel inline (e.g. under a reel).
  final bool fillParent;

  /// Called by the header's close button instead of popping a route — lets an
  /// inline host collapse the panel.
  final VoidCallback? onClose;

  /// Whether to pad the input for the keyboard itself. Set false when the host
  /// already lifts the panel above the keyboard.
  final bool reserveKeyboardInset;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _client = Supabase.instance.client;
  final _inputController = TextEditingController();

  late Future<List<PostComment>> _commentsFuture;

  /// The comment currently being replied to, or null for a top-level comment.
  PostComment? _replyTarget;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _commentsFuture = _loadComments();
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<List<PostComment>> _loadComments() async {
    await Moderation.refreshBlocks();
    final rows = await _client
        .from('post_comments')
        .select(
          'id, build_entry_id, user_id, parent_id, body, created_at, profiles(username)',
        )
        .eq('build_entry_id', widget.entryId)
        .order('created_at', ascending: true);
    return rows
        .map(PostComment.fromMap)
        .where((c) => !Moderation.isBlocked(c.userId))
        .toList();
  }

  Future<void> _refresh() async {
    final future = _loadComments();
    setState(() {
      _commentsFuture = future;
    });
    await future;
  }

  /// Splits a flat, time-ordered list into top-level comments each carrying
  /// their replies (in order). Replies whose parent is missing are skipped.
  List<_Thread> _buildThreads(List<PostComment> all) {
    final tops = <PostComment>[];
    final repliesByParent = <String, List<PostComment>>{};
    for (final c in all) {
      if (c.parentId == null) {
        tops.add(c);
      } else {
        repliesByParent.putIfAbsent(c.parentId!, () => <PostComment>[]).add(c);
      }
    }
    return tops
        .map((t) => _Thread(t, repliesByParent[t.id] ?? const <PostComment>[]))
        .toList();
  }

  void _startReply(PostComment comment) {
    setState(() => _replyTarget = comment);
  }

  void _moderate(PostComment comment) {
    showModerationSheet(
      context,
      targetType: 'comment',
      targetId: comment.id,
      authorId: comment.userId,
      authorName: comment.username,
      onBlocked: _refresh,
    );
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  Future<void> _send() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final payload = <String, dynamic>{
        'build_entry_id': widget.entryId,
        'user_id': user.id,
        'body': text,
      };
      final parentId = _replyTarget?.id;
      if (parentId != null) {
        payload['parent_id'] = parentId;
      }
      await _client.from('post_comments').insert(payload);

      if (!mounted) return;
      _inputController.clear();
      setState(() => _replyTarget = null);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post your comment: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset =
        widget.reserveKeyboardInset ? MediaQuery.viewInsetsOf(context).bottom : 0.0;

    final content = Column(
      mainAxisSize: widget.fillParent ? MainAxisSize.max : MainAxisSize.min,
      children: [
          _header(),
          const Divider(height: 1, color: AppColors.hairline),
          Expanded(
            child: FutureBuilder<List<PostComment>>(
              future: _commentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.ember),
                  );
                }
                if (snapshot.hasError) {
                  return _centeredMuted('Could not load comments.\n${snapshot.error}');
                }
                final threads = _buildThreads(snapshot.data ?? const []);
                if (threads.isEmpty) {
                  return _centeredMuted('No comments yet — start the conversation.');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: threads.length,
                  itemBuilder: (_, i) {
                    final thread = threads[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CommentTile(
                          comment: thread.comment,
                          onReply: () => _startReply(thread.comment),
                          onMore: () => _moderate(thread.comment),
                        ),
                        for (final reply in thread.replies)
                          Padding(
                            padding: const EdgeInsets.only(left: 44),
                            child: _CommentTile(
                              comment: reply,
                              onReply: () => _startReply(thread.comment),
                              onMore: () => _moderate(reply),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.hairline),
          _inputBar(keyboardInset),
        ],
      );

    if (widget.fillParent) return content;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: content,
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          Text(
            'Comments',
            style: GoogleFonts.archivo(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.cream,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: AppColors.steel),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _centeredMuted(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 15,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _inputBar(double keyboardInset) {
    final replyTo = _replyTarget;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + keyboardInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyTo != null) _replyChip(replyTo),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  cursorColor: AppColors.ember,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.graphiteRaised,
                    hintText: replyTo != null
                        ? 'Reply to ${replyTo.username}…'
                        : 'Add a comment…',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppColors.ember, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.ember,
                        ),
                      )
                    : const Icon(Icons.send, color: AppColors.ember),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _replyChip(PostComment replyTo) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Replying to ${replyTo.username}',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: _cancelReply,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 16, color: AppColors.steel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A top-level comment paired with its (ordered) replies.
class _Thread {
  const _Thread(this.comment, this.replies);

  final PostComment comment;
  final List<PostComment> replies;
}

/// A single comment row: avatar placeholder, username + timestamp, body, and a
/// "Reply" affordance. Reused for both top-level comments and replies.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onReply, this.onMore});

  final PostComment comment;
  final VoidCallback onReply;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onMore,
      behavior: HitTestBehavior.opaque,
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(username: comment.username),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.username,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(comment.createdAt),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.body,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.cream,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: onReply,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Text(
                      'Reply',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.steel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// A small circular avatar placeholder showing the first letter of [username].
class _Avatar extends StatelessWidget {
  const _Avatar({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final initial = username.trim().isNotEmpty
        ? username.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.graphiteRaised,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.cream,
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Local, intl-free relative/date formatter.
/// "just now" / "5m" / "3h" within a day, then "3 Jun" or "3 Jun 2026".
String _formatTimestamp(DateTime when) {
  final now = DateTime.now();
  final local = when.toLocal();
  final diff = now.difference(local);

  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';

  final day = local.day;
  final month = _months[local.month - 1];
  if (local.year == now.year) {
    return '$day $month';
  }
  return '$day $month ${local.year}';
}
