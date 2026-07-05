import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club_reply.dart';
import 'package:torqueden/models/club_thread.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/time_ago.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';

/// A club thread: the question/post up top, its replies below, and a reply box
/// for members. [canPost] gates the reply box; [isOwner] can delete any reply.
class ThreadDetailScreen extends StatefulWidget {
  const ThreadDetailScreen({
    super.key,
    required this.thread,
    required this.canPost,
    required this.isOwner,
  });

  final ClubThread thread;
  final bool canPost;
  final bool isOwner;

  @override
  State<ThreadDetailScreen> createState() => _ThreadDetailScreenState();
}

class _ThreadDetailScreenState extends State<ThreadDetailScreen> {
  final _client = Supabase.instance.client;
  final _input = TextEditingController();

  late Future<List<ClubReply>> _future;
  bool _sending = false;
  late bool _pinned = widget.thread.isPinned;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _future = _load();
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

  Future<List<ClubReply>> _load() async {
    await Moderation.refreshBlocks();
    final rows = await _client
        .from('club_replies')
        .select('*, author:profiles(username)')
        .eq('thread_id', widget.thread.id)
        .order('created_at', ascending: true);
    return rows
        .map(ClubReply.fromMap)
        .where((r) => !Moderation.isBlocked(r.authorId))
        .toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _client.from('club_replies').insert({
        'thread_id': widget.thread.id,
        'body': text,
      });
      if (!mounted) return;
      _input.clear();
      FocusScope.of(context).unfocus();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not post your reply: $e')));
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

  @override
  Widget build(BuildContext context) {
    final t = widget.thread;
    final body = t.body?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thread'),
        actions: [
          if (widget.isOwner)
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
              child: FutureBuilder<List<ClubReply>>(
                future: _future,
                builder: (context, snapshot) {
                  final replies = snapshot.data ?? const <ClubReply>[];
                  return RefreshIndicator(
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
                              replies.isEmpty
                                  ? 'Replies'
                                  : '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                              style: GoogleFonts.inter(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.steel),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(child: Divider(color: AppColors.hairline)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.only(top: 30),
                            child: Center(child: CircularProgressIndicator(color: AppColors.ember)),
                          )
                        else if (replies.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text(
                              widget.canPost ? 'No replies yet — be the first.' : 'No replies yet.',
                              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
                            ),
                          )
                        else
                          for (final r in replies)
                            _ReplyTile(
                              reply: r,
                              canDelete: widget.isOwner || r.authorId == _uid,
                              onDelete: () => _deleteReply(r),
                              onMore: () => showModerationSheet(
                                context,
                                targetType: 'reply',
                                targetId: r.id,
                                authorId: r.authorId,
                                authorName: r.authorName,
                                onBlocked: _refresh,
                              ),
                            ),
                      ],
                    ),
                  );
                },
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
      child: Row(
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
                hintText: 'Add a reply…',
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
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({
    required this.reply,
    required this.canDelete,
    required this.onDelete,
    required this.onMore,
  });

  final ClubReply reply;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onMore;

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
              ],
            ),
          ),
        ],
      ),
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
