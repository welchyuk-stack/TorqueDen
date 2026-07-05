import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/theme.dart';

/// Notification preferences — per-type opt-in toggles stored in
/// `notification_prefs`. Toggling persists immediately (optimistic, reverts on
/// error). Note: notification *delivery* isn't built yet; these are the prefs
/// that layer will read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _Pref {
  const _Pref(this.key, this.title, this.subtitle, this.icon);
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _client = Supabase.instance.client;

  static const _social = <_Pref>[
    _Pref('new_follower', 'New followers', 'When someone follows one of your builds', Icons.person_add_alt),
    _Pref('post_comments', 'Comments on your posts', 'When someone comments on your posts', Icons.mode_comment_outlined),
    _Pref('post_likes', 'Likes on your posts', 'When someone likes your posts', Icons.favorite_border),
  ];
  static const _clubs = <_Pref>[
    _Pref('club_new_threads', 'New posts in your clubs', 'When a new thread is posted in a club you\'re in', Icons.forum_outlined),
    _Pref('thread_replies', 'Replies to your threads', 'When someone replies to a thread you started', Icons.reply_outlined),
    _Pref('comment_replies', 'Replies to your comments', 'When someone replies to one of your comments', Icons.chat_bubble_outline),
  ];

  // Defaults to on until the row is loaded.
  final Map<String, bool> _values = {
    for (final p in [..._social, ..._clubs]) p.key: true,
  };
  late Future<void> _loaded;
  final _busy = <String>{};

  String get _uid => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  Future<void> _load() async {
    final row = await _client
        .from('notification_prefs')
        .select()
        .eq('user_id', _uid)
        .maybeSingle();
    if (row != null) {
      for (final key in _values.keys.toList()) {
        final v = row[key];
        if (v is bool) _values[key] = v;
      }
    }
  }

  Future<void> _toggle(String key, bool value) async {
    final prev = _values[key] ?? true;
    setState(() { _values[key] = value; _busy.add(key); });
    try {
      await _client.from('notification_prefs').upsert(
        {'user_id': _uid, key: value, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        onConflict: 'user_id',
      );
      if (mounted) setState(() { _busy.remove(key); });
    } catch (e) {
      if (!mounted) return;
      setState(() { _values[key] = prev; _busy.remove(key); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _loaded,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.ember));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                  child: Text(
                    'Choose what you want to be notified about.',
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
                  ),
                ),
                _header('SOCIAL'),
                for (final p in _social) _tile(p),
                const SizedBox(height: 16),
                _header('CLUBS'),
                for (final p in _clubs) _tile(p),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(title,
            style: GoogleFonts.inter(
                color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
      );

  Widget _tile(_Pref p) {
    final value = _values[p.key] ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: _busy.contains(p.key) ? null : (v) => _toggle(p.key, v),
        activeThumbColor: AppColors.ember,
        secondary: Icon(p.icon, color: AppColors.steel),
        title: Text(p.title, style: GoogleFonts.inter(color: AppColors.cream, fontWeight: FontWeight.w600)),
        subtitle: Text(p.subtitle, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      ),
    );
  }
}
