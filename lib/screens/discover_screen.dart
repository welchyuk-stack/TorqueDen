import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/screens/location_settings_screen.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/services/units_pref.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/settings_button.dart';

/// Discover tab — a dense Instagram-explore-style grid of everyone else's cars.
/// Tap a tile to open the full profile (and follow from there). A search box
/// filters by make / model / nickname.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  late Future<List<Car>> _future;
  String _query = '';

  // Location search ("near me") state. The centre comes from the location the
  // user set in Settings (SavedLocation), not a live GPS grab.
  bool _nearMe = false;
  double? _centerLat;
  double? _centerLng;
  String? _centerLabel;
  double _radiusKm = 50;

  static const double _minRadius = 5;
  static const double _maxRadius = 250; // cap the search at 250 km

  @override
  void initState() {
    super.initState();
    _future = _load();
    _applySavedLocation();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _query) setState(() => _query = q);
    });
  }

  void _applySavedLocation() {
    _centerLat = SavedLocation.lat;
    _centerLng = SavedLocation.lng;
    _centerLabel = SavedLocation.label;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Car>> _load() async {
    final uid = _client.auth.currentUser?.id;
    await Moderation.refreshBlocks();
    var q = _client.from('cars').select();
    if (uid != null) q = q.neq('owner_id', uid);
    final rows = await q.order('created_at', ascending: false);
    return rows
        .map(Car.fromMap)
        .where((c) => !Moderation.isBlocked(c.ownerId))
        .toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  List<Car> _textFilter(List<Car> cars) {
    if (_query.isEmpty) return cars;
    final needle = _query.toLowerCase();
    return cars.where((car) {
      final hay = [
        car.make,
        car.model,
        if (car.nickname != null) car.nickname!,
      ].join(' ').toLowerCase();
      return hay.contains(needle);
    }).toList();
  }

  /// Applies the text filter, then — when "near me" is on with a center set —
  /// keeps only cars inside the radius and sorts them nearest-first. Each entry
  /// carries its distance (km) so the tile can show the "X away" badge.
  List<_ScoredCar> _visibleCars(List<Car> cars) {
    final textMatched = _textFilter(cars);
    if (!_nearMe || _centerLat == null || _centerLng == null) {
      return [for (final c in textMatched) _ScoredCar(c, null)];
    }
    final scored = <_ScoredCar>[];
    for (final car in textMatched) {
      final d = car.distanceKmFrom(_centerLat!, _centerLng!);
      if (d != null && d <= _radiusKm) scored.add(_ScoredCar(car, d));
    }
    scored.sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
    return scored;
  }

  /// Turns "near me" on/off. Turning it on needs a saved location — if none is
  /// set, we send the user to the Location screen to set one first.
  Future<void> _toggleNearMe(bool on) async {
    if (!on) {
      setState(() => _nearMe = false);
      return;
    }
    if (!SavedLocation.isSet) {
      await _openLocationSettings();
      if (!SavedLocation.isSet) return; // user backed out without setting one
    }
    setState(() {
      _applySavedLocation();
      _nearMe = true;
    });
  }

  /// Opens the Location screen (where the user sets their location) and applies
  /// any change to the search centre on return.
  Future<void> _openLocationSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LocationSettingsScreen()),
    );
    if (!mounted || changed != true) return;
    setState(() {
      _applySavedLocation();
      if (!SavedLocation.isSet) _nearMe = false; // location was cleared
    });
  }

  Future<void> _openCar(Car car) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: const [SettingsButton()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                cursorColor: AppColors.ember,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.graphiteRaised,
                  hintText: 'Search cars, builds, people…',
                  prefixIcon: const Icon(Icons.search, color: AppColors.steel),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.ember, width: 1.5),
                  ),
                ),
              ),
            ),
            _LocationBar(
              nearMe: _nearMe,
              centerLabel: _centerLabel,
              radiusKm: _radiusKm,
              minRadius: _minRadius,
              maxRadius: _maxRadius,
              onToggle: _toggleNearMe,
              onChangeLocation: _openLocationSettings,
              onRadiusChanged: (v) => setState(() => _radiusKm = v),
            ),
            Expanded(
              child: FutureBuilder<List<Car>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.ember),
                    );
                  }
                  if (snapshot.hasError) {
                    return RefreshIndicator(
                      color: AppColors.ember,
                      backgroundColor: AppColors.graphite,
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.7,
                            child: EmptyState(
                              icon: Icons.error_outline,
                              title: 'Could not load Discover',
                              message: '${snapshot.error}',
                              action: FilledButton(
                                onPressed: _refresh,
                                child: const Text('Try again'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final cars = snapshot.data ?? const <Car>[];
                  if (cars.isEmpty) {
                    return const EmptyState(
                      icon: Icons.travel_explore_outlined,
                      title: 'No cars to discover yet',
                      message:
                          'When other people add cars, they\'ll show up here to follow.',
                    );
                  }

                  final visible = _visibleCars(cars);
                  if (visible.isEmpty) {
                    final msg = _nearMe
                        ? 'No cars within ${UnitsPref.radiusLabel(_radiusKm)}'
                        : 'No matches';
                    return Center(
                      child: Text(
                        msg,
                        style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.ember,
                    backgroundColor: AppColors.graphite,
                    onRefresh: _refresh,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // ~150px tiles → 2 columns on a phone, more on web.
                        var cols = (constraints.maxWidth / 150).floor();
                        if (cols < 2) cols = 2;
                        if (cols > 6) cols = 6;
                        return GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (_, i) => _GridTile(
                            car: visible[i].car,
                            distanceLabel: visible[i].distanceKm == null
                                ? null
                                : UnitsPref.distanceLabel(visible[i].distanceKm!),
                            onTap: () => _openCar(visible[i].car),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A car paired with its distance (km) from the search center, or null when
/// location filtering is off.
class _ScoredCar {
  const _ScoredCar(this.car, this.distanceKm);
  final Car car;
  final double? distanceKm;
}

/// A square photo tile with the car name tucked along the bottom, plus an
/// optional distance badge in the top corner when searching nearby.
class _GridTile extends StatelessWidget {
  const _GridTile({required this.car, this.distanceLabel, this.onTap});

  final Car car;
  final String? distanceLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (car.hasPhoto)
              Image.network(
                car.photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _TileFallback(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const _TileFallback(),
              )
            else
              const _TileFallback(),
            const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.transparent, Color(0xCC121418)],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 7,
              child: Text(
                car.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.archivo(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cream,
                ),
              ),
            ),
            if (distanceLabel != null)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 12, color: AppColors.ember),
                      const SizedBox(width: 3),
                      Text(
                        distanceLabel!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.cream,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TileFallback extends StatelessWidget {
  const _TileFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_outlined, color: AppColors.steel, size: 32),
    );
  }
}

/// The Marketplace-style location control: a "Near me" toggle chip and, when
/// active, the search-center label plus a radius slider.
class _LocationBar extends StatelessWidget {
  const _LocationBar({
    required this.nearMe,
    required this.centerLabel,
    required this.radiusKm,
    required this.minRadius,
    required this.maxRadius,
    required this.onToggle,
    required this.onChangeLocation,
    required this.onRadiusChanged,
  });

  final bool nearMe;
  final String? centerLabel;
  final double radiusKm;
  final double minRadius;
  final double maxRadius;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onChangeLocation;
  final ValueChanged<double> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilterChip(
                selected: nearMe,
                showCheckmark: false,
                avatar: Icon(
                  Icons.near_me,
                  size: 18,
                  color: nearMe ? AppColors.onEmber : AppColors.steel,
                ),
                label: const Text('Near me'),
                onSelected: onToggle == null
                    ? null
                    : (v) => onToggle!(v),
              ),
              const SizedBox(width: 10),
              if (nearMe)
                Expanded(
                  child: GestureDetector(
                    onTap: onChangeLocation,
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, size: 15, color: AppColors.ember),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            centerLabel ?? 'Your location',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '· Change',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ember,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (nearMe)
            Row(
              children: [
                Text(
                  'Within',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                ),
                Expanded(
                  child: Slider(
                    value: radiusKm.clamp(minRadius, maxRadius),
                    min: minRadius,
                    max: maxRadius,
                    divisions: ((maxRadius - minRadius) / 5).round(),
                    activeColor: AppColors.ember,
                    label: UnitsPref.radiusLabel(radiusKm),
                    onChanged: onRadiusChanged,
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    UnitsPref.radiusLabel(radiusKm),
                    textAlign: TextAlign.end,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.cream,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
