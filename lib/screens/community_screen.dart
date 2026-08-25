import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/screens/clubs_screen.dart';
import 'package:torqueden/screens/meets_screen.dart';
import 'package:torqueden/theme.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Community',
                style: GoogleFonts.archivo(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cream,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connect with fellow enthusiasts',
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.steel),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: _CommunityCard(
                  title: 'Meets',
                  subtitle: 'Find and organise car meets near you',
                  illustration: const _MeetsIllustration(),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MeetsScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _CommunityCard(
                  title: 'Forums',
                  subtitle: 'Discuss builds, mods and everything cars',
                  illustration: const _ForumsIllustration(),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ClubsScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityCard extends StatefulWidget {
  const _CommunityCard({
    required this.title,
    required this.subtitle,
    required this.illustration,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget illustration;
  final VoidCallback onTap;

  @override
  State<_CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends State<_CommunityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse().then((_) => widget.onTap()),
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: _GlassCard(
          child: Stack(
            children: [
              // Illustration fills upper portion
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: widget.illustration,
                ),
              ),
              // Bottom text overlay with gradient fade
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.graphite.withValues(alpha: 0),
                        AppColors.graphite.withValues(alpha: 0.92),
                        AppColors.graphite,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: GoogleFonts.archivo(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cream,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.ember,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.graphite,
        border: Border.all(color: AppColors.ember.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: child,
        ),
      ),
    );
  }
}

// ─── Meets illustration: real wireframe photo ────────────────────────────────

class _MeetsIllustration extends StatelessWidget {
  const _MeetsIllustration();

  // Converts image luminance → ember orange (#FF6A2B = R:255 G:106 B:43).
  // lum = 0.299R + 0.587G + 0.114B
  // Dark: R=lum*0.88, G=lum*0.32, B=lum*0.17 — ember not fire-red
  static const _darkMatrix = ColorFilter.matrix(<double>[
    0.263, 0.516, 0.100, 0,   0,   // R * 0.88
    0.096, 0.188, 0.037, 0,   0,   // G * 0.32
    0.051, 0.100, 0.019, 0,   0,   // B * 0.17
    0,     0,     0,     1,   0,
  ]);

  // Light mode: same strong orange push, background lifted to warm cream.
  static const _lightMatrix = ColorFilter.matrix(<double>[
    0.299, 0.587, 0.114, 0, 145,
    0.066, 0.129, 0.025, 0, 110,
    0.051, 0.100, 0.019, 0,  90,
    0,     0,     0,     1,   0,
  ]);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColorFiltered(
      colorFilter: isDark ? _darkMatrix : _lightMatrix,
      child: Image.asset(
        'assets/images/wire-meets.png',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

class _MeetsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ember.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dimPaint = Paint()
      ..color = AppColors.ember.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Subtle grid floor
    _drawGrid(canvas, size, dimPaint);

    // Three cars parked side by side, receding perspective
    _drawCar(canvas, size, paint, dimPaint,
      x: size.width * 0.08, y: size.height * 0.48,
      w: size.width * 0.32, h: size.height * 0.28, style: _CarStyle.muscle);

    _drawCar(canvas, size, paint, dimPaint,
      x: size.width * 0.36, y: size.height * 0.43,
      w: size.width * 0.30, h: size.height * 0.26, style: _CarStyle.coupe);

    _drawCar(canvas, size, paint, dimPaint,
      x: size.width * 0.63, y: size.height * 0.40,
      w: size.width * 0.29, h: size.height * 0.24, style: _CarStyle.hatch);

    // Faint scan line overlay for depth
    _drawScanLines(canvas, size, dimPaint);
  }

  void _drawGrid(Canvas canvas, Size size, Paint p) {
    final horizon = size.height * 0.55;
    final vp = Offset(size.width / 2, horizon * 0.7);

    for (var i = 0; i <= 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, size.height), vp, p);
    }
    for (var i = 0; i <= 4; i++) {
      final t = i / 4.0;
      final y = horizon + (size.height - horizon) * t;
      final frac = 0.1 + t * 0.9;
      canvas.drawLine(
        Offset(size.width * (0.5 - frac * 0.5), y),
        Offset(size.width * (0.5 + frac * 0.5), y),
        p,
      );
    }
  }

  void _drawCar(Canvas canvas, Size size, Paint p, Paint dp,
      {required double x, required double y, required double w, required double h,
       required _CarStyle style}) {
    // Body outline
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + h * 0.4, w, h * 0.6),
      const Radius.circular(4),
    );
    canvas.drawRRect(body, p);

    // Roof / cabin shape
    Path roof;
    if (style == _CarStyle.muscle) {
      roof = Path()
        ..moveTo(x + w * 0.12, y + h * 0.4)
        ..lineTo(x + w * 0.22, y + h * 0.02)
        ..lineTo(x + w * 0.78, y + h * 0.02)
        ..lineTo(x + w * 0.88, y + h * 0.4)
        ..close();
    } else if (style == _CarStyle.hatch) {
      roof = Path()
        ..moveTo(x + w * 0.15, y + h * 0.4)
        ..lineTo(x + w * 0.28, y + h * 0.05)
        ..lineTo(x + w * 0.75, y + h * 0.05)
        ..lineTo(x + w * 0.85, y + h * 0.4)
        ..close();
    } else {
      roof = Path()
        ..moveTo(x + w * 0.18, y + h * 0.4)
        ..lineTo(x + w * 0.30, y + h * 0.04)
        ..lineTo(x + w * 0.72, y + h * 0.04)
        ..lineTo(x + w * 0.84, y + h * 0.4)
        ..close();
    }
    canvas.drawPath(roof, p);

    // Windows
    final winH = h * 0.25;
    final winY = y + h * 0.14;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + w * 0.23, winY, w * 0.24, winH), const Radius.circular(2)),
      dp,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + w * 0.51, winY, w * 0.24, winH), const Radius.circular(2)),
      dp,
    );

    // Wheels
    final wr = h * 0.14;
    final wheelY = y + h;
    canvas.drawCircle(Offset(x + w * 0.22, wheelY - wr * 0.2), wr, p);
    canvas.drawCircle(Offset(x + w * 0.22, wheelY - wr * 0.2), wr * 0.45, dp);
    canvas.drawCircle(Offset(x + w * 0.78, wheelY - wr * 0.2), wr, p);
    canvas.drawCircle(Offset(x + w * 0.78, wheelY - wr * 0.2), wr * 0.45, dp);

    // Headlights / taillights
    final lightW = w * 0.08;
    final lightH = h * 0.08;
    final lightY = y + h * 0.56;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x + w * 0.02, lightY, lightW, lightH), const Radius.circular(2)),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x + w - lightW - w * 0.02, lightY, lightW, lightH), const Radius.circular(2)),
      p,
    );
  }

  void _drawScanLines(Canvas canvas, Size size, Paint p) {
    for (var y = 0.0; y < size.height; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p..strokeWidth = 0.3);
    }
  }

  @override
  bool shouldRepaint(covariant _MeetsPainter oldDelegate) => false;
}

enum _CarStyle { muscle, coupe, hatch }

// ─── Forums illustration: message board wireframe ────────────────────────────

class _ForumsIllustration extends StatelessWidget {
  const _ForumsIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ForumsPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ForumsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.ember.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dp = Paint()
      ..color = AppColors.ember.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final fp = Paint()
      ..color = AppColors.ember.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    _drawScanLines(canvas, size, dp);

    // Main board panel
    final boardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.06, size.height * 0.06, size.width * 0.88, size.height * 0.82),
      const Radius.circular(8),
    );
    canvas.drawRRect(boardRect, fp);
    canvas.drawRRect(boardRect, p);

    // Header bar
    final headerRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(size.width * 0.06, size.height * 0.06, size.width * 0.88, size.height * 0.10),
      topLeft: const Radius.circular(8), topRight: const Radius.circular(8),
    );
    canvas.drawRRect(headerRect, fp..color = AppColors.ember.withValues(alpha: 0.18));
    canvas.drawRRect(headerRect, p);

    // Header title line
    _roundedLine(canvas, size.width * 0.14, size.height * 0.09,
        size.width * 0.42, size.height * 0.035, p);

    // Thread rows
    final rowData = [
      (0.20, 0.55, 0.70),
      (0.30, 0.45, 0.55),
      (0.42, 0.50, 0.62),
      (0.54, 0.40, 0.58),
      (0.66, 0.52, 0.68),
    ];

    for (final (yFrac, titleW, bodyW) in rowData) {
      final rowY = size.height * yFrac;

      // Avatar circle
      canvas.drawCircle(
        Offset(size.width * 0.13, rowY + size.height * 0.025),
        size.height * 0.028,
        dp,
      );

      // Title line
      _roundedLine(canvas, size.width * 0.21, rowY,
          size.width * titleW, size.height * 0.025, p);

      // Body line
      _roundedLine(canvas, size.width * 0.21, rowY + size.height * 0.035,
          size.width * bodyW, size.height * 0.018, dp);

      // Reply chip
      _chip(canvas, size.width * 0.76, rowY + size.height * 0.002,
          size.width * 0.14, size.height * 0.030, p, dp);

      // Divider
      if (yFrac < 0.60) {
        canvas.drawLine(
          Offset(size.width * 0.09, rowY + size.height * 0.068),
          Offset(size.width * 0.91, rowY + size.height * 0.068),
          dp,
        );
      }
    }

    // Compose button bottom right
    final btnRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.68, size.height * 0.76, size.width * 0.24, size.height * 0.06),
      const Radius.circular(20),
    );
    canvas.drawRRect(btnRect, fp..color = AppColors.ember.withValues(alpha: 0.20));
    canvas.drawRRect(btnRect, p);
    // + icon in button
    final bx = size.width * 0.745;
    final by = size.height * 0.79;
    final bs = size.height * 0.018;
    canvas.drawLine(Offset(bx - bs, by), Offset(bx + bs, by), p);
    canvas.drawLine(Offset(bx, by - bs), Offset(bx, by + bs), p);
  }

  void _roundedLine(Canvas canvas, double x, double y, double w, double h, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(h / 2)),
      p,
    );
  }

  void _chip(Canvas canvas, double x, double y, double w, double h, Paint p, Paint dp) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(h / 2)),
      dp,
    );
  }

  void _drawScanLines(Canvas canvas, Size size, Paint p) {
    for (var y = 0.0; y < size.height; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p..strokeWidth = 0.3);
    }
  }

  @override
  bool shouldRepaint(covariant _ForumsPainter oldDelegate) => false;
}
