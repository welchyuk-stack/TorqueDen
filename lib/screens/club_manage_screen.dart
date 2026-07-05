import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/screens/add_car_screen.dart' show kCarPhotosBucket;
import 'package:torqueden/services/club_mod_log.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/time_ago.dart';

/// Result of managing a club: the updated club, or a delete signal.
class ClubManageResult {
  const ClubManageResult({this.club, this.deleted = false});
  final Club? club;
  final bool deleted;
}

/// Owner-only club admin: edit name/description, set a club picture, lock
/// posting, manage the member list, and delete the club.
class ClubManageScreen extends StatefulWidget {
  const ClubManageScreen({super.key, required this.club});

  final Club club;

  @override
  State<ClubManageScreen> createState() => _ClubManageScreenState();
}

class _ClubManageScreenState extends State<ClubManageScreen> {
  final _client = Supabase.instance.client;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rules = TextEditingController();
  final _words = TextEditingController();

  late Club _club;
  late Future<List<_Member>> _membersFuture;
  late Future<List<_Member>> _bannedFuture;
  late Future<List<_Member>> _mutedFuture;
  late Future<List<_LogEntry>> _logFuture;
  bool _savingDetails = false;
  bool _uploading = false;

  static const _slowOptions = <int, String>{
    0: 'Off', 30: '30 seconds', 60: '1 minute', 300: '5 minutes', 900: '15 minutes',
  };

  @override
  void initState() {
    super.initState();
    _club = widget.club;
    _name.text = _club.name;
    _description.text = _club.description ?? '';
    _rules.text = _club.rules ?? '';
    _words.text = _club.blockedWords.join(', ');
    _membersFuture = _loadMembers();
    _bannedFuture = _loadBanned();
    _mutedFuture = _loadMuted();
    _logFuture = _loadLog();
  }

  Future<List<_Member>> _loadMuted() async {
    final rows = await _client
        .from('club_mutes')
        .select('user_id, until, profiles(username)')
        .eq('club_id', _club.id)
        .gt('until', DateTime.now().toUtc().toIso8601String());
    return rows.map((r) {
      final p = r['profiles'];
      return _Member(
        userId: r['user_id'] as String,
        role: 'muted',
        username: p is Map ? p['username'] as String? : null,
      );
    }).toList();
  }

  Future<List<_LogEntry>> _loadLog() async {
    final rows = await _client
        .from('club_mod_log')
        .select('action, detail, created_at, actor:actor_id(username), target:target_user_id(username)')
        .eq('club_id', _club.id)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map((r) {
      String? name(dynamic e) => e is Map ? e['username'] as String? : null;
      return _LogEntry(
        action: r['action'] as String,
        detail: r['detail'] as String?,
        actor: name(r['actor']),
        target: name(r['target']),
        createdAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  Future<void> _setSlowMode(int secs) async {
    final prev = _club.slowModeSeconds;
    setState(() { _club = _copyWith(slowModeSeconds: secs); });
    try {
      await _client.from('clubs').update({'slow_mode_seconds': secs}).eq('id', _club.id);
      ClubModLog.record(_club.id, 'slow_mode', detail: _slowOptions[secs]);
    } catch (e) {
      if (mounted) setState(() { _club = _copyWith(slowModeSeconds: prev); });
      _snack('Could not update slow mode: $e');
    }
  }

  List<String> _parseWords() => _words.text
      .split(RegExp(r'[,\n]'))
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();

  Future<void> _mute(_Member m) async {
    final hours = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final opt in const [(1, 'Mute for 1 hour'), (24, 'Mute for 1 day'), (168, 'Mute for 7 days')])
              ListTile(title: Text(opt.$2), onTap: () => Navigator.pop(ctx, opt.$1)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (hours == null) return;
    final until = DateTime.now().toUtc().add(Duration(hours: hours));
    try {
      await _client.from('club_mutes').upsert(
        {'club_id': _club.id, 'user_id': m.userId, 'until': until.toIso8601String()},
        onConflict: 'club_id,user_id',
      );
      ClubModLog.record(_club.id, 'mute', targetUserId: m.userId, detail: '${hours}h');
      setState(() { _mutedFuture = _loadMuted(); });
    } catch (e) {
      _snack('Could not mute: $e');
    }
  }

  Future<void> _unmute(_Member m) async {
    try {
      await _client.from('club_mutes').delete().eq('club_id', _club.id).eq('user_id', m.userId);
      setState(() { _mutedFuture = _loadMuted(); });
    } catch (e) {
      _snack('Could not unmute: $e');
    }
  }

  Future<List<_Member>> _loadBanned() async {
    final rows = await _client
        .from('club_bans')
        .select('user_id, profiles(username)')
        .eq('club_id', _club.id)
        .order('created_at');
    return rows.map((r) {
      final p = r['profiles'];
      return _Member(
        userId: r['user_id'] as String,
        role: 'banned',
        username: p is Map ? p['username'] as String? : null,
      );
    }).toList();
  }

  Future<void> _setRole(_Member m, String role) async {
    try {
      await _client
          .from('club_members')
          .update({'role': role})
          .eq('club_id', _club.id)
          .eq('user_id', m.userId);
      ClubModLog.record(_club.id, role == 'admin' ? 'make_admin' : 'remove_admin', targetUserId: m.userId);
      setState(() { _membersFuture = _loadMembers(); });
    } catch (e) {
      _snack('Could not update role: $e');
    }
  }

  Future<void> _ban(_Member m) async {
    try {
      await _client.from('club_bans').insert({'club_id': _club.id, 'user_id': m.userId});
      await _client.from('club_members').delete().eq('club_id', _club.id).eq('user_id', m.userId);
      ClubModLog.record(_club.id, 'ban', targetUserId: m.userId);
      setState(() {
        _membersFuture = _loadMembers();
        _bannedFuture = _loadBanned();
      });
    } catch (e) {
      _snack('Could not ban: $e');
    }
  }

  Future<void> _unban(_Member m) async {
    try {
      await _client.from('club_bans').delete().eq('club_id', _club.id).eq('user_id', m.userId);
      setState(() { _bannedFuture = _loadBanned(); });
    } catch (e) {
      _snack('Could not unban: $e');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    _words.dispose();
    super.dispose();
  }

  Future<List<_Member>> _loadMembers() async {
    final rows = await _client
        .from('club_members')
        .select('user_id, role, profiles(username)')
        .eq('club_id', _club.id)
        .order('joined_at');
    return rows.map((r) {
      final p = r['profiles'];
      return _Member(
        userId: r['user_id'] as String,
        role: r['role'] as String? ?? 'member',
        username: p is Map ? p['username'] as String? : null,
      );
    }).toList();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _saveDetails() async {
    setState(() { _savingDetails = true; });
    final desc = _description.text.trim();
    final rules = _rules.text.trim();
    try {
      final rows = await _client.from('clubs').update({
        'name': _name.text.trim(),
        'description': desc.isEmpty ? null : desc,
        'rules': rules.isEmpty ? null : rules,
        'blocked_words': _parseWords(),
      }).eq('id', _club.id).select('*, club_members(count)');
      _club = Club.fromMap(rows.first);
      _snack('Club updated');
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() { _savingDetails = false; });
    }
  }

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() { _uploading = true; });
    try {
      final uid = _client.auth.currentUser!.id;
      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : 'jpg';
      final path = '$uid/club_${_club.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from(kCarPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
          );
      final url = _client.storage.from(kCarPhotosBucket).getPublicUrl(path);
      final rows = await _client
          .from('clubs')
          .update({'avatar_url': url})
          .eq('id', _club.id)
          .select('*, club_members(count)');
      _club = Club.fromMap(rows.first);
      _snack('Club photo updated');
    } catch (e) {
      _snack('Could not upload photo: $e');
    } finally {
      if (mounted) setState(() { _uploading = false; });
    }
  }

  Future<void> _changeBanner() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() { _uploading = true; });
    try {
      final uid = _client.auth.currentUser!.id;
      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : 'jpg';
      final path = '$uid/club_banner_${_club.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from(kCarPhotosBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
          );
      final url = _client.storage.from(kCarPhotosBucket).getPublicUrl(path);
      final rows = await _client
          .from('clubs')
          .update({'banner_url': url})
          .eq('id', _club.id)
          .select('*, club_members(count)');
      _club = Club.fromMap(rows.first);
      _snack('Banner updated');
    } catch (e) {
      _snack('Could not upload banner: $e');
    } finally {
      if (mounted) setState(() { _uploading = false; });
    }
  }

  Future<void> _toggleLock(bool locked) async {
    final prev = _club.isLocked;
    setState(() { _club = _copyWith(isLocked: locked); });
    try {
      await _client.from('clubs').update({'is_locked': locked}).eq('id', _club.id);
      ClubModLog.record(_club.id, locked ? 'lock' : 'unlock');
    } catch (e) {
      if (mounted) setState(() { _club = _copyWith(isLocked: prev); });
      _snack('Could not update lock: $e');
    }
  }

  Future<void> _toggleArchive(bool archived) async {
    final prev = _club.isArchived;
    setState(() { _club = _copyWith(isArchived: archived); });
    try {
      await _client.from('clubs').update({'is_archived': archived}).eq('id', _club.id);
      ClubModLog.record(_club.id, archived ? 'archive' : 'unarchive');
    } catch (e) {
      if (mounted) setState(() { _club = _copyWith(isArchived: prev); });
      _snack('Could not update archive: $e');
    }
  }

  Future<void> _transferOwnership(_Member m) async {
    final name = m.username ?? 'this member';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Make $name the owner?',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text('You\'ll become a regular member and lose admin control of this club.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Transfer', style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final me = _client.auth.currentUser!.id;
    try {
      // Roles first (while still owner), then hand over owner_id.
      await _client.from('club_members').update({'role': 'owner'}).eq('club_id', _club.id).eq('user_id', m.userId);
      await _client.from('club_members').update({'role': 'member'}).eq('club_id', _club.id).eq('user_id', me);
      final rows = await _client
          .from('clubs')
          .update({'owner_id': m.userId})
          .eq('id', _club.id)
          .select('*, club_members(count)');
      ClubModLog.record(_club.id, 'transfer', targetUserId: m.userId);
      if (mounted) Navigator.of(context).pop(ClubManageResult(club: Club.fromMap(rows.first)));
    } catch (e) {
      _snack('Could not transfer ownership: $e');
    }
  }

  Future<void> _removeMember(_Member m) async {
    try {
      await _client
          .from('club_members')
          .delete()
          .eq('club_id', _club.id)
          .eq('user_id', m.userId);
      ClubModLog.record(_club.id, 'remove', targetUserId: m.userId);
      setState(() { _membersFuture = _loadMembers(); });
    } catch (e) {
      _snack('Could not remove member: $e');
    }
  }

  Future<void> _deleteClub() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text('Delete this club?',
            style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
        content: Text(
          'This permanently removes “${_club.name}”, its threads and replies. This can\'t be undone.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.from('clubs').delete().eq('id', _club.id);
      if (mounted) Navigator.of(context).pop(const ClubManageResult(deleted: true));
    } catch (e) {
      _snack('Could not delete the club: $e');
    }
  }

  Club _copyWith({bool? isLocked, bool? isArchived, int? slowModeSeconds}) => Club(
        id: _club.id,
        name: _club.name,
        description: _club.description,
        avatarUrl: _club.avatarUrl,
        bannerUrl: _club.bannerUrl,
        ownerId: _club.ownerId,
        createdAt: _club.createdAt,
        isLocked: isLocked ?? _club.isLocked,
        isArchived: isArchived ?? _club.isArchived,
        rules: _club.rules,
        slowModeSeconds: slowModeSeconds ?? _club.slowModeSeconds,
        blockedWords: _club.blockedWords,
        memberCount: _club.memberCount,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(ClubManageResult(club: _club));
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Manage club')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Banner
              GestureDetector(
                onTap: _uploading ? null : _changeBanner,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_club.hasBanner)
                          Image.network(_club.bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _BannerPlaceholder())
                        else
                          const _BannerPlaceholder(),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(_club.hasBanner ? 'Change banner' : 'Add banner',
                                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Club icon (shown in lists)
              Row(
                children: [
                  _Avatar(club: _club),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _changePhoto,
                      icon: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ember))
                          : const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(_club.hasAvatar ? 'Change photo' : 'Add club photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ember,
                        side: const BorderSide(color: AppColors.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Details
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                decoration: const InputDecoration(labelText: 'Club name'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _description,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _rules,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                decoration: const InputDecoration(
                  labelText: 'Club rules',
                  hintText: 'House rules shown at the top of the club.',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _savingDetails ? null : _saveDetails,
                  child: _savingDetails
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onEmber))
                      : const Text('Save changes'),
                ),
              ),
              const SizedBox(height: 8),

              // Lock
              Container(
                decoration: BoxDecoration(
                  color: AppColors.graphite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: SwitchListTile(
                  value: _club.isLocked,
                  onChanged: _toggleLock,
                  activeThumbColor: AppColors.ember,
                  title: Text('Lock club',
                      style: GoogleFonts.inter(color: AppColors.cream, fontWeight: FontWeight.w600)),
                  subtitle: Text('Members can\'t post while locked. You still can.',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                  secondary: Icon(_club.isLocked ? Icons.lock : Icons.lock_open, color: AppColors.steel),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.graphite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: SwitchListTile(
                  value: _club.isArchived,
                  onChanged: _toggleArchive,
                  activeThumbColor: AppColors.ember,
                  title: Text('Archive club',
                      style: GoogleFonts.inter(color: AppColors.cream, fontWeight: FontWeight.w600)),
                  subtitle: Text('Read-only — nobody can post, including you.',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                  secondary: Icon(_club.isArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
                      color: AppColors.steel),
                ),
              ),
              const SizedBox(height: 14),

              // Slow mode
              DropdownButtonFormField<int>(
                initialValue: _slowOptions.containsKey(_club.slowModeSeconds) ? _club.slowModeSeconds : 0,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Slow mode',
                  prefixIcon: Icon(Icons.timer_outlined, color: AppColors.steel, size: 20),
                ),
                dropdownColor: AppColors.graphiteRaised,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                iconEnabledColor: AppColors.steel,
                items: [
                  for (final e in _slowOptions.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => v == null ? null : _setSlowMode(v),
              ),
              const SizedBox(height: 6),
              Text('Limits how often members can post. Mods are exempt.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),

              // Word filter
              TextField(
                controller: _words,
                maxLines: 3,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                decoration: const InputDecoration(
                  labelText: 'Blocked words',
                  hintText: 'Comma-separated. Posts containing these are rejected.',
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _savingDetails ? null : _saveDetails,
                  child: Text('Save word filter',
                      style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 24),

              // Members
              Text('Members',
                  style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
              const SizedBox(height: 8),
              FutureBuilder<List<_Member>>(
                future: _membersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(color: AppColors.ember)),
                    );
                  }
                  final members = snapshot.data ?? const <_Member>[];
                  return Column(
                    children: [
                      for (final m in members)
                        _MemberRow(
                          member: m,
                          onRemove: () => _removeMember(m),
                          onMakeOwner: () => _transferOwnership(m),
                          onToggleAdmin: () =>
                              _setRole(m, m.role == 'admin' ? 'member' : 'admin'),
                          onBan: () => _ban(m),
                          onMute: () => _mute(m),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // Banned
              FutureBuilder<List<_Member>>(
                future: _bannedFuture,
                builder: (context, snapshot) {
                  final banned = snapshot.data ?? const <_Member>[];
                  if (banned.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Banned',
                          style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
                      const SizedBox(height: 8),
                      for (final b in banned)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.block, size: 20, color: AppColors.danger),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(b.username ?? 'Member',
                                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15)),
                              ),
                              TextButton(
                                onPressed: () => _unban(b),
                                child: Text('Unban',
                                    style: GoogleFonts.inter(color: AppColors.ember, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),

              // Muted
              FutureBuilder<List<_Member>>(
                future: _mutedFuture,
                builder: (context, snapshot) {
                  final muted = snapshot.data ?? const <_Member>[];
                  if (muted.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Muted',
                          style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
                      const SizedBox(height: 8),
                      for (final m in muted)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.volume_off, size: 20, color: AppColors.steel),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(m.username ?? 'Member',
                                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15)),
                              ),
                              TextButton(
                                onPressed: () => _unmute(m),
                                child: Text('Unmute',
                                    style: GoogleFonts.inter(color: AppColors.ember, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),

              // Mod log
              FutureBuilder<List<_LogEntry>>(
                future: _logFuture,
                builder: (context, snapshot) {
                  final log = snapshot.data ?? const <_LogEntry>[];
                  if (log.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mod log',
                          style: GoogleFonts.archivo(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.cream)),
                      const SizedBox(height: 8),
                      for (final e in log)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Text(
                            e.describe(),
                            style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),

              // Delete
              OutlinedButton.icon(
                onPressed: _deleteClub,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Delete club'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Member {
  const _Member({required this.userId, required this.role, this.username});
  final String userId;
  final String role;
  final String? username;
}

class _LogEntry {
  const _LogEntry({
    required this.action,
    required this.createdAt,
    this.actor,
    this.target,
    this.detail,
  });
  final String action;
  final DateTime createdAt;
  final String? actor;
  final String? target;
  final String? detail;

  String describe() {
    const verbs = {
      'ban': 'banned', 'mute': 'muted', 'remove': 'removed', 'make_admin': 'made admin',
      'remove_admin': 'removed admin from', 'transfer': 'transferred ownership to',
      'lock': 'locked the club', 'unlock': 'unlocked the club',
      'archive': 'archived the club', 'unarchive': 'unarchived the club',
      'slow_mode': 'set slow mode',
    };
    final who = actor ?? 'A mod';
    final verb = verbs[action] ?? action;
    final tgt = target != null ? ' $target' : '';
    final extra = detail != null ? ' ($detail)' : '';
    return '$who $verb$tgt$extra · ${timeAgo(createdAt)}';
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.onRemove,
    required this.onMakeOwner,
    required this.onToggleAdmin,
    required this.onBan,
    required this.onMute,
  });
  final _Member member;
  final VoidCallback onRemove;
  final VoidCallback onMakeOwner;
  final VoidCallback onToggleAdmin;
  final VoidCallback onBan;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final name = member.username ?? 'Member';
    final isOwner = member.role == 'owner';
    final isAdmin = member.role == 'admin';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(color: AppColors.graphiteRaised, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.inter(color: AppColors.steel, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15)),
          ),
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('Admin',
                  style: GoogleFonts.inter(color: AppColors.steel, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          if (isOwner)
            Text('Owner', style: GoogleFonts.inter(color: AppColors.ember, fontSize: 12, fontWeight: FontWeight.w700))
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.steel, size: 20),
              color: AppColors.graphiteRaised,
              onSelected: (v) => switch (v) {
                'owner' => onMakeOwner(),
                'admin' => onToggleAdmin(),
                'mute' => onMute(),
                'ban' => onBan(),
                _ => onRemove(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'admin', child: Text(isAdmin ? 'Remove admin' : 'Make admin')),
                const PopupMenuItem(value: 'owner', child: Text('Make owner')),
                const PopupMenuItem(value: 'mute', child: Text('Mute…')),
                const PopupMenuItem(value: 'remove', child: Text('Remove from club')),
                const PopupMenuItem(value: 'ban', child: Text('Ban from club')),
              ],
            ),
        ],
      ),
    );
  }
}

class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 30, color: AppColors.steel),
          SizedBox(height: 6),
          Text('Club banner', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.club});
  final Club club;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 64, height: 64,
        child: club.hasAvatar
            ? Image.network(club.avatarUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback())
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.graphiteRaised,
        alignment: Alignment.center,
        child: Text(club.name.isNotEmpty ? club.name[0].toUpperCase() : '#',
            style: GoogleFonts.archivo(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ember)),
      );
}
