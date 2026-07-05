import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/partner_page.dart';
import 'package:torqueden/screens/add_car_screen.dart' show kCarPhotosBucket;
import 'package:torqueden/theme.dart';

/// Create or edit the current partner's page. Pops the saved [PartnerPage].
class EditPartnerPageScreen extends StatefulWidget {
  const EditPartnerPageScreen({super.key, this.page});

  final PartnerPage? page;

  @override
  State<EditPartnerPageScreen> createState() => _EditPartnerPageScreenState();
}

class _EditPartnerPageScreenState extends State<EditPartnerPageScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _website = TextEditingController();

  Uint8List? _bannerBytes;
  String? _bannerName;
  String? _bannerUrl;
  bool _saving = false;

  bool get _isEditing => widget.page != null;

  @override
  void initState() {
    super.initState();
    final p = widget.page;
    if (p != null) {
      _name.text = p.businessName;
      _bio.text = p.bio ?? '';
      _website.text = p.websiteUrl ?? '';
      _bannerUrl = p.bannerUrl;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _website.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickBanner() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() { _bannerBytes = bytes; _bannerName = picked.name; });
  }

  /// Normalises a typed website into a launchable https URL.
  String? _normalisedWebsite() {
    var w = _website.text.trim();
    if (w.isEmpty) return null;
    if (!w.startsWith('http://') && !w.startsWith('https://')) w = 'https://$w';
    return w;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final uid = _client.auth.currentUser!.id;
    try {
      var bannerUrl = _bannerUrl;
      if (_bannerBytes != null) {
        final ext = (_bannerName ?? 'jpg').split('.').last.toLowerCase();
        // Unique path + no upsert — the car-photos bucket only grants a plain
        // INSERT, so overwriting (upsert) is rejected by storage RLS.
        final path = '$uid/partner_banner_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage.from(kCarPhotosBucket).uploadBinary(
              path,
              _bannerBytes!,
              fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
            );
        bannerUrl = _client.storage.from(kCarPhotosBucket).getPublicUrl(path);
      }
      final bio = _bio.text.trim();
      final rows = await _client.from('partner_pages').upsert({
        'owner_id': uid,
        'business_name': _name.text.trim(),
        'bio': bio.isEmpty ? null : bio,
        'banner_url': ?bannerUrl,
        'website_url': ?_normalisedWebsite(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'owner_id').select();
      if (mounted) Navigator.of(context).pop(PartnerPage.fromMap(rows.first));
    } on PostgrestException catch (e) {
      _snack(e.code == '42501' ? 'Only Partner members can create a page.' : 'Could not save: ${e.message}');
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      _snack('Could not save: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Partner Page' : 'Create Partner Page')),
      body: SafeArea(
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
                        ? Image.memory(_bannerBytes!, fit: BoxFit.cover)
                        : (_bannerUrl?.isNotEmpty ?? false)
                            ? Image.network(_bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _BannerHint())
                            : const _BannerHint(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Add your business name' : null,
                decoration: const InputDecoration(labelText: 'Business / brand name *'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bio,
                maxLines: 5,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell the community who you are and what you do.',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _website,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Website',
                  hintText: 'yourshop.co.uk',
                  prefixIcon: Icon(Icons.link, color: AppColors.steel),
                ),
              ),
              const SizedBox(height: 16),
              if (_saving)
                const Center(child: CircularProgressIndicator(color: AppColors.ember))
              else
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(_isEditing ? 'Save changes' : 'Create page'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerHint extends StatelessWidget {
  const _BannerHint();
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
          Icon(Icons.image_outlined, size: 34, color: AppColors.steel),
          SizedBox(height: 8),
          Text('Add a banner', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}
