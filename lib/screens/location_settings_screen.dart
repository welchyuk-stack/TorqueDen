import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/services/location_service.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/theme.dart';

/// Set the location used as the centre of Discover's "near me" search — either
/// the device's current location or a place searched by name. Pops `true` if
/// the saved location changed.
class LocationSettingsScreen extends StatefulWidget {
  const LocationSettingsScreen({super.key});

  @override
  State<LocationSettingsScreen> createState() => _LocationSettingsScreenState();
}

class _LocationSettingsScreenState extends State<LocationSettingsScreen> {
  final _search = TextEditingController();
  bool _busy = false;
  bool _changed = false;
  String? _label = SavedLocation.label;
  bool _isSet = SavedLocation.isSet;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _useCurrent() async {
    setState(() => _busy = true);
    try {
      final place = await LocationService.currentPlace();
      await SavedLocation.save(place.latitude, place.longitude, place.label);
      if (!mounted) return;
      setState(() {
        _label = place.label;
        _isSet = true;
        _changed = true;
        _busy = false;
      });
      _snack('Location set${place.label != null ? ' to ${place.label}' : ''}.');
    } on LocationException catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not get your location: $e');
    }
  }

  Future<void> _searchPlace() async {
    final q = _search.text.trim();
    if (q.isEmpty) return _snack('Enter a place to search for.');
    setState(() => _busy = true);
    try {
      final place = await LocationService.search(q);
      await SavedLocation.save(place.latitude, place.longitude, place.label);
      if (!mounted) return;
      setState(() {
        _label = place.label;
        _isSet = true;
        _changed = true;
        _busy = false;
      });
      _search.clear();
      FocusScope.of(context).unfocus();
      _snack('Location set${place.label != null ? ' to ${place.label}' : ''}.');
    } on LocationException catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not find that place: $e');
    }
  }

  Future<void> _clear() async {
    await SavedLocation.clear();
    if (!mounted) return;
    setState(() {
      _label = null;
      _isSet = false;
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Location')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Set the location used to find cars near you in Discover. Your exact '
                'position is never stored — it\'s rounded to a ~1 km area.',
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 20),
              // Current saved location
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.graphite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    Icon(_isSet ? Icons.location_on : Icons.location_off_outlined,
                        color: _isSet ? AppColors.ember : AppColors.steel),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your location',
                              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            _isSet ? (_label ?? 'Set (unnamed area)') : 'Not set',
                            style: GoogleFonts.inter(color: AppColors.cream, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (_isSet)
                      TextButton(
                        onPressed: _busy ? null : _clear,
                        child: Text('Clear', style: GoogleFonts.inter(color: AppColors.steel, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _useCurrent,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onEmber))
                    : const Icon(Icons.my_location, size: 20),
                label: const Text('Use my current location'),
              ),
              const SizedBox(height: 24),
              Text('OR SEARCH FOR A PLACE',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _busy ? null : _searchPlace(),
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Town, city or postcode',
                  prefixIcon: const Icon(Icons.search, color: AppColors.steel),
                  suffixIcon: TextButton(
                    onPressed: _busy ? null : _searchPlace,
                    child: Text('Search', style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
