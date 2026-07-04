import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/settings_button.dart';

/// Garage tab — the current user's cars, loaded live from Supabase.
class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Car>> _carsFuture;

  @override
  void initState() {
    super.initState();
    _carsFuture = _loadCars();
  }

  Future<List<Car>> _loadCars() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('cars')
        .select()
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
    return rows.map(Car.fromMap).toList();
  }

  Future<void> _refresh() async {
    // Use a block body, not an arrow: `() => _carsFuture = _loadCars()` returns
    // the Future, and setState() throws if its callback returns a Future.
    final future = _loadCars();
    setState(() {
      _carsFuture = future;
    });
    await future;
  }

  Future<void> _openAddCar() async {
    final added = await Navigator.of(context).push<Car>(
      MaterialPageRoute(builder: (_) => const AddCarScreen()),
    );
    if (added != null) {
      await _refresh();
    }
  }

  Future<void> _openCar(Car car) async {
    // The detail screen handles its own edits in place; we refresh on return so
    // any edit or delete is reflected in the list.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Garage'),
        actions: [
          IconButton(
            onPressed: _openAddCar,
            icon: const Icon(Icons.add),
            tooltip: 'Add a car',
          ),
          const SettingsButton(),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<Car>>(
          future: _carsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.ember),
              );
            }
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load your garage',
                message: '${snapshot.error}',
                action: FilledButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              );
            }
            final cars = snapshot.data ?? const [];
            if (cars.isEmpty) {
              return EmptyState(
                icon: Icons.garage_outlined,
                title: 'Your garage is empty',
                message: 'Add your first build to get started.',
                action: FilledButton.icon(
                  onPressed: _openAddCar,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add your first build'),
                ),
              );
            }
            return RefreshIndicator(
              color: AppColors.ember,
              backgroundColor: AppColors.graphite,
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: cars.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _CarCard(
                  car: cars[i],
                  onTap: () => _openCar(cars[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car, this.onTap});

  final Car car;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.graphite,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background: the car's photo, or a fallback when it has none.
              if (car.hasPhoto)
                Image.network(
                  car.photoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _CardFallback(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const _CardFallback(),
                )
              else
                const _CardFallback(),

              // Dark gradient so the text stays readable over any photo.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.transparent, Color(0xE6121418)],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),

              // Title + subtitle, bottom-left.
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      car.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.archivo(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      car.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.cream),
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

/// Shown when a car has no photo (or the photo fails to load): the brand-dark
/// well with a centered car icon.
class _CardFallback extends StatelessWidget {
  const _CardFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_outlined, color: AppColors.steel, size: 56),
    );
  }
}
