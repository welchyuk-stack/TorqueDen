import 'dart:io';
import 'dart:ui' as dart_ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/challenge.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/create_post_screen.dart';
import 'package:torqueden/screens/post_viewer_screen.dart';
import 'package:torqueden/services/challenge_service.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Converts a raw Supabase storage URL to a resized thumbnail URL.
String _thumb(String url, {int width = 600, int quality = 75}) {
  final t = url.replaceFirst(
    '/storage/v1/object/public/',
    '/storage/v1/render/image/public/',
  );
  if (t == url) return url;
  return '$t?width=$width&quality=$quality&resize=contain';
}

class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key, required this.challenge});
  final Challenge challenge;

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Future<_ChallengeData> _future;
  _ChallengeData? _data;
  Future<_ResultsData>? _resultsFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _future = _load();
    _resultsFuture = _loadResults();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_ChallengeData> _load() async {
    final svc = ChallengeService.instance;
    final entries = await svc.fetchEntries(widget.challenge);
    Map<String, dynamic>? winner;
    if (widget.challenge.winnerEntryId != null) {
      winner = await svc.fetchWinnerEntry(widget.challenge.winnerEntryId!);
    }
    final votes = await svc.fetchVoteCounts(widget.challenge.id);
    final myVote = await svc.fetchMyVote(widget.challenge.id);
    final result = _ChallengeData(entries: entries, winner: winner, votes: votes, myVote: myVote);
    _data = result;
    return result;
  }

  Future<_ResultsData> _loadResults() async {
    final svc = ChallengeService.instance;
    final subject = widget.challenge.isEnded
        ? widget.challenge
        : await svc.fetchPrevious();
    if (subject == null) return const _ResultsData(challenge: null, top3: [], all: []);
    final entries = await svc.fetchEntries(subject);
    final votes = await svc.fetchVoteCounts(subject.id);
    entries.sort((a, b) => (votes[b['id']] ?? 0).compareTo(votes[a['id']] ?? 0));
    final all = entries.map((e) => {...e, '_vote_count': votes[e['id']] ?? 0}).toList();
    return _ResultsData(challenge: subject, top3: all.take(3).toList(), all: all);
  }

  Future<void> _castVote(String entryId) async {
    if (GuestMode.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to vote')),
      );
      return;
    }
    await ChallengeService.instance.castVote(
      challengeId: widget.challenge.id,
      entryId: entryId,
    );
    final svc = ChallengeService.instance;
    final votes = await svc.fetchVoteCounts(widget.challenge.id);
    final myVote = await svc.fetchMyVote(widget.challenge.id);
    if (!mounted) return;
    setState(() {
      _data = _ChallengeData(
        entries: _data?.entries ?? [],
        winner: _data?.winner,
        votes: votes,
        myVote: myVote,
      );
      _future = Future.value(_data!);
    });
  }

  Future<void> _deleteEntry(String entryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove your entry?'),
        content: const Text('This will withdraw your entry from The Shot. You can re-enter while the challenge is still open.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ChallengeService.instance.deleteEntry(entryId);
    if (!mounted) return;
    setState(() { _future = _load(); });
  }

  void _enter() {
    if (GuestMode.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to enter the challenge')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(challengeTag: widget.challenge.tag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(fontSize: 20),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.ember,
          labelColor: AppColors.ember,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Entries'),
            Tab(text: 'Results'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _entriesTab(c),
          _resultsTab(),
        ],
      ),
      bottomNavigationBar: (c.isActive && _tabs.index == 0)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _enter,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Enter The Shot'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _resultsTab() {
    return FutureBuilder<_ResultsData>(
      future: _resultsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.ember));
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Could not load results',
            message: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => setState(() { _resultsFuture = _loadResults(); }),
              child: const Text('Try again'),
            ),
          );
        }
        final data = snap.data;
        if (data == null || data.challenge == null || data.top3.isEmpty) {
          return const EmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'No results yet',
            message: 'Results appear here once a Shot challenge ends.',
          );
        }
        final myUid = Supabase.instance.client.auth.currentUser?.id;
        return _PodiumView(
          challenge: data.challenge!,
          top3: data.top3,
          all: data.all,
          myUid: myUid,
        );
      },
    );
  }

  Widget _entriesTab(Challenge c) {
    return FutureBuilder<_ChallengeData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && _data == null) {
            return const Center(child: CircularProgressIndicator(color: AppColors.ember));
          }
          if (snap.hasError && _data == null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load entries',
              message: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: () => setState(() { _future = _load(); }),
                child: const Text('Try again'),
              ),
            );
          }
          final data = _data ?? snap.data ?? const _ChallengeData(entries: [], winner: null, votes: {}, myVote: null);
          final myUid = Supabase.instance.client.auth.currentUser?.id;
          final myEntry = myUid == null ? null : data.entries.firstWhere(
            (e) => (e['car'] as Map<String, dynamic>?)?['owner_id'] == myUid,
            orElse: () => <String, dynamic>{},
          );
          final hasMyEntry = myEntry != null && myEntry.isNotEmpty;

          // Sort by votes descending
          final sorted = [...data.entries]..sort(
              (a, b) => (data.votes[b['id']] ?? 0).compareTo(data.votes[a['id']] ?? 0));
          final myRank = hasMyEntry
              ? sorted.indexWhere((e) => e['id'] == myEntry['id']) + 1
              : 0;
          final top5 = sorted.take(5).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(challenge: c, onEnter: c.isActive ? _enter : null)),
              if (data.winner != null)
                SliverToBoxAdapter(child: _WinnerCard(entry: data.winner!)),

              // Top-5 leaderboard + collapsible "your entry"
              if (sorted.isNotEmpty)
                SliverToBoxAdapter(
                  child: _LeaderboardSection(
                    top5: top5,
                    votes: data.votes,
                    myEntry: hasMyEntry ? myEntry : null,
                    myRank: myRank,
                    total: sorted.length,
                    myVote: data.myVote,
                    canVote: c.isActive,
                    onVote: (id) => _castVote(id),
                    onDelete: (hasMyEntry && c.isActive)
                        ? () => _deleteEntry(myEntry!['id'] as String)
                        : null,
                  ),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    data.entries.isEmpty ? 'No entries yet' : 'All entries (${data.entries.length})',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              if (data.entries.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'No entries yet',
                    message: 'Be the first to enter this week\'s Shot',
                  ),
                )
              else
                SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final row = sorted[i];
                      final entryId = row['id'] as String;
                      final voteCount = data.votes[entryId] ?? 0;
                      final isMyVote = data.myVote == entryId;
                      return _EntryTile(
                        row: row,
                        voteCount: voteCount,
                        isMyVote: isMyVote,
                        canVote: c.isActive,
                        onVote: () => _castVote(entryId),
                        rank: i + 1,
                      );
                    },
                    childCount: sorted.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      );
  }
}

class _ChallengeData {
  const _ChallengeData({
    required this.entries,
    required this.winner,
    required this.votes,
    required this.myVote,
  });
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic>? winner;
  final Map<String, int> votes;
  final String? myVote;
}

class _ResultsData {
  const _ResultsData({required this.challenge, required this.top3, required this.all});
  final Challenge? challenge;
  final List<Map<String, dynamic>> top3;
  final List<Map<String, dynamic>> all; // full sorted list with _vote_count
}

// ─── Leaderboard ─────────────────────────────────────────────────────────────

class _LeaderboardSection extends StatefulWidget {
  const _LeaderboardSection({
    required this.top5,
    required this.votes,
    required this.myEntry,
    required this.myRank,
    required this.total,
    required this.myVote,
    required this.canVote,
    required this.onVote,
    this.onDelete,
  });

  final List<Map<String, dynamic>> top5;
  final Map<String, int> votes;
  final Map<String, dynamic>? myEntry;
  final int myRank;
  final int total;
  final String? myVote;
  final bool canVote;
  final void Function(String entryId) onVote;
  final VoidCallback? onDelete;

  @override
  State<_LeaderboardSection> createState() => _LeaderboardSectionState();
}

class _LeaderboardSectionState extends State<_LeaderboardSection> {
  bool _myEntryExpanded = false;

  static const _medals = ['🥇', '🥈', '🥉', '', ''];

  static String _carName(Map<String, dynamic> entry) {
    final car = entry['car'] as Map<String, dynamic>?;
    final nick = car?['nickname'] as String?;
    if (nick != null && nick.isNotEmpty) return nick;
    final make = car?['make'] as String? ?? '';
    final model = car?['model'] as String? ?? '';
    final title = '$make $model'.trim();
    if (title.isNotEmpty) return title;
    final owner = car?['owner'] as Map<String, dynamic>?;
    return (owner?['username'] as String?) ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final hasMyEntry = widget.myEntry != null;
    // Check if my entry is already in the top 5
    final myId = widget.myEntry?['id'] as String?;
    final myInTop5 = widget.top5.any((e) => e['id'] == myId);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              'Leaderboard',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),

          // Top 5 rows
          for (var i = 0; i < widget.top5.length; i++) ...[
            Divider(height: 1, color: AppColors.hairline),
            _LeaderboardRow(
              rank: i + 1,
              medal: _medals[i],
              entry: widget.top5[i],
              voteCount: widget.votes[widget.top5[i]['id']] ?? 0,
              isMe: widget.top5[i]['id'] == myId,
              carName: _carName(widget.top5[i]),
            ),
          ],

          // "Your entry" row — only when not already in top 5
          if (hasMyEntry && !myInTop5) ...[
            Divider(height: 1, color: AppColors.hairline),
            // Collapsed header — always visible
            InkWell(
              onTap: () => setState(() => _myEntryExpanded = !_myEntryExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.ember.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '#${widget.myRank}',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ember,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your entry · ${_carName(widget.myEntry!)}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ember,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '↑ ${widget.votes[widget.myEntry!['id']] ?? 0}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _myEntryExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.steel,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            // Expanded detail
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _myEntryExpanded
                  ? _MyEntryBanner(
                      entry: widget.myEntry!,
                      rank: widget.myRank,
                      total: widget.total,
                      voteCount: widget.votes[widget.myEntry!['id']] ?? 0,
                      isMyVote: widget.myVote == widget.myEntry!['id'],
                      canVote: widget.canVote,
                      onVote: () => widget.onVote(widget.myEntry!['id'] as String),
                      onDelete: widget.onDelete,
                      inset: true,
                    )
                  : const SizedBox.shrink(),
            ),
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.medal,
    required this.entry,
    required this.voteCount,
    required this.isMe,
    required this.carName,
  });

  final int rank;
  final String medal;
  final Map<String, dynamic> entry;
  final int voteCount;
  final bool isMe;
  final String carName;

  @override
  Widget build(BuildContext context) {
    final media = (entry['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    final thumbUrl = media.isNotEmpty ? _thumb(media.first['url'] as String) : null;

    return Container(
      color: isMe ? AppColors.ember.withValues(alpha: 0.06) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          // Rank / medal
          SizedBox(
            width: 28,
            child: medal.isNotEmpty
                ? Text(medal, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center)
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: thumbUrl != null
                ? Image.network(thumbUrl, width: 36, height: 36, fit: BoxFit.cover)
                : Container(
                    width: 36,
                    height: 36,
                    color: AppColors.graphite,
                    child: Icon(Icons.directions_car_outlined, size: 18, color: AppColors.steel),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              carName,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                color: isMe ? AppColors.cream : AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Vote count
          Text(
            '↑ $voteCount',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.challenge, this.onEnter});
  final Challenge challenge;
  final VoidCallback? onEnter;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.isDark
              ? [const Color(0xFF2A1200), const Color(0xFF1A0800)]
              : [const Color(0xFFFFF0E8), const Color(0xFFFFE5D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.cream,
            ),
          ),
          Text(
            c.isActive ? c.timeLeftLabel : c.isEnded ? 'Shot ended' : 'Starts soon',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: c.isActive ? AppColors.ember : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (c.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              c.description,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.ember.withValues(alpha: 0.3)),
            ),
            child: Text(
              '#${c.tag}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.ember,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final car = entry['car'] as Map<String, dynamic>?;
    final media = (entry['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    final carObj = car != null ? Car.fromMap(car) : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'WINNER',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ember,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          if (media.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  _thumb(media.first['url'] as String, width: 800),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (carObj != null)
                  Text(
                    carObj.title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cream,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  entry['title'] as String? ?? '',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyEntryBanner extends StatelessWidget {
  const _MyEntryBanner({
    required this.entry,
    required this.rank,
    required this.total,
    required this.voteCount,
    required this.isMyVote,
    required this.canVote,
    required this.onVote,
    this.onDelete,
    this.inset = false,
  });

  final Map<String, dynamic> entry;
  final int rank;
  final int total;
  final int voteCount;
  final bool isMyVote;
  final bool canVote;
  final VoidCallback onVote;
  final VoidCallback? onDelete;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final car = entry['car'] as Map<String, dynamic>?;
    final carName = car?['nickname'] as String? ??
        '${car?['make'] ?? ''} ${car?['model'] ?? ''}'.trim();
    final media = (entry['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    final thumbUrl = media.isNotEmpty ? _thumb(media.first['url'] as String) : null;

    final inner = Container(
      margin: inset ? const EdgeInsets.fromLTRB(12, 0, 12, 8) : const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: inset ? null : BoxDecoration(
        color: AppColors.isDark ? const Color(0xFF1A1C20) : AppColors.graphite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ember,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Thumb
          if (thumbUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(thumbUrl, width: 48, height: 48, fit: BoxFit.cover),
            ),
          if (thumbUrl != null) const SizedBox(width: 10),
          // Labels
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your entry',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  carName,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cream,
                  ),
                ),
                Text(
                  '$rank of $total',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          // Delete
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.steel,
              tooltip: 'Remove entry',
              visualDensity: VisualDensity.compact,
            ),
          ],
          // Vote count
          Column(
            children: [
              GestureDetector(
                onTap: canVote ? onVote : null,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 28,
                    color: isMyVote ? AppColors.ember : AppColors.steel,
                  ),
                ),
              ),
              Text(
                '$voteCount',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isMyVote ? AppColors.ember : AppColors.cream,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return inner;
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.row,
    required this.voteCount,
    required this.isMyVote,
    required this.canVote,
    required this.onVote,
    this.rank = 0,
  });
  final Map<String, dynamic> row;
  final int voteCount;
  final bool isMyVote;
  final bool canVote;
  final VoidCallback onVote;
  final int rank;

  static String? _medal(int rank) => switch (rank) {
    1 => '🥇',
    2 => '🥈',
    3 => '🥉',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final media = (row['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    final car = row['car'] as Map<String, dynamic>?;
    final carObj = car != null ? Car.fromMap(car) : null;

    return GestureDetector(
      onTap: () {
        if (carObj == null) return;
        final rawMedia = (row['post_media'] as List? ?? []).cast<Map<String, dynamic>>();
        if (rawMedia.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostViewerScreen(
              media: PostMedia.fromMap(rawMedia.first),
              car: carObj,
              voteCount: voteCount,
              isMyVote: isMyVote,
              canVote: canVote,
              onVote: onVote,
            ),
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          media.isNotEmpty
              ? Image.network(_thumb(media.first['url'] as String), fit: BoxFit.cover)
              : Container(
                  color: AppColors.graphiteRaised,
                  child: Icon(Icons.directions_car_outlined, color: AppColors.steel),
                ),
          // Bottom gradient + car name + upvote
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 32, 8, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xEE000000)],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      carObj?.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Vote count display only — tap the entry to vote
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isMyVote
                          ? AppColors.ember.withValues(alpha: 0.9)
                          : Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isMyVote ? AppColors.ember : Colors.white12,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_upward, size: 15, color: isMyVote ? Colors.white : Colors.white54),
                        const SizedBox(width: 4),
                        Text(
                          '$voteCount',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isMyVote ? Colors.white : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Medal badge top-left for top 3
          if (_medal(rank) != null)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_medal(rank)!, style: const TextStyle(fontSize: 18)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Podium / Results ────────────────────────────────────────────────────────

class _PodiumView extends StatefulWidget {
  const _PodiumView({
    required this.challenge,
    required this.top3,
    required this.all,
    this.myUid,
  });
  final Challenge challenge;
  final List<Map<String, dynamic>> top3;
  final List<Map<String, dynamic>> all;
  final String? myUid;

  @override
  State<_PodiumView> createState() => _PodiumViewState();
}

class _PodiumViewState extends State<_PodiumView> {
  Challenge get challenge => widget.challenge;
  List<Map<String, dynamic>> get top3 => widget.top3;
  List<Map<String, dynamic>> get all => widget.all;
  String? get myUid => widget.myUid;

  final _podiumKey = GlobalKey();

  static const _medals = ['🥇', '🥈', '🥉'];
  static const _medalColors = [
    Color(0xFFFFD700),
    Color(0xFFC0C0C0),
    Color(0xFFCD7F32),
  ];

  void _showFullResults(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.graphite,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.steel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Text(
                    'Full results — ${challenge.title}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.cream,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${all.length} entries',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.hairline),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: all.length,
                itemBuilder: (_, i) {
                  final e = all[i];
                  final car = e['car'] as Map<String, dynamic>?;
                  final nick = car?['nickname'] as String?;
                  final make = car?['make'] as String? ?? '';
                  final model = car?['model'] as String? ?? '';
                  final carTitle = nick?.isNotEmpty == true
                      ? nick!
                      : '$make $model'.trim();
                  final owner = car?['owner'] as Map<String, dynamic>?;
                  final name = carTitle.isNotEmpty
                      ? carTitle
                      : (owner?['username'] as String?) ?? '—';
                  final votes = (e['_vote_count'] as int?) ?? 0;
                  final isMe = myUid != null &&
                      car?['owner_id'] == myUid;
                  final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : null;
                  return Container(
                    color: isMe ? AppColors.ember.withValues(alpha: 0.07) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: medal != null
                              ? Text(medal, style: const TextStyle(fontSize: 16))
                              : Text(
                                  '${i + 1}',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                              color: isMe ? AppColors.cream : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '↑ $votes',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
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


  void _openEntry(BuildContext context, Map<String, dynamic> entry) {
    final car = entry['car'] as Map<String, dynamic>?;
    final carObj = car != null ? Car.fromMap(car) : null;
    final media = (entry['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    if (carObj == null || media.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostViewerScreen(
          media: PostMedia.fromMap(media.first),
          car: carObj,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              '${challenge.emoji}  ${challenge.title}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.cream,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Final standings',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),

          // Podium scene — wrapped for screenshot capture on share
          RepaintBoundary(
            key: _podiumKey,
            child: _PodiumScene(top3: top3, onTap: _openEntry),
          ),

          const SizedBox(height: 32),

          // Podium result rows — share button only visible to the user in that slot
          for (var i = 0; i < top3.length; i++)
            _ResultRow(
              entry: top3[i],
              position: i + 1,
              medal: _medals[i],
              accentColor: _medalColors[i],
              myUid: myUid,
            ),

          // Your place (only if not already in the podium)
          if (myUid != null) Builder(builder: (context) {
            final myIdx = all.indexWhere(
              (e) => (e['car'] as Map?)?['owner_id'] == myUid,
            );
            if (myIdx == -1 || myIdx < 3) return const SizedBox.shrink();
            final myE = all[myIdx];
            final car = myE['car'] as Map<String, dynamic>?;
            final name = car?['nickname'] as String? ??
                '${car?['make'] ?? ''} ${car?['model'] ?? ''}'.trim();
            final votes = (myE['_vote_count'] as int?) ?? 0;
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.ember.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.ember.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Text(
                    'Your place',
                    style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.ember, fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.ember.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#${myIdx + 1}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ember,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.cream,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '↑ $votes',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.ios_share_outlined, size: 20),
                    color: AppColors.ember,
                    tooltip: 'Share your result',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      const ordinals = ['1st', '2nd', '3rd'];
                      final rank = myIdx + 1;
                      final pos = rank >= 1 && rank <= ordinals.length
                          ? ordinals[myIdx]
                          : '#$rank';
                      final text = 'I finished $pos in The Shot on TorqueDen with $name! 🏁 #TorqueDen #TheShot';
                      try {
                        // Capture the podium as an image.
                        final boundary = _podiumKey.currentContext
                            ?.findRenderObject() as RenderRepaintBoundary?;
                        if (boundary != null) {
                          final image = await boundary.toImage(pixelRatio: 3.0);
                          final byteData = await image.toByteData(
                              format: dart_ui.ImageByteFormat.png);
                          final bytes = byteData!.buffer.asUint8List();
                          final dir = await getTemporaryDirectory();
                          final file = File('${dir.path}/theshot_result.png');
                          await file.writeAsBytes(bytes);
                          await SharePlus.instance.share(ShareParams(
                            text: text,
                            files: [XFile(file.path, mimeType: 'image/png')],
                          ));
                        } else {
                          // Fallback: text only if podium not rendered yet.
                          await SharePlus.instance.share(ShareParams(text: text));
                        }
                      } catch (_) {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          }),

          // See full results button
          if (all.length > 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Builder(builder: (context) => OutlinedButton(
                onPressed: () => _showFullResults(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.cream,
                  side: BorderSide(color: AppColors.steel),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(
                  'See full results (${all.length})',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              )),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── Podium scene image ───────────────────────────────────────────────────────
//
// The background PNG is 1200×1500 (4:5). We scale it to screen width.
// Each slot (cx, cy, w) is a fraction of scene width; h is derived from
// the scene's natural aspect ratio. The car photo + medal + name sit on
// each step's top surface.

class _PodiumScene extends StatelessWidget {
  const _PodiumScene({required this.top3, required this.onTap});

  final List<Map<String, dynamic>> top3;
  final void Function(BuildContext, Map<String, dynamic>) onTap;

  // stepCy = top surface of each podium step as a fraction of scene height.
  // The pill label sits ON this surface; the card floats above it.
  // cx = horizontal centre of each step as a fraction of scene width.
  static const _slots = [
    _Slot(cx: 0.50,  stepCy: 0.37, w: 0.30, medal: '🥇', color: Color(0xFFFFD700)),
    _Slot(cx: 0.195, stepCy: 0.50, w: 0.26, medal: '🥈', color: Color(0xFFC0C0C0)),
    _Slot(cx: 0.795, stepCy: 0.56, w: 0.24, medal: '🥉', color: Color(0xFFCD7F32)),
  ];

  static String _displayName(Map<String, dynamic> entry) {
    final car = entry['car'] as Map<String, dynamic>?;
    final nick = car?['nickname'] as String?;
    if (nick != null && nick.isNotEmpty) return nick;
    final make = car?['make'] as String? ?? '';
    final model = car?['model'] as String? ?? '';
    final t = '$make $model'.trim();
    if (t.isNotEmpty) return t;
    final owner = car?['owner'] as Map<String, dynamic>?;
    return (owner?['username'] as String?) ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sceneW = constraints.maxWidth;
        final sceneH = sceneW * (1500 / 1200); // 4:5 → 5:4 height ratio

        return SizedBox(
          height: sceneH,
          child: Stack(
            children: [
              // Background scene
              Positioned.fill(
                child: Image.asset(
                  'assets/images/podium_scene.png',
                  fit: BoxFit.fill,
                ),
              ),

              // Per-slot: car photo + medal + name
              for (var i = 0; i < _slots.length; i++) ...[
                if (i < top3.length)
                  _SlotOverlay(
                    slot: _slots[i],
                    entry: top3[i],
                    sceneW: sceneW,
                    sceneH: sceneH,
                    name: _displayName(top3[i]),
                    onTap: () => onTap(context, top3[i]),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Slot {
  const _Slot({
    required this.cx,
    required this.stepCy,
    required this.w,
    required this.medal,
    required this.color,
  });
  final double cx;     // horizontal centre of step, fraction of scene width
  final double stepCy; // top surface of step, fraction of scene height
  final double w;      // card width as fraction of scene width
  final String medal;
  final Color color;
}

class _SlotOverlay extends StatelessWidget {
  const _SlotOverlay({
    required this.slot,
    required this.entry,
    required this.sceneW,
    required this.sceneH,
    required this.name,
    required this.onTap,
  });

  final _Slot slot;
  final Map<String, dynamic> entry;
  final double sceneW;
  final double sceneH;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photoW = sceneW * slot.w;
    final photoH = photoW;
    final left = sceneW * slot.cx - photoW / 2;

    // Pill sits ON the step top surface; card floats above with a gap.
    final pillTop = sceneH * slot.stepCy;
    final cardGap = photoW * 0.10;   // gap between card bottom and pill top
    final cardTop = pillTop - cardGap - photoH;

    final media = (entry['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    final photoUrl = media.isNotEmpty ? _thumb(media.first['url'] as String) : null;

    final pillFontSize = (photoW * 0.105).clamp(10.0, 16.0);

    return Stack(
      children: [
        // ── Liquid-glass card ──────────────────────────────────────────
        Positioned(
          left: left,
          top: cardTop,
          width: photoW,
          height: photoH,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: slot.color.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Blurred backdrop (frosted glass)
                    BackdropFilter(
                      filter: dart_ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: const SizedBox.expand(),
                    ),
                    // Car photo or placeholder
                    if (photoUrl != null)
                      Image.network(photoUrl, fit: BoxFit.cover)
                    else
                      ColoredBox(
                        color: Colors.white.withValues(alpha: 0.08),
                        child: Icon(
                          Icons.directions_car_outlined,
                          color: Colors.white.withValues(alpha: 0.4),
                          size: photoW * 0.38,
                        ),
                      ),
                    // Glass tint + border overlay
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1.2,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.03),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Medal badge — top-centre of card ──────────────────────────
        Positioned(
          left: left + photoW / 2 - photoW * 0.14,
          top: cardTop - photoW * 0.16,
          width: photoW * 0.28,
          child: Text(
            slot.medal,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: photoW * 0.24),
          ),
        ),

        // ── Pill name label — ON the step top surface ─────────────────
        Positioned(
          left: left - photoW * 0.08,
          width: photoW * 1.16,
          top: pillTop,
          child: GestureDetector(
            onTap: onTap,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: photoW * 0.10,
                  vertical: photoW * 0.045,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: pillFontSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cream,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.entry,
    required this.position,
    required this.medal,
    required this.accentColor,
    this.myUid,
  });
  final Map<String, dynamic> entry;
  final int position;
  final String medal;
  final Color accentColor;
  final String? myUid;

  bool get _isMe {
    final car = entry['car'] as Map<String, dynamic>?;
    return myUid != null && car?['owner_id'] == myUid;
  }

  Future<void> _share(BuildContext context) async {
    final car = entry['car'] as Map<String, dynamic>?;
    final carObj = car != null ? Car.fromMap(car) : null;
    final name = carObj?.title ?? 'my car';
    const ordinals = ['1st', '2nd', '3rd'];
    final pos = position >= 1 && position <= ordinals.length
        ? ordinals[position - 1]
        : '#$position';
    final msg = 'I came $pos in The Shot on TorqueDen with $name! 🏁 #TorqueDen #TheShot';
    try {
      await SharePlus.instance.share(ShareParams(text: msg));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: msg));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final car = entry['car'] as Map<String, dynamic>?;
    final carObj = car != null ? Car.fromMap(car) : null;
    final media = (entry['post_media'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((m) => m['kind'] == 'image')
            .toList() ??
        [];
    final photoUrl = media.isNotEmpty ? _thumb(media.first['url'] as String) : null;
    final votes = (entry['_vote_count'] as int?) ?? 0;

    return GestureDetector(
      onTap: () {
        if (carObj == null || media.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostViewerScreen(
              media: PostMedia.fromMap(media.first),
              car: carObj,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          children: [
            Text(medal, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            if (photoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(photoUrl, width: 52, height: 52, fit: BoxFit.cover),
              ),
            if (photoUrl != null) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    carObj?.title ?? '',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.cream,
                    ),
                  ),
                  Text(
                    '$votes vote${votes == 1 ? '' : 's'}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (_isMe)
              IconButton(
                icon: const Icon(Icons.ios_share_outlined),
                color: AppColors.steel,
                tooltip: 'Share result',
                onPressed: () => _share(context),
              ),
          ],
        ),
      ),
    );
  }
}
