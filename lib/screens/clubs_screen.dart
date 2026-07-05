import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/screens/club_detail_screen.dart';
import 'package:torqueden/screens/create_club_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/settings_button.dart';

/// Clubs tab — browse and search public clubs (Discover) or the ones you've
/// joined (My Clubs), and create your own.
class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  late Future<_ClubsData> _future;
  String _query = '';
  int _tab = 0; // 0 Discover · 1 My Clubs · 2 Owned

  String? get _uid => _client.auth.currentUser?.id;

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

  Future<_ClubsData> _load() async {
    final uid = _client.auth.currentUser?.id;
    final rows = await _client
        .from('clubs')
        .select('*, club_members(count)')
        .order('created_at', ascending: false);
    final clubs = rows.map(Club.fromMap).toList();

    final mine = <String>{};
    if (uid != null) {
      final memberships =
          await _client.from('club_members').select('club_id').eq('user_id', uid);
      for (final m in memberships) {
        mine.add(m['club_id'] as String);
      }
    }
    return _ClubsData(clubs: clubs, myClubIds: mine);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() { _future = future; });
    await future;
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Club>(
      MaterialPageRoute(builder: (_) => const CreateClubScreen()),
    );
    if (created != null && mounted) {
      await _openClub(created);
      await _refresh();
    }
  }

  Future<void> _openClub(Club club) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClubDetailScreen(club: club)),
    );
    await _refresh();
  }

  List<Club> _visible(_ClubsData data) {
    var list = data.clubs;
    if (_tab == 1) {
      list = list.where((c) => data.myClubIds.contains(c.id)).toList();
    } else if (_tab == 2) {
      list = list.where((c) => c.ownerId == _uid).toList();
    }
    if (_query.isNotEmpty) {
      final n = _query.toLowerCase();
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(n) ||
              (c.description ?? '').toLowerCase().contains(n))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clubs'),
        actions: [
          IconButton(
            onPressed: _create,
            icon: const Icon(Icons.add),
            tooltip: 'Create a club',
          ),
          const SettingsButton(),
        ],
      ),
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
                  hintText: 'Search clubs…',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _Segment(label: 'Discover', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                  const SizedBox(width: 8),
                  _Segment(label: 'My Clubs', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
                  const SizedBox(width: 8),
                  _Segment(label: 'Owned', selected: _tab == 2, onTap: () => setState(() => _tab = 2)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_ClubsData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.ember));
                  }
                  if (snapshot.hasError) {
                    return _scrollable(EmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load clubs',
                      message: '${snapshot.error}',
                      action: FilledButton(onPressed: _refresh, child: const Text('Try again')),
                    ));
                  }
                  final data = snapshot.data ?? const _ClubsData(clubs: [], myClubIds: {});
                  final visible = _visible(data);
                  if (visible.isEmpty) {
                    return _scrollable(EmptyState(
                      icon: Icons.groups_outlined,
                      title: switch (_tab) {
                        1 => 'You haven\'t joined a club yet',
                        2 => 'You don\'t own any clubs yet',
                        _ => 'No clubs yet',
                      },
                      message: _tab == 0
                          ? 'Be the first — create a club for your crew.'
                          : 'Find one in Discover, or start your own.',
                      action: FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Create a club'),
                      ),
                    ));
                  }
                  return RefreshIndicator(
                    color: AppColors.ember,
                    backgroundColor: AppColors.graphite,
                    onRefresh: _refresh,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ClubCard(
                        club: visible[i],
                        joined: data.myClubIds.contains(visible[i].id),
                        onTap: () => _openClub(visible[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrollable(Widget child) {
    return RefreshIndicator(
      color: AppColors.ember,
      backgroundColor: AppColors.graphite,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: c.maxHeight), child: child),
        ),
      ),
    );
  }
}

class _ClubsData {
  const _ClubsData({required this.clubs, required this.myClubIds});
  final List<Club> clubs;
  final Set<String> myClubIds;
}

class _Segment extends StatelessWidget {
  const _Segment({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ember : AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.ember : AppColors.hairline),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onEmber : AppColors.steel,
          ),
        ),
      ),
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.joined, required this.onTap});
  final Club club;
  final bool joined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.graphite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            _ClubAvatar(club: club),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          club.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.archivo(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.cream,
                          ),
                        ),
                      ),
                      if (club.isPrivate) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock, size: 14, color: AppColors.steel),
                      ],
                      if (joined) ...[
                        const SizedBox(width: 8),
                        const _JoinedTick(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    club.description?.trim().isNotEmpty == true
                        ? club.description!.trim()
                        : 'No description yet',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${club.memberCount} ${club.memberCount == 1 ? 'member' : 'members'}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
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

class _JoinedTick extends StatelessWidget {
  const _JoinedTick();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ember.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Joined',
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ember),
      ),
    );
  }
}

class _ClubAvatar extends StatelessWidget {
  const _ClubAvatar({required this.club});
  final Club club;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 52,
        height: 52,
        child: club.hasAvatar
            ? Image.network(club.avatarUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback())
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: Text(
        club.name.isNotEmpty ? club.name[0].toUpperCase() : '#',
        style: GoogleFonts.archivo(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ember),
      ),
    );
  }
}
