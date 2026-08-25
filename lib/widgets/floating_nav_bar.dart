import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:torqueden/theme.dart';

/// A floating, frosted-glass bottom navigation bar (iOS Liquid Glass spirit).
///
/// Five destinations (Home, Discover, Garage, Clubs, Messages) plus a hex-**nut**
/// create button on the far right — tap it to open the composer.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.homeUnread = 0,
    this.dmUnread = 0,
  });

  final int index;
  final ValueChanged<int> onSelect;

  /// Unread notification count — badges the Home item when > 0.
  final int homeUnread;

  /// Unread DM count — badges the Messages item when > 0.
  final int dmUnread;

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
                icon: Icons.newspaper_outlined,
                selectedIcon: Icons.newspaper,
                label: 'News',
                selected: index == 1,
                onTap: () => onSelect(1),
              ),
              _NavItem(
                icon: Icons.search_outlined,
                selectedIcon: Icons.search,
                label: 'Discover',
                selected: index == 2,
                onTap: () => onSelect(2),
              ),
              _NavItem(
                icon: Icons.garage_outlined,
                selectedIcon: Icons.garage,
                label: 'Garage',
                selected: index == 3,
                onTap: () => onSelect(3),
              ),
              _NavItem(
                icon: Icons.people_outline,
                selectedIcon: Icons.people,
                label: 'Community',
                selected: index == 4,
                onTap: () => onSelect(4),
              ),
              _NavItem(
                icon: Icons.forum_outlined,
                selectedIcon: Icons.forum,
                label: 'Messages',
                selected: index == 5,
                showBadge: dmUnread > 0,
                onTap: () => onSelect(5),
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings',
                selected: index == 6,
                onTap: () => onSelect(6),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        // Dark mode keeps the real frosted-glass blur, refracting the carbon
        // weave behind it. Light mode has no textured canvas to refract, so
        // the bar is a flat opaque grey instead — same surface language as
        // the light-mode cards, not glass — and skips the (pointless, over
        // an opaque fill) BackdropFilter cost.
        child: AppColors.isDark
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16191E).withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1),
                  ),
                  child: child,
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0x1A15171B), width: 1),
                ),
                child: child,
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
    final color = selected ? AppColors.ember : AppColors.cream.withValues(alpha: 0.6);
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
                Icon(selected ? selectedIcon : icon, color: color, size: 24),
                if (showBadge)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 8,
                      height: 8,
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
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
