import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';

/// A floating, frosted-glass bottom navigation bar (iOS Liquid Glass spirit).
///
/// Four destinations (Home, Discover, Garage, Clubs) plus a hex-**nut** create
/// button on the far right — tap it to open the composer.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onCreate,
    this.homeUnread = 0,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  /// Unread notification count — badges the Home item when > 0.
  final int homeUnread;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: safeBottom > 0 ? safeBottom : 12,
      ),
      child: _GlassBar(
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
                selected: index == 0,
                showBadge: homeUnread > 0,
                onTap: () => onSelect(0),
              ),
              _NavItem(
                icon: Icons.search_outlined,
                selectedIcon: Icons.search,
                label: 'Discover',
                selected: index == 1,
                onTap: () => onSelect(1),
              ),
              _NavItem(
                icon: Icons.garage_outlined,
                selectedIcon: Icons.garage,
                label: 'Garage',
                selected: index == 2,
                onTap: () => onSelect(2),
              ),
              _NavItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups,
                label: 'Clubs',
                selected: index == 3,
                onTap: () => onSelect(3),
              ),
              // The nut create button (far right).
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onCreate();
                  },
                  child: const _Nut(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hex-nut create handle with a "+".
class _Nut extends StatelessWidget {
  const _Nut();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 42,
        height: 42,
        child: CustomPaint(painter: _NutPainter()),
      ),
    );
  }
}

class _NutPainter extends CustomPainter {
  const _NutPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 2;

    // Flat-top hexagon (a nut).
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 180 * (60 * i);
      final p = center + Offset(r * math.cos(a), r * math.sin(a));
      i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
    }
    hex.close();

    canvas.drawPath(
      hex,
      Paint()
        ..color = AppColors.ember
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );

    // The "+" in the middle.
    final ps = r * 0.95;
    final t = ps * 0.26;
    final rr = Radius.circular(t / 2);
    final paint = Paint()..color = AppColors.ember;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: ps, height: t), rr),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: center, width: t, height: ps), rr),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _NutPainter oldDelegate) => false;
}

/// The blurred, translucent, rounded container behind the nav row.
class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.graphite.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.cream.withValues(alpha: 0.08), width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One destination in the bar: icon over a small label, ember when selected.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showBadge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? selectedIcon : icon,
                    color: selected ? AppColors.ember : AppColors.steel, size: 24),
                if (showBadge)
                  Positioned(
                    top: -1,
                    right: -3,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.ember,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.graphite, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.cream : AppColors.steel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
