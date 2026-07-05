import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/models/club_thread.dart';
import 'package:torqueden/screens/club_manage_screen.dart';
import 'package:torqueden/screens/thread_detail_screen.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/time_ago.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/moderation_sheet.dart';

/// A club's page: header + Join/Leave, then its discussion threads. Members can
/// start a thread; the owner can delete any thread.
class ClubDetailScreen extends StatefulWidget {
  const ClubDetailScreen({super.key, required this.club});

  final Club club;

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  final _client = Supabase.instance.client;

  late Club _club;
  late Future<List<ClubThread>> _future;
  bool _member = false;
  int _memberCount = 0;
  bool _joining = false;

  String? get _uid => _client.auth.currentUser?.id;
  bool get _isOwner => _uid != null && _uid == _club.ownerId;
  bool get _canPost => _member && (!_club.isLocked || _isOwner);

  @override
  void initState() {
    super.initState();
    _club = widget.club;
    _memberCount = _club.memberCount;
    _future = _load();
  }

  Future<List<ClubThread>> _load() async {
    await Moderation.refreshBlocks();
    // Membership + member count.
    final members =
        await _client.from('club_members').select('user_id').eq('club_id', _club.id);
    _member = _uid != null && members.any((m) => m['user_id'] == _uid);
    _memberCount = members.length;

    final rows = await _client
        .from('club_threads')
        .select('*, author:profiles(username), club_replies(count)')
        .eq('club_id', _club.id)
        .order('created_at', ascending: false);
    if (mounted) setState(() {}); // reflect membership/count
    return rows
        .map(ClubThread.fromMap)
        .where((t) => !Moderation.isBlocked(t.authorId))
        .toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _toggleMembership() async {
    if (_uid == null || _joining) return;
    setState(() => _joining = true);
    final wasMember = _member;
    try {
      if (wasMember) {
        await _client
            .from('club_members')
            .delete()
            .eq('club_id', _club.id)
            .eq('user_id', _uid!);
      } else {
        await _client.from('club_members').insert({'club_id': _club.id});
      }
      if (!mounted) return;
      setState(() {
        _member = !wasMember;
        _memberCount += wasMember ? -1 : 1;
        _joining = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update membership: $e')));
    }
  }

  Future<void> _ask() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AskSheet(clubId: _club.id),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _manage() async {
    final result = await Navigator.of(context).push<ClubManageResult>(
      MaterialPageRoute(builder: (_) => ClubManageScreen(club: _club)),
    );
    if (result == null || !mounted) return;
    if (result.deleted) {
      Navigator.of(context).pop(); // close the club → back to the list
      return;
    }
    if (result.club != null) setState(() => _club = result.club!);
    await _refresh();
  }

  Future<void> _deleteThread(ClubThread thread) async {
    try {
      await _client.from('club_threads').delete().eq('id', thread.id);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  void _moderateThread(ClubThread thread) {
    showModerationSheet(
      context,
      targetType: 'thread',
      targetId: thread.id,
      authorId: thread.authorId,
      authorName: thread.authorName,
      onBlocked: _refresh,
    );
  }

  Future<void> _openThread(ClubThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          thread: thread,
          canPost: _canPost,
          isOwner: _isOwner,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_club.name),
        actions: [
          if (_isOwner)
            IconButton(
              onPressed: _manage,
              icon: const Icon(Icons.tune),
              tooltip: 'Manage club',
            ),
        ],
      ),
      floatingActionButton: _canPost
          ? FloatingActionButton.extended(
              onPressed: _ask,
              backgroundColor: AppColors.ember,
              foregroundColor: AppColors.onEmber,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Ask'),
            )
          : null,
      body: SafeArea(
        child: FutureBuilder<List<ClubThread>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final threads = snapshot.data ?? const <ClubThread>[];
            return RefreshIndicator(
              color: AppColors.ember,
              backgroundColor: AppColors.graphite,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _header(),
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.hairline),
                  const SizedBox(height: 8),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Center(child: CircularProgressIndicator(color: AppColors.ember)),
                    )
                  else if (snapshot.hasError)
                    EmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load threads',
                      message: '${snapshot.error}',
                      action: FilledButton(onPressed: _refresh, child: const Text('Try again')),
                    )
                  else if (threads.isEmpty)
                    EmptyState(
                      icon: Icons.forum_outlined,
                      title: 'No threads yet',
                      message: _canPost
                          ? 'Start the first discussion with the Ask button.'
                          : _club.isLocked
                              ? 'This club is locked — posting is closed.'
                              : 'Join the club to start a discussion.',
                    )
                  else
                    for (final t in threads) ...[
                      _ThreadRow(
                        thread: t,
                        canDelete: _isOwner || t.authorId == _uid,
                        onTap: () => _openThread(t),
                        onDelete: () => _deleteThread(t),
                        onMore: () => _moderateThread(t),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    final desc = _club.description?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _club.name,
                style: GoogleFonts.archivo(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.cream),
              ),
            ),
            if (_club.isLocked) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.graphiteRaised,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 13, color: AppColors.steel),
                    const SizedBox(width: 5),
                    Text('Locked',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.steel)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$_memberCount ${_memberCount == 1 ? 'member' : 'members'}',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
        ),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(desc, style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.45)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _member
              ? OutlinedButton(
                  onPressed: _joining ? null : _toggleMembership,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.steel,
                    side: const BorderSide(color: AppColors.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(_isOwner ? 'Owner' : 'Leave club'),
                )
              : FilledButton(
                  onPressed: _joining ? null : _toggleMembership,
                  child: const Text('Join club'),
                ),
        ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
    required this.onMore,
  });

  final ClubThread thread;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.graphite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.cream),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${thread.authorName ?? 'Member'} · ${timeAgo(thread.createdAt)} · '
                    '${thread.replyCount} ${thread.replyCount == 1 ? 'reply' : 'replies'}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (canDelete)
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: AppColors.steel,
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete thread',
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 2),
                child: Icon(Icons.chevron_right, color: AppColors.steel),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to start a thread. Pops `true` on success.
class _AskSheet extends StatefulWidget {
  const _AskSheet({required this.clubId});
  final String clubId;

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final body = _body.text.trim();
    try {
      await Supabase.instance.client.from('club_threads').insert({
        'club_id': widget.clubId,
        'title': _title.text.trim(),
        'body': body.isEmpty ? null : body,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not post: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Start a thread',
                  style: GoogleFonts.archivo(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.cream)),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a title' : null,
                decoration: const InputDecoration(labelText: 'Title *', hintText: 'Ask a question or start a topic'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _body,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'Add context…'),
              ),
              const SizedBox(height: 20),
              if (_saving)
                const Center(child: CircularProgressIndicator(color: AppColors.ember))
              else
                FilledButton(onPressed: _post, child: const Text('Post thread')),
            ],
          ),
        ),
      ),
    );
  }
}
