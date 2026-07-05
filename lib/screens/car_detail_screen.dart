import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/car/build_tab.dart';
import 'package:torqueden/widgets/car/posts_tab.dart';
import 'package:torqueden/widgets/car/specs_tab.dart';
import 'package:torqueden/widgets/follow_button.dart';

/// A car's profile page: photo + name, then tabs for Specs, the Build log
/// (dated updates and mods) and Posts. Edits update the view in place; delete
/// pops with `true` so the Garage drops the car from its list.
class CarDetailScreen extends StatefulWidget {
  const CarDetailScreen({super.key, required this.car});

  final Car car;

  @override
  State<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends State<CarDetailScreen>
    with SingleTickerProviderStateMixin {
  late Car _car;
  bool _deleting = false;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _car = widget.car;
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {}); // keep the icon rail's highlight in sync
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _Header(
                car: _car,
                showFollow: !isOwn,
                tabIndex: _tabs.index,
                onTabTap: (i) => _tabs.animateTo(i),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  SpecsTab(car: _car),
                  BuildTab(car: _car),
                  PostsTab(car: _car),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hero block: the car's photo (or a fallback), with its name and — for cars
/// you don't own — a follow button.
class _Header extends StatelessWidget {
  const _Header({
    required this.car,
    required this.tabIndex,
    required this.onTabTap,
    this.showFollow = false,
  });

  final Car car;
  final bool showFollow;
  final int tabIndex;
  final ValueChanged<int> onTabTap;

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
        const SizedBox(height: 10),
        // Nickname on the left; the three tab icons sit horizontally under the
        // right of the photo.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                car.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.archivo(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cream,
                ),
              ),
            ),
            if (showFollow) ...[
              const SizedBox(width: 12),
              FollowButton(carId: car.id),
            ],
            const SizedBox(width: 12),
            _TabRail(index: tabIndex, onTap: onTabTap),
          ],
        ),
      ],
    );
  }
}

/// Horizontal tab selector: three circular icon buttons that sit under the
/// right of the photo. Spanner = Specs, car outline = Build, grid = Posts.
class _TabRail extends StatelessWidget {
  const _TabRail({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.build_outlined, label: 'Specs'), // spanner
    (icon: Icons.directions_car_outlined, label: 'Build'), // car outline
    (icon: Icons.grid_view_outlined, label: 'Posts'), // grid
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          _RailIcon(
            icon: _items[i].icon,
            label: _items[i].label,
            selected: i == index,
            onTap: () => onTap(i),
          ),
        ],
      ],
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppColors.ember : AppColors.graphite,
            border: Border.all(
              color: selected ? AppColors.ember : AppColors.hairline,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: selected ? AppColors.onEmber : AppColors.steel,
          ),
        ),
      ),
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
