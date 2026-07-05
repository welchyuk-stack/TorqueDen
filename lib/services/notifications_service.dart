import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/app_notification.dart';

/// Reads the current user's in-app notifications. Rows are created server-side
/// by triggers (see migration 0021); clients only read / mark-read / delete
/// their own via RLS.
class NotificationsService {
  NotificationsService._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Most recent notifications (newest first), with the actor profile joined.
  static Future<List<AppNotification>> list({int limit = 50}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('notifications')
        .select('*, actor:actor_id(display_name, username, avatar_url)')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromMap).toList();
  }

  /// Count of unread notifications (best-effort; 0 on error).
  static Future<int> unreadCount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return 0;
    try {
      final rows =
          await _client.from('notifications').select('id').eq('read', false);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markRead(String id) async {
    await _client.from('notifications').update({'read': true}).eq('id', id);
  }

  static Future<void> markAllRead() async {
    await _client.from('notifications').update({'read': true}).eq('read', false);
  }
}
