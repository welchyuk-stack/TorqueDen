import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';

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

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Car>> _load() async {
    final uid = _client.auth.currentUser?.id;
    var q = _client.from('cars').select();
    if (uid != null) q = q.neq('owner_id', uid);
    final rows = await q.order('created_at', ascending: false);
    return rows.map(Car.fromMap).toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future;
  }

  List<Car> _filter(List<Car> cars) {
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

  Future<void> _openCar(Car car) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
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

                  final visible = _filter(cars);
                  if (visible.isEmpty) {
                    return Center(
                      child: Text(
                        'No matches',
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
                            car: visible[i],
                            onTap: () => _openCar(visible[i]),
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

/// A square photo tile with the car name tucked along the bottom.
class _GridTile extends StatelessWidget {
  const _GridTile({required this.car, this.onTap});

  final Car car;
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
