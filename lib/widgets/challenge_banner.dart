import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/models/challenge.dart';
import 'package:torqueden/services/challenge_service.dart';
import 'package:torqueden/theme.dart';

class ChallengeBanner extends StatefulWidget {
  const ChallengeBanner({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  State<ChallengeBanner> createState() => _ChallengeBannerState();
}

class _ChallengeBannerState extends State<ChallengeBanner>
    with SingleTickerProviderStateMixin {
  late Future<Challenge?> _future;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _future = ChallengeService.instance.fetchActive();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Challenge?>(
      future: _future,
      builder: (context, snap) {
        final c = snap.data;
        if (c == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: GestureDetector(
              onTap: widget.onTap,
              child: _GlowPill(controller: _controller, challenge: c),
            ),
          ),
        );
      },
    );
  }
}

class _GlowPill extends StatelessWidget {
  const _GlowPill({required this.controller, required this.challenge});
  final AnimationController controller;
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    const pillW = 180.0;
    const pillH = 56.0;
    const glowPad = 14.0;

    return SizedBox(
      width: pillW + glowPad * 2,
      height: pillH + glowPad * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating glow ring
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) => Transform.rotate(
              angle: controller.value * 2 * math.pi,
              child: Container(
                width: pillW + glowPad * 2,
                height: pillH + glowPad * 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(pillH / 2 + glowPad),
                  gradient: const SweepGradient(
                    colors: [
                      Color(0x00E85A00),
                      Color(0xCCE85A00),
                      Color(0xFFFF9500),
                      Color(0xCCE85A00),
                      Color(0x00E85A00),
                    ],
                    stops: [0.0, 0.2, 0.5, 0.8, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Pill body
          Container(
            width: pillW,
            height: pillH,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(pillH / 2),
              border: Border.all(
                color: AppColors.ember.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'THE SHOT',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  challenge.title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.ember,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
