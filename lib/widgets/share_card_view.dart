import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/models/car.dart';
import 'package:torqueden/models/build_entry.dart';
import 'package:torqueden/theme.dart';

/// Landscape Top Trumps–style share card.
/// Logical size: 480×300 — captured at 4× = 1920×1200 px.
class ShareCardView extends StatelessWidget {
  const ShareCardView({
    super.key,
    required this.car,
    this.recentEntries = const [],
  });

  final Car car;
  final List<BuildEntry> recentEntries;

  static const double cardW = 480;
  static const double cardH = 300;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardW,
      height: cardH,
      child: _CardContent(car: car, recentEntries: recentEntries),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.car, required this.recentEntries});

  final Car car;
  final List<BuildEntry> recentEntries;

  @override
  Widget build(BuildContext context) {
    final stats = _buildStats();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-bleed car photo ──────────────────────────────────────────
          if (car.hasPhoto)
            Image.network(car.photoUrl!, fit: BoxFit.cover)
          else
            _NoCar(),

          // ── Dark gradient — bottom 60% ────────────────────────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.25, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),

          // ── Left gradient so stats text is always readable ────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  stops: const [0.55, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),

          // ── Ember accent bar — left edge ─────────────────────────────────
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 5,
            child: ColoredBox(color: AppColors.ember),
          ),

          // ── Bottom bar: car name left, wordmark right ────────────────────
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Car name + make/model
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        car.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.7),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (car.year != null) '${car.year}',
                          car.make,
                          car.model,
                        ].join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // TorqueDen wordmark — large, bottom right
                _Wordmark(fontSize: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _buildStats() {
    final out = <(String, String)>[];
    if (car.year != null) out.add(('YEAR', '${car.year}'));
    if (car.color != null && car.color!.trim().isNotEmpty) {
      out.add(('COLOUR', car.color!.trim()));
    }
    if (car.chassisModel != null && car.chassisModel!.trim().isNotEmpty) {
      out.add(('CHASSIS', car.chassisModel!.trim()));
    }
    // Up to 2 build entries as headline mods
    final mods = recentEntries
        .where((e) => e.title.trim().isNotEmpty)
        .take(2)
        .map((e) => e.title.trim())
        .toList();
    for (final m in mods) {
      out.add(('MOD', m));
    }
    return out.take(4).toList();
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$label  ',
            style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: AppColors.ember,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
      height: 1.0,
    );
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'Torque',
          style: style.copyWith(
            color: Colors.white,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
        TextSpan(
          text: 'Den',
          style: style.copyWith(
            color: AppColors.ember,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
      ]),
    );
  }
}

class _NoCar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1E1E), Color(0xFF0A0A0A)],
        ),
      ),
      child: Center(
        child: Icon(Icons.directions_car_outlined, size: 72, color: AppColors.steel),
      ),
    );
  }
}
