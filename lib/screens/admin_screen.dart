import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/theme.dart';

/// Platform-level admin screen: search users, ban / unban globally.
/// Only reachable for the admin UID — gate it in the calling code.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _client = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  List<_UserRow> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Strips the characters that carry meaning in PostgREST's filter grammar.
  ///
  /// `.or()` takes a raw filter *string*, so interpolating a search box into it
  /// lets a comma or bracket close the current condition and append new ones —
  /// the query builder can't parameterise this the way it does `.eq()`. A
  /// search for `a,is_platform_admin.eq.true` would otherwise become an extra
  /// OR clause rather than a literal. Also drops `%` and `_` so a user's
  /// wildcards can't widen the ilike beyond what we intend.
  static String _sanitiseFilterTerm(String input) =>
      input.replaceAll(RegExp(r'[,()\\%_.*:"]'), '').trim();

  Future<void> _search(String q) async {
    final query = _sanitiseFilterTerm(q);
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _client
          .from('profiles')
          .select('id, username, display_name, avatar_url, strike_count, is_banned')
          .or('username.ilike.%$query%,display_name.ilike.%$query%')
          .order('username')
          .limit(30);
      if (mounted) {
        setState(() {
          _results = rows.map((r) => _UserRow.fromMap(r)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleBan(_UserRow user) async {
    final newBanned = !user.isBanned;
    final action = newBanned ? 'Ban' : 'Unban';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('$action @${user.username}?',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text(
          newBanned
              ? 'They will be blocked from posting, commenting, and creating meets.'
              : 'They will regain full access to the platform.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action,
                style: GoogleFonts.inter(
                  color: newBanned ? AppColors.danger : AppColors.ember,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      // Goes through a SECURITY DEFINER function that re-checks admin rights
      // server-side. A direct table update can't work here: is_banned is
      // revoked from the authenticated role, and the profiles UPDATE policy
      // only ever matched the caller's own row — so this silently no-opped.
      await _client.rpc('set_user_banned', params: {
        'target_user_id': user.id,
        'banned': newBanned,
      });
      setState(() {
        final idx = _results.indexWhere((r) => r.id == user.id);
        if (idx != -1) _results[idx] = user.copyWith(isBanned: newBanned);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('@${user.username} ${newBanned ? 'banned' : 'unbanned'}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('Platform Admin', style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: GoogleFonts.inter(color: AppColors.cream),
              decoration: InputDecoration(
                hintText: 'Search username or display name…',
                hintStyle: GoogleFonts.inter(color: AppColors.steel),
                prefixIcon: Icon(Icons.search, color: AppColors.steel),
                filled: true,
                fillColor: AppColors.graphiteRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: AppColors.ember),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: GoogleFonts.inter(color: AppColors.danger)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final u = _results[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.graphiteRaised,
                    backgroundImage: u.avatarUrl != null ? NetworkImage(u.avatarUrl!) : null,
                    child: u.avatarUrl == null
                        ? Text(
                            (u.username.isNotEmpty ? u.username[0] : '?').toUpperCase(),
                            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  title: Text(
                    u.displayName.isNotEmpty ? u.displayName : '@${u.username}',
                    style: GoogleFonts.inter(color: AppColors.cream, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '@${u.username}  ·  ${u.strikeCount} strike${u.strikeCount == 1 ? '' : 's'}${u.isBanned ? '  · BANNED' : ''}',
                    style: GoogleFonts.inter(
                      color: u.isBanned ? AppColors.danger : AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () => _toggleBan(u),
                    child: Text(
                      u.isBanned ? 'Unban' : 'Ban',
                      style: GoogleFonts.inter(
                        color: u.isBanned ? AppColors.ember : AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final int strikeCount;
  final bool isBanned;

  const _UserRow({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.strikeCount,
    required this.isBanned,
  });

  factory _UserRow.fromMap(Map<String, dynamic> m) => _UserRow(
        id: m['id'] as String,
        username: (m['username'] as String?) ?? '',
        displayName: (m['display_name'] as String?) ?? '',
        avatarUrl: m['avatar_url'] as String?,
        strikeCount: (m['strike_count'] as int?) ?? 0,
        isBanned: (m['is_banned'] as bool?) ?? false,
      );

  _UserRow copyWith({bool? isBanned}) => _UserRow(
        id: id,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        strikeCount: strikeCount,
        isBanned: isBanned ?? this.isBanned,
      );
}
