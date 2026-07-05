import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/screens/location_settings_screen.dart';
import 'package:torqueden/screens/partner/partners_view.dart';
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
  late Future<List<String>> _suggestionsFuture;
  String _query = '';
  int _tab = 0; // 0 = Cars, 1 = Partners

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
    _suggestionsFuture = _loadSuggestions();
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)));
  }

  /// Phase-1 search suggestions: frequency-ranked keywords drawn from the cars
  /// you follow and your own garage — their makes/models/chassis codes and the
  /// mod categories logged against them. No history logging or ML; purely
  /// derived from data we already have. Returns [] when there's nothing to go on
  /// (e.g. a brand-new user), which hides the bar.
  Future<List<String>> _loadSuggestions() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      // Cars you follow + your own garage.
      final followRows = await _client
          .from('follows')
          .select('car_id')
          .eq('follower_id', uid);
      final followedIds = [for (final r in followRows) r['car_id'] as String];

      final carRows = <Map<String, dynamic>>[];
      if (followedIds.isNotEmpty) {
        carRows.addAll(
          List<Map<String, dynamic>>.from(
            await _client
                .from('cars')
                .select('id, make, model, chassis_model')
                .inFilter('id', followedIds),
          ),
        );
      }
      carRows.addAll(
        List<Map<String, dynamic>>.from(
          await _client
              .from('cars')
              .select('id, make, model, chassis_model')
              .eq('owner_id', uid),
        ),
      );

      // Mod categories logged against those cars.
      final carIds = {for (final c in carRows) c['id'] as String}.toList();
      final catRows = carIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _client
                  .from('build_entries')
                  .select('category')
                  .inFilter('car_id', carIds),
            );

      // Tally, case-insensitively, keeping the first-seen display spelling.
      final counts = <String, int>{};
      final display = <String, String>{};
      void bump(String? raw, int weight) {
        final t = raw?.trim() ?? '';
        if (t.isEmpty) return;
        final key = t.toLowerCase();
        counts[key] = (counts[key] ?? 0) + weight;
        display.putIfAbsent(key, () => t);
      }

      for (final c in carRows) {
        bump(c['make'] as String?, 2); // makes/models weighted above chassis
        bump(c['model'] as String?, 2);
        bump(c['chassis_model'] as String?, 1);
      }
      for (final r in catRows) {
        bump(r['category'] as String?, 1);
      }

      final keys = counts.keys.toList()
        ..sort((a, b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
      return [for (final k in keys.take(8)) display[k]!];
    } catch (_) {
      return const []; // suggestions are best-effort — never block Discover
    }
  }

  /// Run a suggested keyword as a search.
  void _applySuggestion(String keyword) {
    _searchController.text = keyword;
    _searchController.selection = TextSelection.collapsed(
      offset: keyword.length,
    );
    setState(() => _query = keyword);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Text('Discover', style: TextStyle(fontSize: 22)),
        ),
        actions: [
          _Segment(
            label: 'Cars',
            selected: _tab == 0,
            onTap: () => setState(() => _tab = 0),
          ),
          const SizedBox(width: 6),
          _Segment(
            label: 'Partners',
            selected: _tab == 1,
            onTap: () => setState(() => _tab = 1),
          ),
          const SizedBox(width: 4),
          const SettingsButton(),
        ],
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
                  hintText: _tab == 0
                      ? 'Search cars, builds…'
                      : 'Search partners…',
                  prefixIcon: const Icon(Icons.search, color: AppColors.steel),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.ember,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            if (_tab == 0)
              _SuggestionsBar(
                future: _suggestionsFuture,
                onTap: _applySuggestion,
              ),
            if (_tab == 0)
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
              child: _tab == 1
                  ? PartnersView(query: _query)
                  : FutureBuilder<List<Car>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.ember,
                            ),
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
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.7,
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
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: AppColors.textMuted,
                              ),
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
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  16,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
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
                                      : UnitsPref.distanceLabel(
                                          visible[i].distanceKm!,
                                        ),
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

/// A pill toggle for the Cars / Partners tabs.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.cream : AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.cream : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.carbon : AppColors.steel,
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of suggested search keywords (Phase 1), sitting in the slot
/// freed by moving the Cars/Partners toggle up to the app bar. Hidden while the
/// suggestions load or when there are none.
class _SuggestionsBar extends StatelessWidget {
  const _SuggestionsBar({required this.future, required this.onTap});

  final Future<List<String>> future;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: future,
      builder: (context, snapshot) {
        final suggestions = snapshot.data ?? const <String>[];
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
          child: SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: suggestions.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Center(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: AppColors.steel,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'For you',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  );
                }
                final keyword = suggestions[i - 1];
                return _SuggestionChip(
                  label: keyword,
                  onTap: () => onTap(keyword),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.cream,
          ),
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
      child: Container(
        // A very thin ember outline over the tile edge.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ember, width: 0.5),
        ),
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
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Color(0xCC121418),
                    ],
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 12,
                          color: AppColors.ember,
                        ),
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
      child: const Icon(
        Icons.directions_car_outlined,
        color: AppColors.steel,
        size: 32,
      ),
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
                onSelected: onToggle == null ? null : (v) => onToggle!(v),
              ),
              const SizedBox(width: 10),
              if (nearMe)
                Expanded(
                  child: GestureDetector(
                    onTap: onChangeLocation,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 15,
                          color: AppColors.ember,
                        ),
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
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
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
