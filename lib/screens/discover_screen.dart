import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/ads/ad_ids.dart';
import 'package:torqueden/ads/consent_service.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/post_media.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/screens/location_settings_screen.dart';
import 'package:torqueden/screens/post_viewer_screen.dart';
import 'package:torqueden/services/moderation.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/services/units_pref.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/models/challenge.dart';
import 'package:torqueden/screens/challenge_screen.dart';
import 'package:torqueden/services/challenge_service.dart';

/// Discover tab — a dense Instagram-explore-style grid of everyone else's cars.
/// Tap a tile to open the full profile (and follow from there), or a post tile
/// to open that post. A plain-text search matches both cars (make / model /
/// nickname / chassis / tags) and posts (title / body / tags), merged into one
/// grid. A "#tag" search returns posts only.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.initialQuery});

  /// Pre-fill the search box, e.g. when navigating from a hashtag chip.
  final String? initialQuery;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  late Future<List<Car>> _future;
  String _query = '';
  List<String> _trendingTags = [];
  // carId → all tags across that car's posts
  Map<String, List<String>> _carTags = {};
  // All public posts, loaded alongside cars so text search can match both.
  List<_PostHit> _posts = [];

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
    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
      _query = widget.initialQuery!;
    }
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
    await Moderation.refreshBlocks();
    final rows = await _client
        .from('cars')
        .select('*, follower_count')
        .order('created_at', ascending: false)
        .limit(200);
    final cars = rows
        .map(Car.fromMap)
        .where((c) => !Moderation.isBlocked(c.ownerId))
        .toList();

    // Load tags from posts for the cars we just fetched.
    final carIds = cars.map((c) => c.id).toList();
    if (carIds.isNotEmpty) {
      final tagRows = await _client
          .from('build_entries')
          .select('car_id, tags')
          .inFilter('car_id', carIds)
          .not('tags', 'eq', '{}');
      final map = <String, List<String>>{};
      for (final r in tagRows) {
        final id = r['car_id'] as String;
        final tags = (r['tags'] as List<dynamic>).cast<String>();
        map.update(id, (existing) => [...existing, ...tags],
            ifAbsent: () => [...tags]);
      }
      _carTags = map;
    } else {
      _carTags = {};
    }

    await _loadPosts();
    _computeTrending();
    return cars;
  }

  /// Loads public posts (build entries) with their car and first photo, so
  /// search can match post title/body/tags alongside car fields.
  Future<void> _loadPosts() async {
    final rows = await _client
        .from('build_entries')
        .select(
          'id, title, body, tags, '
          'car:cars(id, owner_id, make, model, nickname, chassis_model, photo_url), '
          'post_media!inner(id, url, kind, position)',
        )
        .eq('silent', false)
        .order('created_at', ascending: false)
        .limit(200);

    final posts = <_PostHit>[];
    for (final row in rows) {
      final carMap = row['car'] as Map<String, dynamic>?;
      if (carMap == null) continue;
      if (Moderation.isBlocked(carMap['owner_id'] as String?)) continue;

      final mediaRows = ((row['post_media'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .toList()
        ..sort(
          (a, b) =>
              ((a['position'] as int?) ?? 0).compareTo((b['position'] as int?) ?? 0),
        );

      posts.add(
        _PostHit(
          id: row['id'] as String,
          title: row['title'] as String? ?? '',
          body: row['body'] as String?,
          tags: (row['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
          car: Car.fromMap(carMap),
          media: mediaRows.isEmpty
              ? null
              : PostMedia(
                  id: mediaRows.first['id'] as String,
                  url: mediaRows.first['url'] as String,
                  kind: (mediaRows.first['kind'] as String?) ?? 'image',
                  position: (mediaRows.first['position'] as int?) ?? 0,
                  buildEntryId: row['id'] as String,
                  caption: row['title'] as String?,
                  tags: (row['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
                ),
        ),
      );
    }
    _posts = posts;
  }

  void _computeTrending() {
    final counts = <String, int>{};
    for (final tags in _carTags.values) {
      for (final tag in tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (mounted) {
      setState(() {
        _trendingTags = sorted.take(5).map((e) => e.key).toList();
      });
    }
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  /// A "#tag" query searches posts only — cars never match a hashtag search.
  bool get _isHashtagQuery => _query.trim().startsWith('#');

  /// Search text with any leading # stripped, so "#jdm" and "jdm" match the
  /// same posts/tags.
  String get _needle =>
      _query.toLowerCase().replaceFirst(RegExp(r'^#'), '').trim();

  List<Car> _textFilter(List<Car> cars) {
    if (_query.isEmpty) return cars;
    if (_isHashtagQuery) return const []; // hashtag searches return posts only
    final needle = _needle;
    return cars.where((car) {
      final hay = [
        car.make,
        car.model,
        if (car.nickname != null) car.nickname!,
        if (car.chassisModel != null) car.chassisModel!,
        ...(_carTags[car.id] ?? const []),
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

  /// Posts matching the current query by title, body, tags, or the owning
  /// car's make/model/nickname/chassis. Empty when there's no query — posts
  /// only ever show up as search results, not in the default browse grid.
  List<_PostHit> _filteredPosts() {
    if (_query.isEmpty) return const [];
    final needle = _needle;
    return _posts.where((p) {
      final hay = [
        p.title,
        if (p.body != null) p.body!,
        ...p.tags,
        p.car.make,
        p.car.model,
        if (p.car.nickname != null) p.car.nickname!,
        if (p.car.chassisModel != null) p.car.chassisModel!,
      ].join(' ').toLowerCase();
      return hay.contains(needle);
    }).toList();
  }

  /// The merged grid contents for the current query:
  /// - Hashtag search ("#tag") → posts only.
  /// - Plain text search → matching cars + matching posts together.
  /// - No search (browsing) → cars only, exactly as before.
  /// "Near me" only ever filters cars (posts have no location of their own),
  /// so posts are left out while it's on to avoid mixing filtered/unfiltered
  /// results in the same grid.
  List<_DiscoverItem> _visibleItems(List<Car> cars) {
    if (_isHashtagQuery) {
      return [for (final p in _filteredPosts()) _DiscoverItem.forPost(p)];
    }
    final items = <_DiscoverItem>[];
    var carCount = 0;
    for (final sc in _visibleCars(cars)) {
      items.add(_DiscoverItem.forCar(sc.car, sc.distanceKm));
      carCount++;
      // One ad tile after every 10th car, same size as the car tiles.
      if (carCount % 10 == 0) items.add(const _DiscoverItem.forAd());
    }
    if (_query.isNotEmpty && !_nearMe) {
      items.addAll([for (final p in _filteredPosts()) _DiscoverItem.forPost(p)]);
    }
    return items;
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

  Future<void> _openPost(_PostHit post) async {
    final media = post.media;
    if (media == null) return; // no photo/video to show — nothing to open
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PostViewerScreen(media: media, car: post.car),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.initialQuery != null
          ? AppColors.carbon
          : Colors.transparent,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Text('Discover', style: TextStyle(fontSize: 22)),
        ),
        actions: const [],
      ),
      body: FutureBuilder<List<Car>>(
          future: _future,
          builder: (context, snapshot) {
            final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
            // Build the header slivers regardless of load state.
            final searchSliver = SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.inter(color: AppColors.cream, fontSize: 15),
                  cursorColor: AppColors.ember,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.graphiteRaised,
                    hintText: 'Search make, model, chassis, tags',
                    prefixIcon: Icon(Icons.search, color: AppColors.steel),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.ember, width: 1.5),
                    ),
                  ),
                ),
              ),
            );

            final trendingSliver = _trendingTags.isNotEmpty
                ? SliverToBoxAdapter(
                    child: _TrendingBar(
                      tags: _trendingTags,
                      activeTag: _query.replaceFirst(RegExp(r'^#'), ''),
                      onTap: (tag) {
                        final current = _searchController.text
                            .trim()
                            .replaceFirst(RegExp(r'^#'), '');
                        if (current == tag) {
                          _searchController.clear();
                        } else {
                          _searchController.text = '#$tag';
                          _searchController.selection = TextSelection.collapsed(
                            offset: _searchController.text.length,
                          );
                        }
                      },
                    ),
                  )
                : null;

            final locationSliver = SliverToBoxAdapter(
              child: _LocationBar(
                nearMe: _nearMe,
                centerLabel: _centerLabel,
                radiusKm: _radiusKm,
                minRadius: _minRadius,
                maxRadius: _maxRadius,
                onToggle: _toggleNearMe,
                onChangeLocation: _openLocationSettings,
                onRadiusChanged: (v) => setState(() => _radiusKm = v),
                onShowdownTap: () async {
                  final svc = ChallengeService.instance;
                  final c = await svc.fetchActive() ??
                      (await svc.fetchAll()).firstOrNull;
                  if (c != null && mounted) {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChallengeScreen(challenge: c),
                    ));
                  }
                },
              ),
            );

            // Loading state
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CustomScrollView(slivers: [
                searchSliver,
                if (trendingSliver != null) trendingSliver,
                locationSliver,
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: AppColors.ember)),
                ),
              ]);
            }

            // Error state
            if (snapshot.hasError) {
              return RefreshIndicator(
                color: AppColors.ember,
                backgroundColor: AppColors.graphite,
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    searchSliver,
                    if (trendingSliver != null) trendingSliver,
                    locationSliver,
                    SliverFillRemaining(
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
              return RefreshIndicator(
                color: AppColors.ember,
                backgroundColor: AppColors.graphite,
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    searchSliver,
                    if (trendingSliver != null) trendingSliver,
                    locationSliver,
                    const SliverFillRemaining(
                      child: EmptyState(
                        icon: Icons.travel_explore_outlined,
                        title: 'No cars to discover yet',
                        message: 'When other people add cars, they\'ll show up here to follow.',
                      ),
                    ),
                  ],
                ),
              );
            }

            final items = _visibleItems(cars);
            if (items.isEmpty) {
              final msg = _isHashtagQuery
                  ? 'No posts for #$_needle'
                  : (_nearMe
                      ? 'No cars within ${UnitsPref.radiusLabel(_radiusKm)}'
                      : 'No matches');
              return RefreshIndicator(
                color: AppColors.ember,
                backgroundColor: AppColors.graphite,
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    searchSliver,
                    if (trendingSliver != null) trendingSliver,
                    locationSliver,
                    SliverFillRemaining(
                      child: Center(
                        child: EmptyState(
                          icon: Icons.search_off_outlined,
                          title: 'No results',
                          message: msg,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              color: AppColors.ember,
              backgroundColor: AppColors.graphite,
              onRefresh: _refresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  var cols = (constraints.maxWidth / 150).floor();
                  if (cols < 2) cols = 2;
                  if (cols > 6) cols = 6;
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      searchSliver,
                      if (trendingSliver != null) trendingSliver,
                      locationSliver,
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottomInset),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) {
                              final item = items[i];
                              if (item.isAd) return const _DiscoverAdTile();
                              if (item.isPost) {
                                return _PostGridTile(
                                  post: item.post!,
                                  onTap: () => _openPost(item.post!),
                                );
                              }
                              return _GridTile(
                                car: item.car!,
                                distanceLabel: item.distanceKm == null
                                    ? null
                                    : UnitsPref.distanceLabel(item.distanceKm!),
                                onTap: () => _openCar(item.car!),
                              );
                            },
                            childCount: items.length,
                          ),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
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

/// A post (build entry) search result — its own text plus the car it belongs
/// to, so search can match either.
class _PostHit {
  const _PostHit({
    required this.id,
    required this.title,
    this.body,
    required this.tags,
    required this.car,
    this.media,
  });

  final String id;
  final String title;
  final String? body;
  final List<String> tags;
  final Car car;

  /// The post's first photo/video, if it has one — what search result tiles
  /// show and what opens in the post viewer.
  final PostMedia? media;
}

/// One entry in the merged Discover grid — a car, a post, or an ad slot. At
/// most one of [car] / [post] is set; neither set means it's an ad tile.
class _DiscoverItem {
  const _DiscoverItem.forCar(this.car, this.distanceKm)
      : post = null,
        isAd = false;
  const _DiscoverItem.forPost(this.post)
      : car = null,
        distanceKm = null,
        isAd = false;
  const _DiscoverItem.forAd()
      : car = null,
        post = null,
        distanceKm = null,
        isAd = true;

  final Car? car;
  final _PostHit? post;
  final double? distanceKm;
  final bool isAd;

  bool get isPost => post != null;
}

/// A square photo tile with the car name tucked along the bottom, plus an
/// optional distance badge in the top corner when searching nearby.
class _GridTile extends StatelessWidget {
  const _GridTile({required this.car, this.distanceLabel, this.onTap});

  final Car car;
  final String? distanceLabel;
  final VoidCallback? onTap;

  /// Metadata under the tile name — chassis code when known (the detail car
  /// people actually search by), else year/make/model. Skipped if it would
  /// just repeat the title.
  static String? _subtitle(Car car) {
    final chassis = car.chassisModel?.trim();
    final line = (chassis != null && chassis.isNotEmpty)
        ? '$chassis · ${car.make}'
        : car.subtitle;
    return line == car.title ? null : line;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Glass rim outline over the tile edge.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: AppDecorations.glassRimBorder(),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The photo — a fixed border along its lower edge hands off to
              // the caption plate below, rather than the name floating over
              // a gradient fade.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (car.hasPhoto)
                      Image.network(
                        car.thumbnailUrl()!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _TileFallback(),
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : const _TileFallback(),
                      )
                    else
                      const _TileFallback(),
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
              // Caption plate — a Top-Trumps-style stat bar: a fixed liquid-
              // glass panel below the photo, not laid over it. A hairline rim
              // along its top edge is the "fixed border" separating photo
              // from plate; the rim-light border on the whole tile continues
              // around its outer edge.
              Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                decoration: BoxDecoration(
                  gradient: AppColors.isDark
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xD925292F), Color(0xF01A1E24)],
                        )
                      : null,
                  color: AppColors.isDark ? null : const Color(0xFFEEEEEE),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.isDark
                          ? AppColors.cream.withValues(alpha: 0.14)
                          : const Color(0x2915171B),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      car.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    if (_subtitle(car) != null)
                      Text(
                        _subtitle(car)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
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
      child: Icon(
        Icons.directions_car_outlined,
        color: AppColors.steel,
        size: 32,
      ),
    );
  }
}

/// A native-sized AdMob banner squeezed into a grid cell the same size as the
/// car/post tiles. The ad's own aspect ratio (300×250) doesn't match the
/// grid's square cells, so it's scaled with [FittedBox] to fill the tile's
/// width — same technique as [FeedAdSlot], just square-shaped chrome instead
/// of a full-width card. Renders nothing until an ad actually loads.
class _DiscoverAdTile extends StatefulWidget {
  const _DiscoverAdTile();

  @override
  State<_DiscoverAdTile> createState() => _DiscoverAdTileState();
}

class _DiscoverAdTileState extends State<_DiscoverAdTile> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadWhenConsented();
  }

  Future<void> _loadWhenConsented() async {
    await ConsentService.instance.ensureReady();
    if (!mounted || !ConsentService.instance.canRequestAds) return;
    _ad = BannerAd(
      adUnitId: AdIds.discoverGridBanner,
      size: AdSize.mediumRectangle, // 300x250
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() { _ad = null; _loaded = false; });
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: AppDecorations.glassRimBorder(),
      ),
      decoration: BoxDecoration(
        color: AppColors.graphiteRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: AdSize.mediumRectangle.width.toDouble(),
                height: AdSize.mediumRectangle.height.toDouble(),
                child: AdWidget(ad: _ad!),
              ),
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Ad',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A search-result tile for a post — its first photo/video, with the post
/// title and the owning car tucked along the bottom, same layout as
/// [_GridTile] so cars and posts sit together in one consistent grid.
class _PostGridTile extends StatelessWidget {
  const _PostGridTile({required this.post, this.onTap});

  final _PostHit post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final media = post.media;
    final title = post.title.trim().isNotEmpty ? post.title.trim() : post.car.title;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: AppDecorations.glassRimBorder(),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (media != null)
                      Image.network(
                        media.thumbnailUrl(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _TileFallback(),
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : const _TileFallback(),
                      )
                    else
                      const _TileFallback(),
                    if (media?.isVideo ?? false)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                decoration: BoxDecoration(
                  gradient: AppColors.isDark
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xD925292F), Color(0xF01A1E24)],
                        )
                      : null,
                  color: AppColors.isDark ? null : const Color(0xFFEEEEEE),
                  border: Border(
                    top: BorderSide(
                      color: AppColors.isDark
                          ? AppColors.cream.withValues(alpha: 0.14)
                          : const Color(0x2915171B),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    Text(
                      post.car.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of the top 5 trending hashtag chips.
class _TrendingBar extends StatelessWidget {
  const _TrendingBar({
    required this.tags,
    required this.activeTag,
    required this.onTap,
  });

  final List<String> tags;
  final String activeTag;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tag = tags[i];
          final active = activeTag == tag;
          return GestureDetector(
            onTap: () => onTap(tag),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.ember.withValues(alpha: 0.15)
                    : AppColors.graphiteRaised,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? AppColors.ember : AppColors.hairline,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Text(
                '#$tag',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: active ? AppColors.ember : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
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
    required this.onShowdownTap,
  });

  final bool nearMe;
  final String? centerLabel;
  final double radiusKm;
  final double minRadius;
  final double maxRadius;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onChangeLocation;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onShowdownTap;

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
              if (!nearMe) const Spacer(),
              _ShowdownChip(onTap: onShowdownTap),
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

class _ShowdownChip extends StatelessWidget {
  const _ShowdownChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Challenge?>(
      future: ChallengeService.instance.fetchActive().then(
        (active) async => active ??
            (await ChallengeService.instance.fetchAll()).firstOrNull,
      ),
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.isDark ? const Color(0xFF111111) : AppColors.graphiteRaised,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.ember.withValues(alpha: 0.5), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THE SHOT',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.cream,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: AppColors.ember),
              ],
            ),
          ),
        );
      },
    );
  }
}
