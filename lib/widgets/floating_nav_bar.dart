import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';

/// A floating, frosted-glass bottom navigation bar (iOS Liquid Glass spirit):
/// translucent + blurred, detached from the edges.
///
/// Five destinations (Home, Search, Garage, Clubs, Settings). There's no
/// visible "+" — to create a post you **drag along the bar** (thumb to the
/// left): the items fold away to the left, a "+" emerges, and **releasing**
/// while armed opens the composer. A discreet cue hints at the gesture.
class FloatingNavBar extends StatefulWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onCreate,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  State<FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<FloatingNavBar>
    with SingleTickerProviderStateMixin {
  /// How far the drag-to-post gesture has been pulled, 0 → 1 (armed near 1).
  double _reveal = 0;
  bool _fired = false;

  static const double _dragDistance = 160; // px of drag for a full reveal
  static const double _armAt = 0.6; // reveal past this = release-to-post
  static const int _slots = 5;

  late final AnimationController _spring; // animates _reveal back to 0

  bool get _armed => _reveal >= _armAt;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
      ..addListener(() => setState(() => _reveal = _spring.value));
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  /// Per-item fold progress, staggered so the rightmost item folds first as the
  /// thumb sweeps in from the right, cascading to the leftmost.
  double _itemProgress(int slot) {
    const spread = 0.5; // how spread out the cascade is over the drag
    final delay = (_slots - 1 - slot) / (_slots - 1) * spread; // right→0, left→spread
    final span = 1 - spread;
    return ((_reveal - delay) / span).clamp(0.0, 1.0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_spring.isAnimating) return;
    // Dragging left (negative dx) reveals; dragging back right hides.
    final next = (_reveal - (d.primaryDelta ?? 0) / _dragDistance).clamp(0.0, 1.0);
    if (_armed != (next >= _armAt)) HapticFeedback.selectionClick();
    setState(() => _reveal = next);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_armed && !_fired) {
      _fired = true;
      HapticFeedback.mediumImpact();
      widget.onCreate();
    }
    _spring.value = _reveal;
    _spring.animateTo(0, curve: Curves.easeOutBack).whenComplete(() => _fired = false);
  }

  Widget _slot(int slot, int screenIndex, IconData icon, IconData selectedIcon, String label) {
    return Expanded(
      child: _Folding(
        progress: _itemProgress(slot),
        child: _NavItem(
          icon: icon,
          selectedIcon: selectedIcon,
          label: label,
          selected: widget.index == screenIndex,
          onTap: () => widget.onSelect(screenIndex),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: safeBottom > 0 ? safeBottom : 12,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: _GlassBar(
          child: SizedBox(
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    _slot(0, 0, Icons.home_outlined, Icons.home, 'Home'),
                    _slot(1, 1, Icons.search_outlined, Icons.search, 'Search'),
                    _slot(2, 3, Icons.garage_outlined, Icons.garage, 'Garage'),
                    _slot(3, 2, Icons.groups_outlined, Icons.groups, 'Clubs'),
                    _slot(4, 4, Icons.settings_outlined, Icons.settings, 'Settings'),
                  ],
                ),
                // Discreet "drag to post" cue — fades out as the drag begins.
                Positioned(
                  top: 4,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - _reveal).clamp(0.0, 1.0) * 0.5,
                      child: const Center(child: _DragHint()),
                    ),
                  ),
                ),
                // The emerging "+" (and hint) as items fold away.
                if (_reveal > 0.01)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _RevealPlus(reveal: _reveal, armed: _armed),
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

/// Applies a staggered 3D "fold/tumble to the left" as [progress] goes 0 → 1.
class _Folding extends StatelessWidget {
  const _Folding({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0) return child;
    return Opacity(
      opacity: (1 - progress).clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0016) // perspective
          ..translateByDouble(-46.0 * progress, 0, 0, 1) // slide left
          ..rotateY(1.4 * progress) // fold around the vertical axis
          ..rotateZ(-0.45 * progress), // tumble
        child: child,
      ),
    );
  }
}

/// The ember "+" that emerges centre-bar as the items fold away, with a
/// keep-dragging / release-to-post hint.
class _RevealPlus extends StatelessWidget {
  const _RevealPlus({required this.reveal, required this.armed});

  final double reveal;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: reveal.clamp(0.0, 1.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 0.5 + 0.6 * reveal,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.ember, AppColors.emberHover],
                ),
                boxShadow: armed
                    ? [BoxShadow(color: AppColors.ember.withValues(alpha: 0.55), blurRadius: 16)]
                    : null,
              ),
              child: const Icon(Icons.add, color: AppColors.onEmber, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            armed ? 'Release to post' : 'Keep dragging…',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: armed ? AppColors.cream : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small, muted "‹ • • •" cue that hints you can drag the bar left.
class _DragHint extends StatelessWidget {
  const _DragHint();

  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
          width: 3,
          height: 3,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: const BoxDecoration(color: AppColors.steel, shape: BoxShape.circle),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.chevron_left, size: 12, color: AppColors.steel),
        const SizedBox(width: 1),
        dot(),
        dot(),
        dot(),
      ],
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
      // Shadow lives on an outer box so it isn't clipped by the blur.
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
              border: Border.all(
                color: AppColors.cream.withValues(alpha: 0.08),
                width: 1,
              ),
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
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? selectedIcon : icon,
              color: selected ? AppColors.ember : AppColors.steel, size: 24),
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
    );
  }
}
