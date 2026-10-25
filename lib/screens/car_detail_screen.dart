import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/screens/add_car_screen.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/models/challenge.dart';
import 'package:torqueden/services/challenge_service.dart';
import 'package:torqueden/widgets/car/build_tab.dart';
import 'package:torqueden/widgets/car/posts_tab.dart';
import 'package:torqueden/widgets/car/specs_tab.dart';
import 'package:torqueden/widgets/follow_button.dart';
import 'package:torqueden/widgets/share_sheet.dart';

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
          style: GoogleFonts.spaceGrotesk(color: AppColors.cream, fontWeight: FontWeight.w700),
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
            onPressed: () => showShareSheet(context, car: _car),
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Share',
          ),
          if (isOwn) ...[
          IconButton(
            onPressed: _deleting ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
          ),
          // Delete lives behind the overflow menu (plus its confirm dialog) —
          // an always-visible red trash next to Edit is one mis-tap from
          // losing a whole car.
          PopupMenuButton<String>(
            enabled: !_deleting,
            icon: Icon(Icons.more_vert, color: AppColors.steel),
            tooltip: 'More',
            color: AppColors.graphiteRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (v) {
              if (v == 'delete') _confirmDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline,
                        size: 20, color: AppColors.danger),
                    const SizedBox(width: 10),
                    Text(
                      'Delete car',
                      style: GoogleFonts.inter(color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ], // isOwn actions
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
                onFollowChanged: (following) {
                  setState(() {
                    _car = _car.copyWith(
                      followerCount: _car.followerCount + (following ? 1 : -1),
                    );
                  });
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  SpecsTab(car: _car, isOwner: isOwn),
                  BuildTab(car: _car),
                  PostsTab(car: _car, isOwner: isOwn),
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
    this.onFollowChanged,
  });

  final Car car;
  final bool showFollow;
  final int tabIndex;
  final ValueChanged<int> onTabTap;
  final ValueChanged<bool>? onFollowChanged;

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
                    car.thumbnailUrl(width: 800)!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _HeaderFallback(),
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const SizedBox.expand(
                            child: ColoredBox(
                              color: Color(0xFF23272E),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.ember,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
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
                  if (car.followerCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${car.followerCount} ${car.followerCount == 1 ? 'follower' : 'followers'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _TabRail(index: tabIndex, onTap: onTabTap),
                if (showFollow) ...[
                  const SizedBox(height: 8),
                  FollowButton(carId: car.id, onChanged: onFollowChanged),
                ],
              ],
            ),
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
    // Icon + a permanent label: a first-time visitor shouldn't have to tap
    // through three unlabelled circles to learn what they mean.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 42,
            height: 42,
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
              size: 21,
              color: selected ? AppColors.onEmber : AppColors.steel,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? AppColors.cream : AppColors.textMuted,
            ),
          ),
        ],
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
      child: Icon(Icons.directions_car_outlined, color: AppColors.steel, size: 64),
    );
  }
}

/// Horizontal row of trophy badges earned by this car.
/// Hidden when the car has no badges yet.
class _BadgesRow extends StatefulWidget {
  const _BadgesRow({required this.carId});
  final String carId;

  @override
  State<_BadgesRow> createState() => _BadgesRowState();
}

class _BadgesRowState extends State<_BadgesRow> {
  List<CarBadge> _badges = [];

  @override
  void initState() {
    super.initState();
    ChallengeService.instance.fetchBadgesForCar(widget.carId).then((b) {
      if (mounted) setState(() => _badges = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _badges.map((b) => _BadgeChip(badge: b)).toList(),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});
  final CarBadge badge;

  @override
  Widget build(BuildContext context) {
    final year = badge.awardedAt.year;
    final month = _monthAbbr(badge.awardedAt.month);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1200),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🏆', style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            '${badge.challengeTitle} — $month $year',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.ember,
            ),
          ),
        ],
      ),
    );
  }

  static String _monthAbbr(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}
