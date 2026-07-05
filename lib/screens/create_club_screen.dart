import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/club.dart';
import 'package:torqueden/screens/add_car_screen.dart' show kCarPhotosBucket;
import 'package:torqueden/theme.dart';

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
    final bytes = await picked.readAsBytes();
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
    final bytes = await picked.readAsBytes();
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
    final desc = _description.text.trim();
    final rules = _rules.text.trim();
    try {
      // owner_id defaults to auth.uid(); the trigger adds owner membership.
      final rows = await client.from('clubs').insert({
        'name': _name.text.trim(),
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
      _fail('Could not create the club: ${e.message}');
    } catch (e) {
      _fail('Could not create the club: $e');
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
      appBar: AppBar(title: const Text('Create a club')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GestureDetector(
                    onTap: _saving ? null : _pickBanner,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _bannerBytes != null
                            ? Stack(fit: StackFit.expand, children: [
                                Image.memory(_bannerBytes!, fit: BoxFit.cover),
                                const Positioned(
                                  right: 10,
                                  bottom: 10,
                                  child: _Badge(text: 'Change banner'),
                                ),
                              ])
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.graphiteRaised,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.hairline),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_outlined, size: 34, color: AppColors.steel),
                                    SizedBox(height: 8),
                                    Text('Add a banner (optional)',
                                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Club icon — shown in search results and the clubs list.
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _saving ? null : _pickIcon,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: _iconBytes != null
                                ? Image.memory(_iconBytes!, fit: BoxFit.cover)
                                : DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.graphiteRaised,
                                      border: Border.all(color: AppColors.hairline),
                                    ),
                                    child: const Icon(Icons.groups, color: AppColors.steel),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _pickIcon,
                              icon: const Icon(Icons.photo_camera_outlined, size: 18),
                              label: Text(_iconBytes != null ? 'Change icon' : 'Add club icon'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.ember,
                                side: const BorderSide(color: AppColors.hairline),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('Shown in search and your clubs list.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 60,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Give your club a name' : null,
                    decoration: const InputDecoration(
                      labelText: 'Club name *',
                      hintText: 'e.g. E85 Tuning',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _description,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'What\'s it about?',
                      hintText: 'A line or two so people know what they\'re joining.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _rules,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Club rules (optional)',
                      hintText: 'House rules shown at the top of the club.',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    value: _private,
                    onChanged: _saving ? null : (v) => setState(() => _private = v),
                    activeThumbColor: AppColors.ember,
                    tileColor: AppColors.graphite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: AppColors.hairline),
                    ),
                    title: const Text('Private club',
                        style: TextStyle(color: AppColors.cream, fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                        'People must request to join, and only members see the discussions.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    secondary: Icon(_private ? Icons.lock : Icons.public, color: AppColors.steel),
                  ),
                  const SizedBox(height: 16),
                  if (_saving)
                    const Center(child: CircularProgressIndicator(color: AppColors.ember))
                  else
                    FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.groups, size: 20),
                      label: const Text('Create club'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _private
                        ? 'Your club is private — it\'s still listed in Discover, but people must request to join and only members can see posts. You\'re the owner and can remove posts.'
                        : 'Your club is public — anyone can find it and join. You\'re the owner and can remove posts.',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.cream, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
