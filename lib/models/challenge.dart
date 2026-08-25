/// A weekly challenge row from the `challenges` table.
class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.emoji,
    required this.tag,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    this.winnerEntryId,
    this.winnerAnnounced = false,
    this.entryCount = 0,
  });

  final String id;
  final String title;
  final String emoji;
  final String tag;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? winnerEntryId;
  final bool winnerAnnounced;
  final int entryCount;

  bool get isActive {
    final now = DateTime.now().toUtc();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  bool get isUpcoming => DateTime.now().toUtc().isBefore(startsAt);
  bool get isEnded => DateTime.now().toUtc().isAfter(endsAt);

  /// Remaining duration (clamped to zero when ended).
  Duration get timeLeft {
    final diff = endsAt.difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get timeLeftLabel {
    final d = timeLeft;
    if (d == Duration.zero) return 'Ended';
    if (d.inDays >= 2) return '${d.inDays} days left';
    if (d.inDays == 1) return '1 day left';
    if (d.inHours >= 1) return '${d.inHours}h left';
    return '${d.inMinutes}m left';
  }

  static Challenge fromMap(Map<String, dynamic> m) => Challenge(
        id: m['id'] as String,
        title: m['title'] as String,
        emoji: (m['emoji'] as String?) ?? '🏁',
        tag: m['tag'] as String,
        description: (m['description'] as String?) ?? '',
        startsAt: DateTime.parse(m['starts_at'] as String),
        endsAt: DateTime.parse(m['ends_at'] as String),
        winnerEntryId: m['winner_entry_id'] as String?,
        winnerAnnounced: (m['winner_announced'] as bool?) ?? false,
        entryCount: (m['entry_count'] as int?) ?? 0,
      );
}

/// A trophy badge on a car — one per challenge won.
class CarBadge {
  const CarBadge({
    required this.challengeId,
    required this.challengeTitle,
    required this.challengeEmoji,
    required this.awardedAt,
  });

  final String challengeId;
  final String challengeTitle;
  final String challengeEmoji;
  final DateTime awardedAt;

  static CarBadge fromMap(Map<String, dynamic> m) {
    final c = m['challenge'] as Map<String, dynamic>? ?? m;
    return CarBadge(
      challengeId: (m['challenge_id'] ?? c['id']) as String,
      challengeTitle: c['title'] as String,
      challengeEmoji: (c['emoji'] as String?) ?? '🏆',
      awardedAt: DateTime.parse(m['awarded_at'] as String),
    );
  }
}
