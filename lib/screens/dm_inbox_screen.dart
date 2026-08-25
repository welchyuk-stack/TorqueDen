import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/dm.dart';
import 'package:torqueden/screens/dm_thread_screen.dart';
import 'package:torqueden/services/dm_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/time_ago.dart';
import 'package:torqueden/screens/auth/auth_screen.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// The DM inbox: a list of conversations sorted by most recent message.
/// Unread threads are bolded. Tapping opens [DmThreadScreen].
class DmInboxScreen extends StatefulWidget {
  const DmInboxScreen({super.key});

  /// Fire this to trigger a reload from anywhere (e.g. when the tab is selected
  /// after a DM was opened from outside the inbox via DmService.openOrCreate).
  static final refreshSignal = StreamController<void>.broadcast();

  @override
  State<DmInboxScreen> createState() => _DmInboxScreenState();
}

class _DmInboxScreenState extends State<DmInboxScreen> {
  StreamSubscription<void>? _refreshSub;
  final _client = Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  List<DmThread> _threads = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshSub = DmInboxScreen.refreshSignal.stream.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      // Fetch threads with both participant profiles joined, plus a snapshot
      // of the last message body and unread count for the preview row.
      final rows = await _client
          .from('dm_threads')
          .select('''
            id, participant_a, participant_b, last_message_at,
            profile_a:participant_a(id, username, display_name, avatar_url),
            profile_b:participant_b(id, username, display_name, avatar_url),
            last_body:dm_messages(body, created_at)
          ''')
          .or('participant_a.eq.$uid,participant_b.eq.$uid')
          .order('last_message_at', ascending: false);

      // Fetch unread counts per thread separately (aggregate not easy inline).
      final threadIds = (rows as List).map((r) => r['id'] as String).toList();
      Map<String, int> unreadMap = {};
      if (threadIds.isNotEmpty) {
        final unreadRows = await _client
            .from('dm_messages')
            .select('thread_id')
            .inFilter('thread_id', threadIds)
            .neq('sender_id', uid)
            .isFilter('read_at', null);
        for (final r in unreadRows as List) {
          final tid = r['thread_id'] as String;
          unreadMap[tid] = (unreadMap[tid] ?? 0) + 1;
        }
      }

      final threads = (rows).map((r) {
        // last_body is a list from the join — pick the most recent.
        final msgs = (r['last_body'] as List?) ?? [];
        String? lastBody;
        if (msgs.isNotEmpty) {
          msgs.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
          lastBody = msgs.first['body'] as String?;
        }
        final enriched = Map<String, dynamic>.from(r as Map)
          ..['last_body'] = lastBody
          ..['unread_count'] = unreadMap[r['id'] as String] ?? 0;
        return DmThread.fromMap(enriched, uid);
      }).toList();

      if (mounted) setState(() { _threads = threads; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<bool> _confirmDelete(DmThread thread) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.graphite,
            title: Text('Delete conversation?',
                style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream)),
            content: Text(
              'This removes your conversation with ${thread.displayName}. Messages will be deleted for both sides.',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteThread(DmThread thread) async {
    try {
      await DmService.deleteThread(thread.id);
      setState(() => _threads.removeWhere((t) => t.id == thread.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete conversation: $e')),
      );
      _load();
    }
  }

  Future<void> _openThread(DmThread thread) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DmThreadScreen(thread: thread)),
    );
    // Refresh inbox on return so unread counts update.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('Messages', style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.hairline),
        ),
      ),
      body: _uid == null
          ? _GuestPrompt(onSignIn: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen())))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.ember,
              child: _error != null
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: EmptyState(
                          icon: Icons.error_outline,
                          title: 'Could not load messages',
                          message: 'Check your connection and try again.',
                          action: FilledButton(onPressed: _load, child: const Text('Try again')),
                        ),
                      ),
                    ])
                  : _threads.isEmpty
                      ? ListView(children: [const Padding(padding: EdgeInsets.only(top: 80), child: EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', message: 'Open someone\'s car and tap the message icon to start a conversation.'))])
                      : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _threads.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.hairline, indent: 72),
                        itemBuilder: (_, i) {
                          final thread = _threads[i];
                          return Dismissible(
                            key: ValueKey(thread.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: AppColors.danger,
                              child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
                            ),
                            confirmDismiss: (_) => _confirmDelete(thread),
                            onDismissed: (_) => _deleteThread(thread),
                            child: _ThreadTile(
                              thread: thread,
                              onTap: () => _openThread(thread),
                            ),
                          );
                        },
                      ),
              ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onTap});
  final DmThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = thread.unreadCount > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.graphiteRaised,
              backgroundImage: thread.otherAvatarUrl != null
                  ? NetworkImage(thread.otherAvatarUrl!)
                  : null,
              child: thread.otherAvatarUrl == null
                  ? Text(
                      thread.displayName.characters.first.toUpperCase(),
                      style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream, fontSize: 18),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Name + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.displayName,
                          style: GoogleFonts.archivo(
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 15,
                            color: AppColors.cream,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeAgo(thread.lastMessageAt),
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          thread.lastBody ?? 'Start a conversation',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: hasUnread ? AppColors.cream : AppColors.steel,
                            fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.ember,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${thread.unreadCount}',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onEmber),
                          ),
                        ),
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

class _GuestPrompt extends StatelessWidget {
  const _GuestPrompt({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 52, color: AppColors.steel),
            const SizedBox(height: 16),
            Text(
              'Sign in to message',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.cream,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Create an account or log in to send and receive messages.',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onSignIn,
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              child: const Text('Sign in / Create account'),
            ),
          ],
        ),
      ),
    );
  }
}
