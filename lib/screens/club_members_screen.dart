import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/services/club_mod_log.dart';
import 'package:torqueden/theme.dart';

/// Returned when the members screen closes: whether anything changed (so the
/// Manage screen can refresh its banned/muted lists), and — if ownership was
/// handed over — the updated club.
class ClubMembersResult {
  const ClubMembersResult({this.changed = false, this.transferredClub});
  final bool changed;
  final Club? transferredClub;
}

/// Full-screen member list for a club with a search box. Owner/admins manage
/// roles, mutes, bans and removals here (moved out of the Manage screen).
class ClubMembersScreen extends StatefulWidget {
  const ClubMembersScreen({super.key, required this.club});

  final Club club;

  @override
  State<ClubMembersScreen> createState() => _ClubMembersScreenState();
}

class _ClubMembersScreenState extends State<ClubMembersScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  late Future<List<_Member>> _future;
  String _query = '';
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _query) setState(() { _query = q; });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_Member>> _load() async {
    final rows = await _client
        .from('club_members')
        .select('user_id, role, profiles(username)')
        .eq('club_id', widget.club.id)
        .order('joined_at');
    return rows.map((r) {
      final p = r['profiles'];
      return _Member(
        userId: r['user_id'] as String,
        role: r['role'] as String? ?? 'member',
        username: p is Map ? p['username'] as String? : null,
      );
    }).toList();
  }

  void _reload() => setState(() { _future = _load(); });

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  List<_Member> _visible(List<_Member> members) {
    if (_query.isEmpty) return members;
    final n = _query.toLowerCase();
    return members.where((m) => (m.username ?? 'member').toLowerCase().contains(n)).toList();
  }

  Future<void> _setRole(_Member m, String role) async {
    try {
      await _client
          .from('club_members')
          .update({'role': role})
          .eq('club_id', widget.club.id)
          .eq('user_id', m.userId);
      ClubModLog.record(widget.club.id, role == 'admin' ? 'make_admin' : 'remove_admin', targetUserId: m.userId);
      _changed = true;
      _reload();
    } catch (e) {
      _snack('Could not update role: $e');
    }
  }

  Future<void> _ban(_Member m) async {
    try {
      await _client.from('club_bans').insert({'club_id': widget.club.id, 'user_id': m.userId});
      await _client.from('club_members').delete().eq('club_id', widget.club.id).eq('user_id', m.userId);
      ClubModLog.record(widget.club.id, 'ban', targetUserId: m.userId);
      _changed = true;
      _reload();
    } catch (e) {
      _snack('Could not ban: $e');
    }
  }

  Future<void> _mute(_Member m) async {
    final hours = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final opt in const [(1, 'Mute for 1 hour'), (24, 'Mute for 1 day'), (168, 'Mute for 7 days')])
              ListTile(title: Text(opt.$2), onTap: () => Navigator.pop(ctx, opt.$1)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (hours == null) return;
    final until = DateTime.now().toUtc().add(Duration(hours: hours));
    try {
      await _client.from('club_mutes').upsert(
        {'club_id': widget.club.id, 'user_id': m.userId, 'until': until.toIso8601String()},
        onConflict: 'club_id,user_id',
      );
      ClubModLog.record(widget.club.id, 'mute', targetUserId: m.userId, detail: '${hours}h');
      _changed = true;
      _snack('Muted ${m.username ?? 'member'}');
    } catch (e) {
      _snack('Could not mute: $e');
    }
  }

  Future<void> _removeMember(_Member m) async {
    try {
      await _client
          .from('club_members')
          .delete()
          .eq('club_id', widget.club.id)
          .eq('user_id', m.userId);
      ClubModLog.record(widget.club.id, 'remove', targetUserId: m.userId);
      _changed = true;
      _reload();
    } catch (e) {
      _snack('Could not remove member: $e');
    }
  }

  Future<void> _transferOwnership(_Member m) async {
    final name = m.username ?? 'this member';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Make $name the owner?',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text('You\'ll become a regular member and lose admin control of this club.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Transfer', style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final me = _client.auth.currentUser!.id;
    try {
      // Roles first (while still owner), then hand over owner_id.
      await _client.from('club_members').update({'role': 'owner'}).eq('club_id', widget.club.id).eq('user_id', m.userId);
      await _client.from('club_members').update({'role': 'member'}).eq('club_id', widget.club.id).eq('user_id', me);
      final rows = await _client
          .from('clubs')
          .update({'owner_id': m.userId})
          .eq('id', widget.club.id)
          .select('*, club_members(count)');
      ClubModLog.record(widget.club.id, 'transfer', targetUserId: m.userId);
      if (mounted) {
        Navigator.of(context).pop(ClubMembersResult(changed: true, transferredClub: Club.fromMap(rows.first)));
      }
    } catch (e) {
      _snack('Could not transfer ownership: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(ClubMembersResult(changed: _changed));
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Members')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  cursorColor: AppColors.ember,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.graphiteRaised,
                    hintText: 'Search members…',
                    prefixIcon: const Icon(Icons.search, color: AppColors.steel),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.ember, width: 1.5),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<_Member>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.ember));
                    }
                    final all = snapshot.data ?? const <_Member>[];
                    final visible = _visible(all);
                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          _query.isEmpty ? 'No members yet.' : 'No members match “$_query”.',
                          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final m = visible[i];
                        return _MemberRow(
                          member: m,
                          onRemove: () => _removeMember(m),
                          onMakeOwner: () => _transferOwnership(m),
                          onToggleAdmin: () => _setRole(m, m.role == 'admin' ? 'member' : 'admin'),
                          onBan: () => _ban(m),
                          onMute: () => _mute(m),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Member {
  const _Member({required this.userId, required this.role, this.username});
  final String userId;
  final String role;
  final String? username;
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.onRemove,
    required this.onMakeOwner,
    required this.onToggleAdmin,
    required this.onBan,
    required this.onMute,
  });
  final _Member member;
  final VoidCallback onRemove;
  final VoidCallback onMakeOwner;
  final VoidCallback onToggleAdmin;
  final VoidCallback onBan;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final name = member.username ?? 'Member';
    final isOwner = member.role == 'owner';
    final isAdmin = member.role == 'admin';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(color: AppColors.graphiteRaised, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.inter(color: AppColors.steel, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
          ),
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('Admin',
                  style: GoogleFonts.inter(color: AppColors.steel, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          if (isOwner)
            Text('Owner', style: GoogleFonts.inter(color: AppColors.ember, fontSize: 12, fontWeight: FontWeight.w700))
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.steel, size: 20),
              color: AppColors.graphiteRaised,
              onSelected: (v) => switch (v) {
                'owner' => onMakeOwner(),
                'admin' => onToggleAdmin(),
                'mute' => onMute(),
                'ban' => onBan(),
                _ => onRemove(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'admin', child: Text(isAdmin ? 'Remove admin' : 'Make admin')),
                const PopupMenuItem(value: 'owner', child: Text('Make owner')),
                const PopupMenuItem(value: 'mute', child: Text('Mute…')),
                const PopupMenuItem(value: 'remove', child: Text('Remove from club')),
                const PopupMenuItem(value: 'ban', child: Text('Ban from club')),
              ],
            ),
        ],
      ),
    );
  }
}
