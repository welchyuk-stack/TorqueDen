import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/models/club_thread.dart';
import 'package:torqueden/screens/club_manage_screen.dart';
import 'package:torqueden/screens/thread_detail_screen.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/post_error.dart';
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
  bool _isAdmin = false;
  int _memberCount = 0;
  int _online = 0;
  bool _joining = false;
  RealtimeChannel? _presence;

  String? get _uid => _client.auth.currentUser?.id;
  bool get _isOwner => _uid != null && _uid == _club.ownerId;
  bool get _isMod => _isOwner || _isAdmin;
  bool get _canPost => _member && !_club.isArchived && (!_club.isLocked || _isMod);

  @override
  void initState() {
    super.initState();
    _club = widget.club;
    _memberCount = _club.memberCount;
    _future = _load();
    _joinPresence();
  }

  @override
  void dispose() {
    final ch = _presence;
    if (ch != null) _client.removeChannel(ch);
    super.dispose();
  }

  /// Live "online" count for this club via Realtime presence — members
  /// currently viewing the club are tracked on a shared channel.
  void _joinPresence() {
    final uid = _uid;
    if (uid == null) return;
    final ch = _client.channel('club-presence-${_club.id}');
    ch.onPresenceSync((_) {
      final ids = <String>{};
      for (final state in ch.presenceState()) {
        for (final p in state.presences) {
          final u = p.payload['user_id'];
          if (u is String) ids.add(u);
        }
      }
      if (mounted) setState(() => _online = ids.length);
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await ch.track({'user_id': uid});
      }
    });
    _presence = ch;
  }

  Future<List<ClubThread>> _load() async {
    await Moderation.refreshBlocks();
    // Membership + role + member count.
    final members =
        await _client.from('club_members').select('user_id, role').eq('club_id', _club.id);
    _member = _uid != null && members.any((m) => m['user_id'] == _uid);
    _isAdmin = _uid != null &&
        members.any((m) => m['user_id'] == _uid && m['role'] == 'admin');
    _memberCount = members.length;

    final rows = await _client
        .from('club_threads')
        .select('*, author:profiles(username), club_replies(count)')
        .eq('club_id', _club.id)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);
    if (mounted) setState(() {}); // reflect membership/count
    return rows
        .map(ClubThread.fromMap)
        .where((t) => !Moderation.isBlocked(t.authorId))
        .toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() { _future = future; });
    await future;
  }

  Future<void> _toggleMembership() async {
    if (_uid == null || _joining) return;
    setState(() { _joining = true; });
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
      setState(() { _joining = false; });
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
    if (result.club != null) setState(() { _club = result.club!; });
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

  void _showRules() {
    final rules = _club.rules?.trim() ?? '';
    if (rules.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gavel_outlined, size: 18, color: AppColors.ember),
                  const SizedBox(width: 8),
                  Text('Club Rules',
                      style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(rules,
                      style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary, height: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          canModerate: _isMod,
        ),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canPost
          ? FloatingActionButton.extended(
              onPressed: _ask,
              backgroundColor: AppColors.ember,
              foregroundColor: AppColors.onEmber,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Ask'),
            )
          : null,
      body: FutureBuilder<List<ClubThread>>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final threads = snapshot.data ?? const <ClubThread>[];
          final desc = _club.description?.trim() ?? '';
          return RefreshIndicator(
            color: AppColors.ember,
            backgroundColor: AppColors.graphite,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _banner(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (desc.isNotEmpty) ...[
                        Text(desc,
                            style: GoogleFonts.inter(
                                fontSize: 15, color: AppColors.textSecondary, height: 1.45)),
                        const SizedBox(height: 16),
                      ],
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
                            canDelete: _isMod || t.authorId == _uid,
                            onTap: () => _openThread(t),
                            onDelete: () => _deleteThread(t),
                            onMore: () => _moderateThread(t),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The club header: a banner image (top 25%) with the name + rules up top and
  /// member/online + join control along the bottom.
  Widget _banner(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final height = MediaQuery.sizeOf(context).height * 0.25 + topPad;
    final online = _online > 0
        ? '  ·  ${_online == 1 ? '1 online' : '$_online online'}'
        : '';
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_club.hasBanner)
            Image.network(_club.bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _BannerFallback())
          else
            const _BannerFallback(),
          // Legibility scrim, darker top and bottom.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent, Colors.black87],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, topPad + 6, 12, 12),
            child: Column(
              children: [
                // Top: back · name (left)  ·  rules · manage (right)
                Row(
                  children: [
                    _CircleBtn(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _club.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.archivo(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.cream,
                          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
                        ),
                      ),
                    ),
                    if (_club.rules?.trim().isNotEmpty == true) ...[
                      const SizedBox(width: 6),
                      _RulesButton(onTap: _showRules),
                    ],
                    if (_isOwner) ...[
                      const SizedBox(width: 6),
                      _CircleBtn(icon: Icons.tune, onTap: _manage),
                    ],
                  ],
                ),
                const Spacer(),
                // Bottom: members · online (left)  ·  join / owner (right)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (_club.isLocked) const _MiniChip(icon: Icons.lock, label: 'Locked'),
                          if (_club.isArchived) const _MiniChip(icon: Icons.inventory_2_outlined, label: 'Archived'),
                          Flexible(
                            child: Text(
                              '$_memberCount ${_memberCount == 1 ? 'member' : 'members'}$online',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.cream,
                                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _joinControl(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _joinControl() {
    if (_isOwner) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('Owner',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.cream)),
      );
    }
    if (_member) {
      return TextButton(
        onPressed: _joining ? null : _toggleMembership,
        style: TextButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.45),
          foregroundColor: AppColors.cream,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: const Text('Leave'),
      );
    }
    return FilledButton(
      onPressed: _joining ? null : _toggleMembership,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: const Text('Join'),
    );
  }
}

/// Fallback banner background (ember-tinted gradient) when no image is set.
class _BannerFallback extends StatelessWidget {
  const _BannerFallback();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2016), AppColors.carbon],
        ),
      ),
    );
  }
}

/// Small translucent circular icon button used over the banner.
class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.cream),
        ),
      ),
    );
  }
}

/// Small status chip (Locked / Archived) shown over the banner.
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppColors.cream),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.cream)),
      ]),
    );
  }
}

/// A small pill button that opens the club rules.
class _RulesButton extends StatelessWidget {
  const _RulesButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.ember.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.ember.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.gavel_outlined, size: 13, color: AppColors.ember),
            const SizedBox(width: 5),
            Text('Club Rules',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ember)),
          ],
        ),
      ),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (thread.isPinned) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 6),
                          child: Icon(Icons.push_pin, size: 14, color: AppColors.ember),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          thread.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.cream),
                        ),
                      ),
                    ],
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
    setState(() { _saving = true; });
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
      setState(() { _saving = false; });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyPostError(e))));
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
