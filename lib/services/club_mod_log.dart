import 'package:supabase_flutter/supabase_flutter.dart';

/// Appends moderation actions to a club's audit log. Fire-and-forget — a log
/// failure never blocks the action itself.
class ClubModLog {
  const ClubModLog._();

  static Future<void> record(
    String clubId,
    String action, {
    String? targetUserId,
    String? detail,
  }) async {
    try {
      await Supabase.instance.client.from('club_mod_log').insert({
        'club_id': clubId,
        'action': action,
        'target_user_id': ?targetUserId,
        'detail': ?detail,
      });
    } catch (_) {/* logging is best-effort */}
  }
}
