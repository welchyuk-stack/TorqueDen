import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/challenge.dart';

class ChallengeService {
  ChallengeService._();
  static final instance = ChallengeService._();

  final _client = Supabase.instance.client;

  /// The currently active challenge, or null if none is running.
  Future<Challenge?> fetchActive() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client
        .from('challenges')
        .select('*')
        .lte('starts_at', now)
        .gte('ends_at', now)
        .order('starts_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final c = Challenge.fromMap(rows.first as Map<String, dynamic>);
    final count = await _countEntries(c.tag, c.startsAt, c.endsAt);
    return Challenge(
      id: c.id, title: c.title, emoji: c.emoji, tag: c.tag,
      description: c.description, startsAt: c.startsAt, endsAt: c.endsAt,
      winnerEntryId: c.winnerEntryId, winnerAnnounced: c.winnerAnnounced,
      entryCount: count,
    );
  }

  /// All challenges, newest first.
  Future<List<Challenge>> fetchAll() async {
    final rows = await _client
        .from('challenges')
        .select('*')
        .order('starts_at', ascending: false);
    return rows
        .map((r) => Challenge.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Build entries that count as entries for [challenge] (tag + window).
  Future<List<Map<String, dynamic>>> fetchEntries(Challenge challenge) async {
    final rows = await _client
        .from('build_entries')
        .select(
          'id, title, body, created_at, tags, '
          'car:cars(id, make, model, nickname, photo_url, owner_id, owner:profiles(username)), '
          'post_media(id, url, kind, position)',
        )
        .filter('tags', 'cs', '{${challenge.tag}}')
        .gte('created_at', challenge.startsAt.toUtc().toIso8601String())
        .lte('created_at', challenge.endsAt.toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// The winning build entry row (with media), or null.
  Future<Map<String, dynamic>?> fetchWinnerEntry(String entryId) async {
    final rows = await _client
        .from('build_entries')
        .select(
          'id, title, body, created_at, tags, '
          'car:cars(id, make, model, nickname, photo_url, owner_id, owner:profiles(username)), '
          'post_media(id, url, kind, position)',
        )
        .eq('id', entryId)
        .limit(1);
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  Future<List<CarBadge>> fetchBadgesForCar(String carId) async {
    final rows = await _client
        .from('car_badges')
        .select('challenge_id, awarded_at, challenge:challenges(id, title, emoji)')
        .eq('car_id', carId)
        .order('awarded_at', ascending: false);
    return rows
        .map((r) => CarBadge.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Vote counts keyed by entry_id for a given challenge.
  Future<Map<String, int>> fetchVoteCounts(String challengeId) async {
    final rows = await _client
        .from('challenge_votes')
        .select('entry_id')
        .eq('challenge_id', challengeId);
    final counts = <String, int>{};
    for (final r in rows as List) {
      final id = r['entry_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// The entry_id the current user has voted for in this challenge, or null.
  Future<String?> fetchMyVote(String challengeId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final rows = await _client
        .from('challenge_votes')
        .select('entry_id')
        .eq('challenge_id', challengeId)
        .eq('user_id', uid)
        .limit(1);
    return rows.isEmpty ? null : rows.first['entry_id'] as String;
  }

  /// Cast or move a vote. Passing the same entry twice removes the vote.
  Future<void> castVote({
    required String challengeId,
    required String entryId,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    final existing = await fetchMyVote(challengeId);
    if (existing == entryId) {
      // Tapping same entry removes vote
      await _client
          .from('challenge_votes')
          .delete()
          .eq('challenge_id', challengeId)
          .eq('user_id', uid);
    } else {
      // Upsert moves vote to new entry
      await _client.from('challenge_votes').upsert({
        'user_id': uid,
        'challenge_id': challengeId,
        'entry_id': entryId,
      });
    }
  }

  /// Delete the user's own build entry from this challenge.
  Future<void> deleteEntry(String entryId) async {
    await _client.from('build_entries').delete().eq('id', entryId);
  }

  /// The most recently ended challenge (i.e. the previous week's Shot).
  Future<Challenge?> fetchPrevious() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _client
        .from('challenges')
        .select('*')
        .lt('ends_at', now)
        .order('ends_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Challenge.fromMap(rows.first as Map<String, dynamic>);
  }

  /// Top [limit] entries for a challenge, sorted by vote count descending.
  Future<List<Map<String, dynamic>>> fetchTopEntries(
    Challenge challenge, {
    int limit = 3,
  }) async {
    final entries = await fetchEntries(challenge);
    final votes = await fetchVoteCounts(challenge.id);
    entries.sort((a, b) =>
        (votes[b['id']] ?? 0).compareTo(votes[a['id']] ?? 0));
    return entries.take(limit).map((e) {
      return {...e, '_vote_count': votes[e['id']] ?? 0};
    }).toList();
  }

  Future<int> _countEntries(String tag, DateTime start, DateTime end) async {
    final rows = await _client
        .from('build_entries')
        .select('id')
        .contains('tags', [tag])
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String());
    return (rows as List).length;
  }
}
