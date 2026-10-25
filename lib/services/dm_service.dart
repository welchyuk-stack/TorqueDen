import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/dm.dart';
import 'package:torqueden/screens/dm_thread_screen.dart';

/// Lightweight DM helpers: unread badge count + open-or-create thread.
class DmService {
  DmService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Shared unread count so the Messages nav badge stays in sync.
  /// Call [refreshUnread] on app resume and after marking messages read.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  static Future<void> refreshUnread() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) { unread.value = 0; return; }
    try {
      // Threads the current user is in.
      final threadRows = await _client
          .from('dm_threads')
          .select('id')
          .or('participant_a.eq.$uid,participant_b.eq.$uid');
      final threadIds = (threadRows as List).map((r) => r['id'] as String).toList();
      if (threadIds.isEmpty) { unread.value = 0; return; }

      final msgRows = await _client
          .from('dm_messages')
          .select('id')
          .inFilter('thread_id', threadIds)
          .neq('sender_id', uid)
          .isFilter('read_at', null);
      unread.value = (msgRows as List).length;
    } catch (_) {}
  }

  /// Deletes a thread (and all its messages via cascade). Both participants
  /// can delete — deleting only removes it for yourself isn't supported yet
  /// (no per-user soft-delete column), so this removes it for both sides.
  static Future<void> deleteThread(String threadId) async {
    await _client.from('dm_threads').delete().eq('id', threadId);
    await refreshUnread();
  }

  /// Opens an existing DM thread with [otherUserId], or creates one and opens
  /// it. Navigates to [DmThreadScreen] via [context].
  static Future<void> openOrCreate({
    required BuildContext context,
    required String otherUserId,
    required String otherUsername,
    String? otherDisplayName,
    String? otherAvatarUrl,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    if (uid == otherUserId) return; // can't DM yourself

    // Participants stored sorted (a < b).
    final a = uid.compareTo(otherUserId) < 0 ? uid : otherUserId;
    final b = uid.compareTo(otherUserId) < 0 ? otherUserId : uid;

    try {
      // Try to find existing thread.
      final existing = await _client
          .from('dm_threads')
          .select('id, participant_a, participant_b, last_message_at')
          .eq('participant_a', a)
          .eq('participant_b', b)
          .maybeSingle();

      String threadId;
      if (existing != null) {
        threadId = existing['id'] as String;
      } else {
        final created = await _client
            .from('dm_threads')
            .insert({'participant_a': a, 'participant_b': b})
            .select('id, participant_a, participant_b, last_message_at')
            .single();
        threadId = created['id'] as String;
      }

      final thread = DmThread(
        id: threadId,
        otherUserId: otherUserId,
        otherUsername: otherUsername,
        otherDisplayName: otherDisplayName,
        otherAvatarUrl: otherAvatarUrl,
        lastMessageAt: DateTime.now(),
      );

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DmThreadScreen(thread: thread)),
        );
        refreshUnread();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open conversation: $e')),
        );
      }
    }
  }
}
