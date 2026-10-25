import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/screens/add_car_screen.dart' show kCarPhotosBucket;
import 'package:torqueden/utils/image_compress.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/settings_group.dart';
import 'package:torqueden/widgets/upgrade_sheet.dart';

/// Create a new club. Pops the created [Club] on success (the owner is added as
/// a member automatically by a DB trigger).
class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _rules = TextEditingController();
  bool _saving = false;
  bool _private = false;

  Uint8List? _bannerBytes;
  String? _bannerName;
  Uint8List? _iconBytes;
  String? _iconName;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _pickBanner() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    final bytes = await compressImageBytes(raw);
    if (!mounted) return;
    setState(() {
      _bannerBytes = bytes;
      _bannerName = picked.name;
    });
  }

  Future<void> _pickIcon() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    final bytes = await compressImageBytes(raw);
    if (!mounted) return;
    setState(() {
      _iconBytes = bytes;
      _iconName = picked.name;
    });
  }

  /// Uploads image bytes and returns its public URL. Path is per-new-club so
  /// no upsert is needed (the car-photos bucket only grants a plain INSERT).
  Future<String> _upload(SupabaseClient client, String base, Uint8List bytes, String? name) async {
    final uid = client.auth.currentUser!.id;
    final ext = (name ?? 'jpg').split('.').last.toLowerCase();
    final path = '$uid/$base.$ext';
    await client.storage.from(kCarPhotosBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        );
    return client.storage.from(kCarPhotosBucket).getPublicUrl(path);
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    final clubName = _name.text.trim();
    final desc = _description.text.trim();
    final rules = _rules.text.trim();
    try {
      // Duplicate name check
      final existing = await client
          .from('clubs')
          .select('id')
          .ilike('name', clubName)
          .limit(1);
      if (existing.isNotEmpty) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('A forum called "$clubName" already exists. Choose a different name.')),
        );
        return;
      }
      // owner_id defaults to auth.uid(); the trigger adds owner membership.
      final rows = await client.from('clubs').insert({
        'name': clubName,
        'description': desc.isEmpty ? null : desc,
        'rules': rules.isEmpty ? null : rules,
        'is_private': _private,
      }).select('*, club_members(count)');
      var club = Club.fromMap(rows.first);

      // Upload the banner / icon (if chosen) now that we have the club id.
      final updates = <String, dynamic>{};
      if (_bannerBytes != null) {
        updates['banner_url'] = await _upload(client, 'club_banner_${club.id}', _bannerBytes!, _bannerName);
      }
      if (_iconBytes != null) {
        updates['avatar_url'] = await _upload(client, 'club_icon_${club.id}', _iconBytes!, _iconName);
      }
      if (updates.isNotEmpty) {
        final updated = await client
            .from('clubs')
            .update(updates)
            .eq('id', club.id)
            .select('*, club_members(count)');
        club = Club.fromMap(updated.first);
      }

      if (mounted) Navigator.of(context).pop(club);
    } on PostgrestException catch (e) {
      _fail('Could not create the forum: ${e.message}');
    } catch (e) {
      _fail('Could not create the forum: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
    );
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a forum'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ember),
                    ),
                  )
                : TextButton(
                    onPressed: _create,
                    child: Text('Create',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.ember,
                        )),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [

                  // ── Banner ────────────────────────────────────────────
                  GestureDetector(
                    onTap: _saving ? null : _pickBanner,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 7,
                        child: _bannerBytes != null
                            ? Stack(fit: StackFit.expand, children: [
                                Image.memory(_bannerBytes!, fit: BoxFit.cover),
                                Positioned(
                                  right: 12, bottom: 12,
                                  child: _PillBadge(
                                    icon: Icons.photo_camera_outlined,
                                    text: 'Change banner',
                                  ),
                                ),
                              ])
                            : Container(
                                decoration: AppDecorations.glassCard(radius: 16),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_outlined, size: 32, color: AppColors.steel),
                                    const SizedBox(height: 8),
                                    Text('Add banner image',
                                        style: GoogleFonts.inter(
                                            color: AppColors.textSecondary, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text('optional',
                                        style: GoogleFonts.inter(
                                            color: AppColors.textMuted, fontSize: 12)),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Icon + Name row ───────────────────────────────────
                  Container(
                    decoration: AppDecorations.glassCard(radius: 16),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Single tap target for icon
                        GestureDetector(
                          onTap: _saving ? null : _pickIcon,
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 72, height: 72,
                                  child: _iconBytes != null
                                      ? Image.memory(_iconBytes!, fit: BoxFit.cover)
                                      : Container(
                                          color: AppColors.graphite,
                                          child: Icon(Icons.groups_outlined,
                                              color: AppColors.steel, size: 32),
                                        ),
                                ),
                              ),
                              Positioned(
                                right: 0, bottom: 0,
                                child: Container(
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    color: AppColors.ember,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.carbon, width: 2),
                                  ),
                                  child: const Icon(Icons.photo_camera,
                                      color: Colors.white, size: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 60,
                                style: GoogleFonts.spaceGrotesk(
                                    color: AppColors.cream,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Give your forum a name'
                                        : null,
                                decoration: InputDecoration(
                                  labelText: 'Forum name *',
                                  hintText: 'e.g. E85 Tuning',
                                  counterStyle: GoogleFonts.inter(
                                      color: AppColors.textMuted, fontSize: 11),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Description + Rules ───────────────────────────────
                  Container(
                    decoration: AppDecorations.glassCard(radius: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _description,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 3,
                          maxLength: 300,
                          style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: 'What\'s it about?',
                            hintText: 'A line or two so people know what they\'re joining.',
                            counterStyle: GoogleFonts.inter(
                                color: AppColors.textMuted, fontSize: 11),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                        Divider(height: 1, color: AppColors.hairline),
                        TextFormField(
                          controller: _rules,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 3,
                          maxLength: 500,
                          style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: 'Forum rules',
                            hintText: 'House rules shown at the top of the forum. Optional.',
                            counterStyle: GoogleFonts.inter(
                                color: AppColors.textMuted, fontSize: 11),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Privacy toggle ────────────────────────────────────
                  SettingsGroup(
                    children: [
                      if (Entitlements.canCreatePrivateClubs)
                        SwitchListTile(
                          value: _private,
                          onChanged: _saving ? null : (v) => setState(() => _private = v),
                          activeThumbColor: AppColors.ember,
                          secondary: Icon(
                              _private ? Icons.lock : Icons.public_outlined,
                              color: AppColors.steel),
                          title: Text('Private forum',
                              style: GoogleFonts.inter(
                                  color: AppColors.cream,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          subtitle: Text(
                              'Members only — people must request to join.',
                              style: GoogleFonts.inter(
                                  color: AppColors.textMuted, fontSize: 13)),
                        )
                      else
                        ListTile(
                          onTap: () => showUpgradeSheet(
                            context,
                            title: 'Private forums are Premium',
                            message: 'Free forums are public. Upgrade to Premium to create '
                                'private, request-to-join forums.',
                          ),
                          leading: Icon(Icons.lock_outline, color: AppColors.steel),
                          title: Text('Private forum',
                              style: GoogleFonts.inter(
                                  color: AppColors.cream,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          subtitle: Text('Premium — tap to upgrade',
                              style: GoogleFonts.inter(
                                  color: AppColors.textMuted, fontSize: 13)),
                          trailing: const Icon(Icons.workspace_premium_outlined,
                              color: AppColors.ember),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _private
                          ? 'Private forums are listed in Discover but members-only to view. You\'re the owner and can remove posts.'
                          : 'Public forums are open to everyone — anyone can find and join. You\'re the owner and can remove posts.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textMuted, height: 1.4),
                    ),
                  ),

                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _create,
                    icon: const Icon(Icons.groups, size: 20),
                    label: const Text('Create forum'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.cream),
          const SizedBox(width: 5),
          Text(text,
              style: GoogleFonts.inter(
                  color: AppColors.cream,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
