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
  bool _saving = false;

  Uint8List? _bannerBytes;
  String? _bannerName;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
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

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    final desc = _description.text.trim();
    try {
      // owner_id defaults to auth.uid(); the trigger adds owner membership.
      final rows = await client.from('clubs').insert({
        'name': _name.text.trim(),
        'description': desc.isEmpty ? null : desc,
      }).select('*, club_members(count)');
      var club = Club.fromMap(rows.first);

      // Upload the banner (if chosen) now that we have the club id.
      if (_bannerBytes != null) {
        final uid = client.auth.currentUser!.id;
        final ext = (_bannerName ?? 'jpg').split('.').last.toLowerCase();
        final path = '$uid/club_banner_${club.id}.$ext';
        await client.storage.from(kCarPhotosBucket).uploadBinary(
              path,
              _bannerBytes!,
              fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
            );
        final url = client.storage.from(kCarPhotosBucket).getPublicUrl(path);
        final updated = await client
            .from('clubs')
            .update({'banner_url': url})
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
                  const SizedBox(height: 12),
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
                    'Your club is public — anyone can find it and join. You\'re the owner and can remove posts.',
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
