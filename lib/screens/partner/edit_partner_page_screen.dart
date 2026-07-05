import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/partner_page.dart';
import 'package:torqueden/screens/add_car_screen.dart' show kCarPhotosBucket;
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/banner_framer_screen.dart';

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
  final _address = TextEditingController();
  final _contactEmail = TextEditingController();

  Uint8List? _bannerBytes; // freshly cropped banner, if changed
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
      _address.text = p.address ?? '';
      _contactEmail.text = p.contactEmail ?? '';
      _bannerUrl = p.bannerUrl;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _website.dispose();
    _address.dispose();
    _contactEmail.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickBanner() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    if (!mounted) return;
    final framed = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => BannerFramerScreen(bytes: raw)),
    );
    if (framed != null && mounted) setState(() => _bannerBytes = framed);
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
      final b = _bannerBytes;
      if (b != null) {
        // Detect format from the cropped bytes (unique path, no upsert).
        final isPng = b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
        final ext = isPng ? 'png' : 'jpg';
        final path = '$uid/partner_banner_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage.from(kCarPhotosBucket).uploadBinary(
              path,
              b,
              fileOptions: FileOptions(contentType: isPng ? 'image/png' : 'image/jpeg'),
            );
        bannerUrl = _client.storage.from(kCarPhotosBucket).getPublicUrl(path);
      }
      final bio = _bio.text.trim();
      final address = _address.text.trim();
      final email = _contactEmail.text.trim();
      final rows = await _client.from('partner_pages').upsert({
        'owner_id': uid,
        'business_name': _name.text.trim(),
        'bio': bio.isEmpty ? null : bio,
        'banner_url': ?bannerUrl,
        'website_url': ?_normalisedWebsite(),
        'address': address.isEmpty ? null : address,
        'contact_email': email.isEmpty ? null : email,
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
    final hasBanner = _bannerBytes != null || (_bannerUrl?.isNotEmpty ?? false);
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_bannerBytes != null)
                          Image.memory(_bannerBytes!, fit: BoxFit.cover)
                        else if (_bannerUrl?.isNotEmpty ?? false)
                          Image.network(_bannerUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _BannerHint())
                        else
                          const _BannerHint(),
                        if (hasBanner)
                          const Positioned(
                            right: 10,
                            bottom: 10,
                            child: _Badge(text: 'Change banner'),
                          ),
                      ],
                    ),
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
                controller: _address,
                maxLines: 3,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Business address',
                  hintText: 'Unit / street, town, postcode',
                  prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.steel),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactEmail,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null; // optional
                  return (s.contains('@') && s.contains('.')) ? null : 'Enter a valid email';
                },
                decoration: const InputDecoration(
                  labelText: 'Contact email',
                  hintText: 'hello@yourshop.co.uk',
                  prefixIcon: Icon(Icons.mail_outline, color: AppColors.steel),
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
