import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/car/build_tab.dart';
import 'package:torqueden/widgets/car/mods_tab.dart';
import 'package:torqueden/widgets/car/posts_tab.dart';
import 'package:torqueden/widgets/car/specs_tab.dart';
import 'package:torqueden/widgets/follow_button.dart';

/// A car's profile page: photo + name, then tabs for Specs, Mods and the Build
/// log. Edits update the view in place; delete pops with `true` so the Garage
/// drops the car from its list.
class CarDetailScreen extends StatefulWidget {
  const CarDetailScreen({super.key, required this.car});

  final Car car;

  @override
  State<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends State<CarDetailScreen> {
  late Car _car;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _car = widget.car;
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<Car>(
      MaterialPageRoute(builder: (_) => AddCarScreen(car: _car)),
    );
    if (updated != null) {
      setState(() => _car = updated);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.graphite,
        title: Text(
          'Delete this car?',
          style: GoogleFonts.archivo(color: AppColors.cream, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This removes ${_car.title} from your garage for good. This can\'t be undone.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.steel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _delete();
    }
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await Supabase.instance.client.from('cars').delete().eq('id', _car.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete the car. Please try again.')),
        );
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final isOwn = uid != null && _car.ownerId != null && uid == _car.ownerId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_car.title),
        actions: [
          IconButton(
            onPressed: _deleting ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: _deleting ? null : _confirmDelete,
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: SafeArea(
        child: DefaultTabController(
          length: 4,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: _Header(car: _car, showFollow: !isOwn),
              ),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelColor: AppColors.cream,
                unselectedLabelColor: AppColors.steel,
                indicatorColor: AppColors.ember,
                indicatorWeight: 2.5,
                dividerColor: AppColors.hairline,
                tabs: [
                  Tab(text: 'Specs'),
                  Tab(text: 'Mods'),
                  Tab(text: 'Build'),
                  Tab(text: 'Posts'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SpecsTab(car: _car),
                    ModsTab(car: _car),
                    BuildTab(car: _car),
                    PostsTab(car: _car),
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

/// Hero block: the car's photo (or a fallback), with its name and — for cars
/// you don't own — a follow button.
class _Header extends StatelessWidget {
  const _Header({required this.car, this.showFollow = false});

  final Car car;
  final bool showFollow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: car.hasPhoto
                ? Image.network(
                    car.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _HeaderFallback(),
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const _HeaderFallback(),
                  )
                : const _HeaderFallback(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    car.title,
                    style: GoogleFonts.archivo(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    car.subtitle,
                    style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (showFollow) ...[
              const SizedBox(width: 12),
              FollowButton(carId: car.id),
            ],
          ],
        ),
      ],
    );
  }
}

class _HeaderFallback extends StatelessWidget {
  const _HeaderFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.graphiteRaised,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car_outlined, color: AppColors.steel, size: 64),
    );
  }
}
