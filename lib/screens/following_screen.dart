import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/car_detail_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// Lists all the cars the signed-in user is currently following.
class FollowingScreen extends StatefulWidget {
  const FollowingScreen({super.key});

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Car>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Car>> _load() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('follows')
        .select('car:car_id(*, follower_count)')
        .eq('follower_id', uid)
        .order('created_at', ascending: false);
    return rows
        .map((r) => Car.fromMap(r['car'] as Map<String, dynamic>))
        .toList();
  }

  Future<void> _unfollow(Car car) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', uid)
        .eq('car_id', car.id);
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _open(Car car) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CarDetailScreen(car: car)),
    );
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Following')),
      body: FutureBuilder<List<Car>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.ember));
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: AppColors.steel, size: 40),
                  const SizedBox(height: 12),
                  Text('Could not load.',
                      style: GoogleFonts.inter(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          final cars = snap.data ?? const [];
          if (cars.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border,
              title: 'Not following anyone yet',
              message: 'Tap Follow on a build to keep up with its updates.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: cars.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: AppColors.hairline),
              itemBuilder: (context, i) => _FollowRow(
                car: cars[i],
                onTap: () => _open(cars[i]),
                onUnfollow: () => _unfollow(cars[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FollowRow extends StatelessWidget {
  const _FollowRow({
    required this.car,
    required this.onTap,
    required this.onUnfollow,
  });

  final Car car;
  final VoidCallback onTap;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      title: Text(
        car.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.cream,
        ),
      ),
      subtitle: Text(
        car.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: TextButton(
        onPressed: onUnfollow,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(64, 44),
        ),
        child: Text(
          'Unfollow',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
