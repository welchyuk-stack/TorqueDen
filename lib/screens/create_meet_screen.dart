import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/models/car_meet.dart';
import 'package:torqueden/theme.dart';

class CreateMeetScreen extends StatefulWidget {
  const CreateMeetScreen({super.key, this.meet});
  final CarMeet? meet; // non-null = edit mode

  @override
  State<CreateMeetScreen> createState() => _CreateMeetScreenState();
}

class _CreateMeetScreenState extends State<CreateMeetScreen> {
  final _client = Supabase.instance.client;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _mapCtrl = MapController();

  DateTime? _meetAt;
  LatLng? _pin;
  Uint8List? _coverBytes;
  bool _saving = false;
  bool _geocoding = false;
  String? _geocodeError;

  bool get _isEdit => widget.meet != null;

  @override
  void initState() {
    super.initState();
    final m = widget.meet;
    if (m != null) {
      _titleCtrl.text = m.title;
      _descCtrl.text = m.description ?? '';
      _locationCtrl.text = m.locationName;
      _addressCtrl.text = m.address ?? '';
      _meetAt = m.meetAt;
      if (m.hasCoords) {
        _pin = LatLng(m.latitude!, m.longitude!);
      } else if ((m.address ?? '').trim().isNotEmpty) {
        // address saved but no coords yet — geocode on load
        WidgetsBinding.instance.addPostFrameCallback((_) => _geocodeAddress());
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      _titleCtrl.text.trim().length >= 3 &&
      _locationCtrl.text.trim().length >= 2 &&
      _meetAt != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.ember,
            onPrimary: AppColors.onEmber,
            surface: AppColors.graphite,
            onSurface: AppColors.cream,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.ember,
            onPrimary: AppColors.onEmber,
            surface: AppColors.graphite,
            onSurface: AppColors.cream,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _meetAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickCover() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _coverBytes = bytes);
  }

  Future<void> _locateMe() async {
    if (kIsWeb) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() { _pin = ll; _geocodeError = null; });
      _mapCtrl.move(ll, 15);

      // Reverse geocode to fill address field
      try {
        final placemarks = await geo.Geocoding().placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          final parts = [p.street, p.locality, p.postalCode].where((s) => s?.isNotEmpty == true);
          _addressCtrl.text = parts.join(', ');
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _geocodeAddress() async {
    if (kIsWeb) return;
    final query = _addressCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() { _geocoding = true; _geocodeError = null; });
    try {
      final locations = await geo.Geocoding().locationFromAddress(query);
      if (locations.isEmpty) {
        setState(() { _geocodeError = 'Address not found'; _geocoding = false; });
        return;
      }
      final loc = locations.first;
      final ll = LatLng(loc.latitude, loc.longitude);
      setState(() { _pin = ll; _geocoding = false; });
      _mapCtrl.move(ll, 15);
    } catch (_) {
      if (mounted) setState(() { _geocodeError = 'Could not find address'; _geocoding = false; });
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    final uid = _client.auth.currentUser?.id;
    if (uid == null || !_canSave) return;

    // Duplicate meet check (skip when editing the same meet)
    if (!_isEdit && _meetAt != null) {
      final weekStart = _meetAt!.subtract(Duration(days: _meetAt!.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));
      final dupes = await _client
          .from('car_meets')
          .select('id')
          .ilike('title', title)
          .gte('meet_at', weekStart.toUtc().toIso8601String())
          .lt('meet_at', weekEnd.toUtc().toIso8601String())
          .limit(1);
      if (dupes.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.graphite,
            title: Text('Meet already exists?',
                style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700)),
            content: Text(
              'A meet called "$title" is already scheduled this week. Are you sure you want to create another one?',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Create anyway', style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    setState(() => _saving = true);
    try {
      String? coverUrl;
      if (_coverBytes != null) {
        final path = '$uid/meet_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _client.storage.from(kCarPhotosBucket).uploadBinary(
          path, _coverBytes!,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        coverUrl = _client.storage.from(kCarPhotosBucket).getPublicUrl(path);
      }

      final addr = _addressCtrl.text.trim();
      final payload = {
        'title': title,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'location_name': location,
        if (addr.isNotEmpty) 'address': addr,
        'latitude': _pin?.latitude,
        'longitude': _pin?.longitude,
        'meet_at': _meetAt!.toUtc().toIso8601String(),
        if (coverUrl != null) 'cover_url': coverUrl,
      };

      if (_isEdit) {
        await _client.from('car_meets').update(payload).eq('id', widget.meet!.id);
      } else {
        await _client.from('car_meets').insert({'creator_id': uid, ...payload});
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not ${_isEdit ? 'update' : 'create'} meet: $e'),
            backgroundColor: AppColors.danger),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(_isEdit ? 'Edit meet' : 'New meet', style: GoogleFonts.archivo(fontWeight: FontWeight.w700, color: AppColors.cream)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit ? 'Save' : 'Create', style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 16,
                      color: _canSave ? AppColors.ember : AppColors.steel,
                    )),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover photo
              GestureDetector(
                onTap: _pickCover,
                child: Container(
                  height: 160,
                  decoration: AppDecorations.glassCard(radius: 14),
                  clipBehavior: Clip.antiAlias,
                  child: _coverBytes != null
                      ? Image.memory(_coverBytes!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 36, color: AppColors.steel),
                            const SizedBox(height: 8),
                            Text('Add cover photo (optional)', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              _Field(
                controller: _titleCtrl,
                label: 'Meet name',
                hint: 'e.g. Sunday Morning Cruise',
                onChanged: (_) => setState(() {}),
                maxLength: 100,
              ),
              const SizedBox(height: 12),

              // Date & time
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: AppDecorations.glassCard(radius: 12),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.steel),
                      const SizedBox(width: 12),
                      Text(
                        _meetAt == null ? 'Date & time' : _formatDateTime(_meetAt!),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: _meetAt == null ? AppColors.textMuted : AppColors.cream,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Display location name (shown in feed / cards)
              _Field(
                controller: _locationCtrl,
                label: 'Location name',
                hint: 'e.g. Caffè Nero car park, Manchester',
                onChanged: (_) => setState(() {}),
                maxLength: 200,
              ),
              const SizedBox(height: 12),

              // Map section
              Container(
                decoration: AppDecorations.glassCard(radius: 14),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Address search row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addressCtrl,
                              style: GoogleFonts.inter(fontSize: 14, color: AppColors.cream),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _geocodeAddress(),
                              decoration: InputDecoration(
                                hintText: 'Search address or postcode…',
                                hintStyle: GoogleFonts.inter(fontSize: 14, color: AppColors.steel),
                                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.steel),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          if (_geocoding)
                            const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            IconButton(
                              icon: Icon(Icons.my_location, size: 18, color: AppColors.ember),
                              tooltip: 'Use my location',
                              onPressed: _locateMe,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                    if (_geocodeError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(_geocodeError!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.danger)),
                      ),
                    Divider(height: 1, color: AppColors.hairline),

                    // Map
                    SizedBox(
                      height: 240,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapCtrl,
                            options: MapOptions(
                              initialCenter: _pin ?? const LatLng(54.0, -2.0),
                              initialZoom: _pin != null ? 15 : 5,
                              onTap: (_, ll) => setState(() { _pin = ll; _geocodeError = null; }),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.torqueden.app',
                              ),
                              if (_pin != null)
                                MarkerLayer(markers: [
                                  Marker(
                                    point: _pin!,
                                    width: 36,
                                    height: 36,
                                    child: Icon(Icons.location_on, color: AppColors.ember, size: 36),
                                  ),
                                ]),
                            ],
                          ),
                          // Zoom controls
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Column(
                              children: [
                                _MapBtn(icon: Icons.add, onTap: () => _mapCtrl.move(
                                  _mapCtrl.camera.center, _mapCtrl.camera.zoom + 1)),
                                const SizedBox(height: 4),
                                _MapBtn(icon: Icons.remove, onTap: () => _mapCtrl.move(
                                  _mapCtrl.camera.center, _mapCtrl.camera.zoom - 1)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Hint / coords strip
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _pin != null
                          ? Row(children: [
                              Icon(Icons.check_circle_outline, size: 14, color: AppColors.ember),
                              const SizedBox(width: 6),
                              Text(
                                'Pinned · ${_pin!.latitude.toStringAsFixed(4)}, ${_pin!.longitude.toStringAsFixed(4)}',
                                style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(() => _pin = null),
                                child: Text('Clear', style: GoogleFonts.inter(fontSize: 11, color: AppColors.steel)),
                              ),
                            ])
                          : Text(
                              'Search an address above or tap the map to drop a pin',
                              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Description
              _Field(
                controller: _descCtrl,
                label: 'Description (optional)',
                hint: 'What to expect, what to bring, any notes…',
                maxLines: 5,
                maxLength: 2000,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} at $hour:$min';
  }
}

class _MapBtn extends StatelessWidget {
  const _MapBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.graphite.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.hairline),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
        ),
        child: Icon(icon, color: AppColors.cream, size: 18),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.onChanged,
    this.maxLines = 1,
    this.maxLength,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.glassCard(radius: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: maxLines,
        minLines: 1,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: GoogleFonts.inter(fontSize: 15, color: AppColors.cream),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(color: AppColors.steel, fontSize: 13),
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 15),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          counterText: '',
        ),
      ),
    );
  }
}
