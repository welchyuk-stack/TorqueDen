import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/services/entitlements.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';
import 'package:torqueden/widgets/guest_nudge_sheet.dart';
import 'package:torqueden/widgets/upgrade_sheet.dart';

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
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    await Entitlements.refresh(); // so the car-limit gate reflects the tier
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
    // Free tier is capped to one car; Premium is unlimited.
    final limit = Entitlements.carLimit;
    if (limit != null) {
      final cars = await _carsFuture;
      if (cars.length >= limit && mounted) {
        await showUpgradeSheet(
          context,
          title: 'You\'ve reached the free garage limit',
          message:
              'Free members can add one car. Upgrade to Premium to keep '
              'unlimited cars in your garage.',
        );
        return;
      }
    }
    if (!mounted) return;
    final added = await Navigator.of(
      context,
    ).push<Car>(MaterialPageRoute(builder: (_) => const AddCarScreen()));
    if (added != null) {
      await _refresh();
    }
  }

  Future<void> _openCar(Car car) async {
    // The detail screen handles its own edits in place; we refresh on return so
    // any edit or delete is reflected in the list.
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(left: 6),
          child: Text('Garage', style: TextStyle(fontSize: 22)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: _openAddCar,
              icon: Icon(Icons.add, size: 32, color: AppColors.cream),
              tooltip: 'Add a car',
            ),
          ),
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
            final isLoggedIn = _client.auth.currentUser != null;
            if (cars.isEmpty) {
              return EmptyState(
                icon: Icons.garage_outlined,
                title: isLoggedIn ? 'Your garage is empty' : 'Your garage',
                message: isLoggedIn
                    ? 'Add your first build to get started.'
                    : 'Create an account to add your car and start your build log.',
                action: FilledButton.icon(
                  onPressed: isLoggedIn ? _openAddCar : () => showGuestNudge(context, reason: 'add your car'),
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(isLoggedIn ? 'Add your first build' : 'Get started'),
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
                itemBuilder: (_, i) =>
                    _CarCard(car: cars[i], onTap: () => _openCar(cars[i])),
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
    return DecoratedBox(
      decoration: AppDecorations.glassCard(radius: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Photo — upper portion of the card.
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (car.hasPhoto)
                      Image.network(
                        car.thumbnailUrl()!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _CardFallback(),
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : const _CardFallback(),
                      )
                    else
                      const _CardFallback(),
                  ],
                ),
              ),
              // Top-Trumps stat plate — solid panel below the photo.
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
                          ? AppColors.cream.withValues(alpha: 0.10)
                          : const Color(0x2015171B),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      car.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      car.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
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
      child: Icon(
        Icons.directions_car_outlined,
        color: AppColors.steel,
        size: 56,
      ),
    );
  }
}
