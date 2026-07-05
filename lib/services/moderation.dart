import 'package:supabase_flutter/supabase_flutter.dart';

/// Central moderation helpers: the current user's block list (cached so screens
/// can filter cheaply) plus report/block/unblock actions.
class Moderation {
  const Moderation._();

  static final SupabaseClient _client = Supabase.instance.client;

  /// User ids the current user has blocked. Refreshed by [refreshBlocks];
  /// screens read this to filter out blocked authors.
  static final Set<String> blockedIds = <String>{};

  static bool isBlocked(String? userId) =>
      userId != null && blockedIds.contains(userId);

  /// Loads (or reloads) the block list for the signed-in user.
  static Future<void> refreshBlocks() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      blockedIds.clear();
      return;
    }
    try {
      final rows =
          await _client.from('blocks').select('blocked_id').eq('blocker_id', uid);
      blockedIds
        ..clear()
        ..addAll(rows.map((r) => r['blocked_id'] as String));
    } catch (_) {/* keep last-known set */}
  }

  static Future<void> block(String userId) async {
    await _client.from('blocks').insert({'blocked_id': userId});
    blockedIds.add(userId);
  }

  static Future<void> unblock(String userId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('blocks')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', userId);
    blockedIds.remove(userId);
  }

  /// Files a report against a piece of content or a user.
  static Future<void> report({
    required String targetType, // 'post' | 'comment' | 'thread' | 'reply' | 'club' | 'user'
    required String targetId,
    required String reason,
    String? note,
  }) async {
    await _client.from('reports').insert({
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }
}
