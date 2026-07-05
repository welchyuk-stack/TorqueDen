import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club_reply.dart';
import 'package:torqueden/models/club_thread.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/post_error.dart';
import 'package:torqueden/utils/time_ago.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';

/// A club thread: the question/post up top, its replies below, and a reply box
/// for members. [canPost] gates the reply box; [isOwner] can delete any reply.
class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({
    super.key,
    required this.thread,
    required this.canPost,
    required this.canModerate,
  });

  final ClubThread thread;
  final bool canPost;

  /// Owner or admin: can pin, and delete any reply.
  final bool canModerate;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  final _client = Supabase.instance.client;
  final _input = TextEditingController();

  List<ClubReply> _replies = [];
  bool _loading = true;
  Object? _error;
  bool _sending = false;
  ClubReply? _replyTarget;
  late bool _pinned = widget.thread.isPinned;

  String? get _uid => _client.auth.currentUser?.id;

  void _startReply(ClubReply r) => setState(() => _replyTarget = r);
  void _cancelReply() => setState(() => _replyTarget = null);

  /// Groups replies into top-level entries each carrying their nested replies.
  List<({ClubReply top, List<ClubReply> children})> _threads() {
    final tops = <ClubReply>[];
    final byParent = <String, List<ClubReply>>{};
    for (final r in _replies) {
      if (r.parentId == null) {
        tops.add(r);
      } else {
        byParent.putIfAbsent(r.parentId!, () => []).add(r);
      }
    }
    return [for (final t in tops) (top: t, children: byParent[t.id] ?? const [])];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    setState(() => _pinned = next);
    try {
      await _client.from('club_threads').update({'is_pinned': next}).eq('id', widget.thread.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pinned = !next);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update pin: $e')));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await Moderation.refreshBlocks();
      final rows = await _client
          .from('club_replies')
          .select('*, author:profiles(username), club_reply_votes(user_id, value)')
          .eq('thread_id', widget.thread.id)
          .order('created_at', ascending: true);
      final list = rows
          .map((r) => ClubReply.fromMap(r, currentUserId: _uid))
          .where((r) => !Moderation.isBlocked(r.authorId))
          .toList();
      if (!mounted) return;
      setState(() {
        _replies = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _vote(ClubReply r, int value) async {
    final uid = _uid;
    if (uid == null) return;
    final newVote = r.myVote == value ? 0 : value; // tap the same arrow to clear
    final delta = newVote - r.myVote;
    void apply(int vote, int score) {
      final i = _replies.indexWhere((x) => x.id == r.id);
      if (i != -1) _replies[i] = _replies[i].copyWith(myVote: vote, score: score);
    }

    setState(() => apply(newVote, r.score + delta));
    try {
      if (newVote == 0) {
        await _client.from('club_reply_votes').delete().eq('reply_id', r.id).eq('user_id', uid);
      } else {
        await _client.from('club_reply_votes').upsert(
          {'reply_id': r.id, 'user_id': uid, 'value': newVote},
          onConflict: 'reply_id,user_id',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => apply(r.myVote, r.score)); // revert
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not vote: $e')));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    // Reply-to-a-reply attaches under the top-level reply (one level deep).
    final parentId = _replyTarget == null ? null : (_replyTarget!.parentId ?? _replyTarget!.id);
    try {
      await _client.from('club_replies').insert({
        'thread_id': widget.thread.id,
        'body': text,
        'parent_id': ?parentId,
      });
      if (!mounted) return;
      _input.clear();
      _replyTarget = null;
      FocusScope.of(context).unfocus();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyPostError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteReply(ClubReply reply) async {
    try {
      await _client.from('club_replies').delete().eq('id', reply.id);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  Widget _tile(ClubReply r) => _ReplyTile(
        reply: r,
        canDelete: widget.canModerate || r.authorId == _uid,
        onDelete: () => _deleteReply(r),
        onVote: (v) => _vote(r, v),
        onReply: widget.canPost ? () => _startReply(r) : null,
        onMore: () => showModerationSheet(
          context,
          targetType: 'reply',
          targetId: r.id,
          authorId: r.authorId,
          authorName: r.authorName,
          onBlocked: _refresh,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.thread;
    final body = t.body?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thread'),
        actions: [
          if (widget.canModerate)
            IconButton(
              onPressed: _togglePin,
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: _pinned ? AppColors.ember : AppColors.steel),
              tooltip: _pinned ? 'Unpin' : 'Pin to top',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppColors.ember,
                backgroundColor: AppColors.graphite,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    // The question / opening post.
                    Text(
                      t.title,
                      style: GoogleFonts.archivo(
                          fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.cream, height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${t.authorName ?? 'Member'} · ${timeAgo(t.createdAt)}',
                      style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(body,
                          style: GoogleFonts.inter(fontSize: 15.5, color: AppColors.textSecondary, height: 1.5)),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          _replies.isEmpty
                              ? 'Replies'
                              : '${_replies.length} ${_replies.length == 1 ? 'reply' : 'replies'}',
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.steel),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(child: Divider(color: AppColors.hairline)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(child: CircularProgressIndicator(color: AppColors.ember)),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text('Could not load replies.\n$_error',
                            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted)),
                      )
                    else if (_replies.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          widget.canPost ? 'No replies yet — be the first.' : 'No replies yet.',
                          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
                        ),
                      )
                    else
                      for (final th in _threads()) ...[
                        _tile(th.top),
                        for (final child in th.children)
                          Padding(
                            padding: const EdgeInsets.only(left: 40),
                            child: _tile(child),
                          ),
                      ],
                  ],
                ),
              ),
            ),
            if (widget.canPost)
              _replyBar()
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: AppColors.graphite,
                child: Text(
                  'Join the club to reply.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _replyBar() {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.graphite,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTarget != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 15, color: AppColors.ember),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyTarget!.authorName ?? 'member'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
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
          Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
              cursorColor: AppColors.ember,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.graphiteRaised,
                hintText: _replyTarget != null ? 'Write a reply…' : 'Add a reply…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.ember, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ember))
                : const Icon(Icons.send, color: AppColors.ember),
            tooltip: 'Send',
          ),
        ],
      ),
          ],
        ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.reply,
    required this.canDelete,
    required this.onDelete,
    required this.onMore,
    required this.onVote,
    required this.onReply,
  });

  final ClubReply reply;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onMore;
  final ValueChanged<int> onVote;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onMore,
      behavior: HitTestBehavior.opaque,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(name: reply.authorName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      reply.authorName ?? 'Member',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.cream),
                    ),
                    const SizedBox(width: 8),
                    Text(timeAgo(reply.createdAt),
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                    const Spacer(),
                    if (canDelete)
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(Icons.delete_outline, size: 18, color: AppColors.steel),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(reply.body,
                    style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.45)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _VoteBar(
                      score: reply.score,
                      myVote: reply.myVote,
                      onUp: () => onVote(1),
                      onDown: () => onVote(-1),
                    ),
                    if (onReply != null) ...[
                      const SizedBox(width: 14),
                      InkWell(
                        onTap: onReply,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                          child: Text('Reply',
                              style: GoogleFonts.inter(
                                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.steel)),
                        ),
                      ),
                    ],
                  ],
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

/// Thumbs up / score / thumbs down for a reply.
class _VoteBar extends StatelessWidget {
  const _VoteBar({
    required this.score,
    required this.myVote,
    required this.onUp,
    required this.onDown,
  });

  final int score;
  final int myVote;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VoteButton(
          icon: myVote == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
          active: myVote == 1,
          onTap: onUp,
        ),
        const SizedBox(width: 8),
        Text(
          '$score',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: myVote == 1
                ? AppColors.ember
                : myVote == -1
                    ? AppColors.steel
                    : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        _VoteButton(
          icon: myVote == -1 ? Icons.thumb_down : Icons.thumb_down_outlined,
          active: myVote == -1,
          onTap: onDown,
        ),
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 18, color: active ? AppColors.ember : AppColors.steel),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final letter = (name != null && name!.isNotEmpty) ? name![0].toUpperCase() : '?';
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(color: AppColors.graphiteRaised, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(letter,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.steel)),
    );
  }
}
