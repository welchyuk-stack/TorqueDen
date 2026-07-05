import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/services/location_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/utils/link_guard.dart';

/// Name of the public Supabase Storage bucket that holds car photos.
const String kCarPhotosBucket = 'car-photos';

/// Form to add a car to your garage, or edit an existing one.
///
/// Pass [car] to edit it; leave it null to add a new car. On a successful save
/// it pops with the saved [Car] (the fresh row from Supabase, including its id),
/// so the caller can refresh or update its view.
class AddCarScreen extends StatefulWidget {
  const AddCarScreen({super.key, this.car});

  /// The car being edited, or null when adding a new one.
  final Car? car;

  @override
  State<AddCarScreen> createState() => _AddCarScreenState();
}

class _AddCarScreenState extends State<AddCarScreen> {
  final _formKey = GlobalKey<FormState>();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _chassis = TextEditingController();
  final _year = TextEditingController();
  final _nickname = TextEditingController();
  final _color = TextEditingController();
  final _description = TextEditingController();

  bool _saving = false;

  // Photo state. _pickedBytes holds a freshly chosen image (not yet uploaded);
  // otherwise we fall back to the car's existing photoUrl when editing.
  Uint8List? _pickedBytes;
  String? _pickedName;

  // Location state — where this car is based (optional).
  double? _lat;
  double? _lng;
  String? _locationLabel;
  bool _locating = false;

  bool get _isEditing => widget.car != null;
  bool get _hasLocation => _lat != null && _lng != null;

  @override
  void initState() {
    super.initState();
    final car = widget.car;
    if (car != null) {
      _make.text = car.make;
      _model.text = car.model;
      _chassis.text = car.chassisModel ?? '';
      _year.text = car.year?.toString() ?? '';
      _nickname.text = car.nickname ?? '';
      _color.text = car.color ?? '';
      _description.text = car.description ?? '';
      _lat = car.latitude;
      _lng = car.longitude;
      _locationLabel = car.locationName;
    }
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _chassis.dispose();
    _year.dispose();
    _nickname.dispose();
    _color.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) {
      setState(() {
        _pickedBytes = bytes;
        _pickedName = picked.name;
      });
    }
  }

  /// Uploads the freshly picked image (if any) and returns its public URL.
  /// Returns null if no new image was picked.
  Future<String?> _uploadPhotoIfNeeded(String userId) async {
    if (_pickedBytes == null) return null;
    final client = Supabase.instance.client;
    final ext = (_pickedName ?? 'photo.jpg').split('.').last.toLowerCase();
    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    // Unique, timestamped filename per upload, so this is always a fresh insert
    // (no upsert — upsert needs an extra UPDATE storage policy and buys us
    // nothing when the path never collides).
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await client.storage.from(kCarPhotosBucket).uploadBinary(
          path,
          _pickedBytes!,
          fileOptions: FileOptions(contentType: contentType),
        );
    return client.storage.from(kCarPhotosBucket).getPublicUrl(path);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final place = await LocationService.currentPlace();
      if (!mounted) return;
      setState(() {
        _lat = place.latitude;
        _lng = place.longitude;
        _locationLabel = place.label;
      });
    } on LocationException catch (e) {
      _notify(e.message);
    } catch (e) {
      _notify('Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _lat = null;
      _lng = null;
      _locationLabel = null;
    });
  }

  /// Short-lived informational snackbar (doesn't touch the saving state).
  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Keep the garage promotion-free — links belong on a Partner Page.
    if (containsUrl(_description.text) || containsUrl(_nickname.text)) {
      _notify('Links aren\'t allowed in the garage. Businesses can add their website on a Partner Page.');
      return;
    }
    setState(() => _saving = true);

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    // Stage 1 — upload the photo first (only if a new one was picked).
    // Kept separate so a storage failure reports clearly and doesn't get
    // mistaken for a database problem.
    String? uploadedUrl;
    try {
      uploadedUrl = await _uploadPhotoIfNeeded(userId);
    } on StorageException catch (e) {
      _fail('Photo upload failed: ${e.message}');
      return;
    } catch (e) {
      _fail('Photo upload failed: $e');
      return;
    }

    // Stage 2 — save the row.
    final yearText = _year.text.trim();
    final chassis = _chassis.text.trim();
    final nickname = _nickname.text.trim();
    final color = _color.text.trim();
    final description = _description.text.trim();

    final payload = {
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      'chassis_model': chassis.isEmpty ? null : chassis,
      'year': yearText.isEmpty ? null : int.tryParse(yearText),
      'nickname': nickname.isEmpty ? null : nickname,
      'color': color.isEmpty ? null : color,
      'description': description.isEmpty ? null : description,
      // Only overwrite the photo when a new one was picked; keep the old one
      // otherwise (don't send null and wipe it on an edit).
      'photo_url': ?uploadedUrl,
      // Location is sent as-is (including null) so clearing it persists.
      'latitude': _lat,
      'longitude': _lng,
      'location_name': _locationLabel,
    };

    try {
      final table = client.from('cars');
      // .select() returns the saved row so the future completes (esp. on web)
      // and we get back the id / generated columns.
      final rows = _isEditing
          ? await table.update(payload).eq('id', widget.car!.id).select()
          // owner_id is filled in automatically by the table's default (auth.uid()).
          : await table.insert(payload).select();
      if (mounted) Navigator.of(context).pop(Car.fromMap(rows.first));
    } on PostgrestException catch (e) {
      _fail('Save failed: ${e.message}');
    } catch (e) {
      _fail('Could not save the car: $e');
    }
  }

  /// Shows a (longer-lived) error message and re-enables the form.
  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
    setState(() => _saving = false);
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _yearValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null; // optional
    final n = int.tryParse(t);
    if (n == null) return 'Numbers only';
    if (n < 1900 || n > 2100) return 'Enter a real year';
    return null;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit car' : 'Add a car')),
      body: SafeArea(
        // Centre + cap the width so the form stays tidy on wide windows
        // (web/desktop) instead of stretching edge to edge.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PhotoPicker(
                    pickedBytes: _pickedBytes,
                    existingUrl: widget.car?.photoUrl,
                    onTap: _saving ? null : _pickPhoto,
                  ),
                  const SizedBox(height: 20),
                  _field(_make, 'Make *',
                      hint: 'e.g. BMW',
                      textCapitalization: TextCapitalization.words,
                      validator: _required),
                  const SizedBox(height: 14),
                  _field(_model, 'Model *',
                      hint: 'e.g. M2',
                      textCapitalization: TextCapitalization.words,
                      validator: _required),
                  const SizedBox(height: 14),
                  _field(_chassis, 'Chassis Model',
                      hint: 'e.g. G87',
                      textCapitalization: TextCapitalization.characters),
                  const SizedBox(height: 14),
                  _field(_year, 'Year',
                      hint: 'e.g. 2023',
                      keyboardType: TextInputType.number,
                      validator: _yearValidator),
                  const SizedBox(height: 14),
                  _field(_nickname, 'Nickname (optional)', hint: 'e.g. Project Apex'),
                  const SizedBox(height: 14),
                  _field(_color, 'Colour', hint: 'e.g. Black Sapphire Metallic'),
                  const SizedBox(height: 14),
                  _LocationField(
                    hasLocation: _hasLocation,
                    label: _locationLabel,
                    busy: _locating,
                    onUseCurrent: _saving || _locating ? null : _useCurrentLocation,
                    onClear: _saving || _locating ? null : _clearLocation,
                  ),
                  const SizedBox(height: 14),
                  _field(_description, 'Notes',
                      hint: 'Anything about the build…', maxLines: 4),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.onEmber),
                          )
                        : Text(_isEditing ? 'Save changes' : 'Save car'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable photo area at the top of the form. Shows the freshly picked image,
/// then the car's existing photo, then an "add a photo" prompt.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.pickedBytes,
    required this.existingUrl,
    required this.onTap,
  });

  final Uint8List? pickedBytes;
  final String? existingUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasExisting = existingUrl != null && existingUrl!.trim().isNotEmpty;
    final showsImage = pickedBytes != null || hasExisting;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (pickedBytes != null)
                Image.memory(pickedBytes!, fit: BoxFit.cover)
              else if (hasExisting)
                Image.network(existingUrl!, fit: BoxFit.cover)
              else
                _buildPrompt(),
              // "Change photo" affordance once an image is shown.
              if (showsImage)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera_outlined, size: 16, color: AppColors.cream),
                        SizedBox(width: 6),
                        Text('Change', style: TextStyle(color: AppColors.cream, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrompt() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, size: 34, color: AppColors.steel),
          SizedBox(height: 10),
          Text('Add a photo', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

/// "Where is this car based?" — a card that captures the device location so the
/// car can appear in nearby searches. Optional; can be cleared.
class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.hasLocation,
    required this.label,
    required this.busy,
    required this.onUseCurrent,
    required this.onClear,
  });

  final bool hasLocation;
  final String? label;
  final bool busy;
  final VoidCallback? onUseCurrent;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation ? Icons.location_on : Icons.location_off_outlined,
            color: hasLocation ? AppColors.ember : AppColors.steel,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasLocation
                      ? (label ?? 'Location set')
                      : 'Add so people nearby can find it',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: hasLocation ? AppColors.cream : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ember),
            )
          else if (hasLocation)
            IconButton(
              tooltip: 'Clear location',
              onPressed: onClear,
              icon: const Icon(Icons.close, color: AppColors.steel),
            )
          else
            TextButton.icon(
              onPressed: onUseCurrent,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use current'),
            ),
        ],
      ),
    );
  }
}
