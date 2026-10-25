import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/screens/auth/auth_gate.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/biometric_gate.dart';

const int _kTotalMs = 1500;
const double _tRoll   = 0;
const double _tImpact = 700;
const double _tSettle = 900;
const double _tTag    = 1200;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: _kTotalMs),
      vsync: this,
    )..forward();

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _navigate();
    });
  }

  void _navigate() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, a1, a2) => const BiometricGate(child: AuthGate()),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, anim, a2, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final groundY = size.height * 0.5;
    const r = 100.0; // tyre radius (larger than old wheel)

    final isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    return Scaffold(
      backgroundColor: const Color(0xFF15171B), // always dark — tyre is designed for dark bg
      body: GestureDetector(
        onTap: _navigate,
        child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final ms = _ctrl.value * _kTotalMs;
          final tagAlpha = _clamp((ms - _tTag) / 400, 0, 1);

          final tyreAlpha = _clamp((ms - _tRoll) / 200, 0, 1);
          // Tyre x position — must mirror painter logic exactly
          double tyreX = size.width / 2;
          double shakeX = 0;
          if (ms >= _tRoll && ms < _tImpact) {
            final p = _clamp((ms - _tRoll) / (_tImpact - _tRoll), 0, 1);
            tyreX = -r + (size.width / 2 + r) * _easeOutCubic(p);
          } else if (ms >= _tImpact) {
            final imp = _clamp((ms - _tImpact) / (_tSettle - _tImpact), 0, 1);
            if (imp < 1) shakeX = math.sin(imp * math.pi * 3) * 3 * (1 - imp);
          }
          tyreX += shakeX;
          final tyreCY = groundY - r + 2;

          return Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Color(0xFF15171B))),

              Positioned.fill(
                child: CustomPaint(
                  painter: _TyrePainter(
                    elapsedMs: ms,
                    screenWidth: size.width,
                    groundY: groundY,
                    radius: r,
                  ),
                ),
              ),

              // TD monogram — Flutter widget so it's guaranteed to render
              Positioned(
                left: tyreX - r * 0.6,
                top: tyreCY - r * 0.35,
                width: r * 1.2,
                height: r * 0.7,
                child: Opacity(
                  opacity: tyreAlpha,
                  child: Center(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'T',
                            style: TextStyle(
                              fontSize: r * 0.58,
                              fontWeight: FontWeight.w900,
                              color: isDark ? AppColors.cream : Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: 'D',
                            style: TextStyle(
                              fontSize: r * 0.58,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF5C00),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Tagline fades in after tyre settles
              Positioned(
                left: 0, right: 0,
                top: groundY + r + 28,
                child: Opacity(
                  opacity: tagAlpha,
                  child: Center(
                    child: Text(
                      'Where the build lives.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF5B5E63),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

// ── Tyre CustomPainter ───────────────────────────────────────────────────────

class _TyrePainter extends CustomPainter {
  const _TyrePainter({
    required this.elapsedMs,
    required this.screenWidth,
    required this.groundY,
    required this.radius,
  });

  final double elapsedMs;
  final double screenWidth;
  final double groundY;
  final double radius;

  static double _nearestUpright(double a) {
    const twoPi = math.pi * 2;
    return (a / twoPi).round() * twoPi;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius;
    final restX = screenWidth / 2;
    final cy = groundY - r + 2;
    final e = elapsedMs;

    double wheelX = -r;
    double angle = 0;
    double alpha = 0;
    double shakeX = 0;

    if (e >= _tRoll && e < _tImpact) {
      final p = _clamp((e - _tRoll) / (_tImpact - _tRoll), 0, 1);
      final ep = _easeOutCubic(p);
      wheelX = -r + (restX + r) * ep;
      final dist = wheelX - (-r);
      angle = dist / r;
      alpha = _clamp(p * 5, 0, 1);
    } else if (e >= _tImpact) {
      wheelX = restX;
      alpha = 1;
      final impactDist = restX + r;
      final impactAngle = impactDist / r;
      final target = _nearestUpright(impactAngle);
      final settleP = _clamp((e - _tImpact) / (_tSettle - _tImpact), 0, 1);
      angle = impactAngle + (target - impactAngle) * _easeOutCubic(settleP);
      // Gentle single-bounce settle instead of rapid oscillation
      final imp = _clamp((e - _tImpact) / (_tSettle - _tImpact), 0, 1);
      if (imp < 1) shakeX = math.sin(imp * math.pi * 3) * 3 * (1 - imp);
    }

    if (e < _tRoll) return;

    final cx = wheelX + shakeX;

    canvas.save();
    canvas.translate(cx, cy);

    // Spotlight so the tyre reads against the carbon background.
    canvas.drawCircle(
      Offset.zero, r * 1.8,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero, r * 1.8,
          [
            Color.fromRGBO(255, 255, 255, 0.18 * alpha),
            Colors.transparent,
          ],
          [0.0, 1.0],
        ),
    );

    canvas.rotate(angle);

    _drawTyre(canvas, r, alpha);

    canvas.restore();
  }

  void _drawTyre(Canvas canvas, double r, double alpha) {
    // Design coordinates are 1400px canvas with tyre at radius ~660.
    // We map: design radius 660 → our r.
    final sc = r / 660.0;

    void ring(Canvas c, double r0, double r1, Paint p) {
      final path = Path()
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: r1 * sc))
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: r0 * sc));
      path.fillType = PathFillType.evenOdd;
      c.drawPath(path, p);
    }

    // ── TREAD SHOULDER (600–660) ─────────────────────────────────────────
    ring(canvas, 600, 660,
        Paint()..color = Color(0xFF3a3a3e).withValues(alpha: alpha));

    // Directional shoulder grooves
    final groovePaint = Paint()
      ..color = const Color(0x04040585).withValues(alpha: 0.85 * alpha)
      ..strokeWidth = 7 * sc
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int d = 0; d < 360; d += 5) {
      final a1 = (d - 90) * math.pi / 180;
      final a2 = (d + 4 - 90) * math.pi / 180;
      final x1 = 614 * sc * math.cos(a1), y1 = 614 * sc * math.sin(a1);
      final x2 = 661 * sc * math.cos(a2), y2 = 661 * sc * math.sin(a2);
      groovePaint
        ..color = Color.fromRGBO(4, 4, 5, 0.85 * alpha)
        ..strokeWidth = 7 * sc;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), groovePaint);

      final a3 = (d - 1 - 90) * math.pi / 180;
      final x3 = 614 * sc * math.cos(a3), y3 = 614 * sc * math.sin(a3);
      final x4 = 661 * sc * math.cos(a2), y4 = 661 * sc * math.sin(a2);
      canvas.drawLine(Offset(x3, y3), Offset(x4, y4),
          Paint()
            ..color = Color.fromRGBO(255, 255, 255, 0.05 * alpha)
            ..strokeWidth = 2 * sc
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke);
    }

    // Circumferential groove separating shoulder from sidewall
    canvas.drawCircle(Offset.zero, 596 * sc,
        Paint()
          ..color = Color(0xFF0a0a0b).withValues(alpha: alpha)
          ..strokeWidth = 9 * sc
          ..style = PaintingStyle.stroke);

    // Outer edge
    canvas.drawCircle(Offset.zero, 659 * sc,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.8 * alpha)
          ..strokeWidth = 3 * sc
          ..style = PaintingStyle.stroke);

    // ── SIDEWALL (490–592) ───────────────────────────────────────────────
    final swColors = [
      Color(0xFF363639).withValues(alpha: alpha),
      Color(0xFF484850).withValues(alpha: alpha),
      Color(0xFF555560).withValues(alpha: alpha),
      Color(0xFF5e5e6a).withValues(alpha: alpha),
      Color(0xFF484850).withValues(alpha: alpha),
      Color(0xFF363639).withValues(alpha: alpha),
      Color(0xFF2a2a2e).withValues(alpha: alpha),
    ];
    final swGrad = ui.Gradient.radial(
      Offset.zero, 592 * sc,
      swColors,
      [0.0, 0.13, 0.37, 0.60, 0.81, 0.95, 1.0],
      TileMode.clamp,
      null,
      Offset.zero,
      490 * sc / (592 * sc),
    );
    ring(canvas, 490, 592, Paint()..shader = swGrad);

    // Moulding rib rings
    for (final rb in [512.0, 578.0]) {
      canvas.drawCircle(Offset.zero, rb * sc,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.32 * alpha)
            ..strokeWidth = 2 * sc
            ..style = PaintingStyle.stroke);
      canvas.drawCircle(Offset.zero, (rb - 2) * sc,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.07 * alpha)
            ..strokeWidth = sc
            ..style = PaintingStyle.stroke);
    }

    // ── BEAD / RIM-PROTECTOR (484–514) ───────────────────────────────────
    final beadGrad = ui.Gradient.radial(
      Offset.zero, 516 * sc,
      [
        Color(0xFF0f0f10).withValues(alpha: alpha),
        Color(0xFF3d3d41).withValues(alpha: alpha),
        Color(0xFF232426).withValues(alpha: alpha),
        Color(0xFF1a1a1c).withValues(alpha: alpha),
      ],
      [0.0, 0.35, 0.7, 1.0],
      TileMode.clamp,
      null,
      Offset.zero,
      484 * sc / (516 * sc),
    );
    ring(canvas, 484, 514, Paint()..shader = beadGrad);

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 500 * sc),
      (-170 - 90) * math.pi / 180, 160 * math.pi / 180, false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10 * alpha)
        ..strokeWidth = 3 * sc
        ..style = PaintingStyle.stroke);

    // Inner chamfer
    final chamferGrad = ui.Gradient.radial(
      Offset.zero, 484 * sc,
      [
        Color(0xFF060607).withValues(alpha: alpha),
        Color(0xFF0f0f10).withValues(alpha: alpha),
      ],
      [0.0, 1.0],
      TileMode.clamp,
      null,
      Offset.zero,
      474 * sc / (484 * sc),
    );
    ring(canvas, 474, 484, Paint()..shader = chamferGrad);

    canvas.drawCircle(Offset.zero, 475 * sc,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.65 * alpha)
          ..strokeWidth = 2 * sc
          ..style = PaintingStyle.stroke);

    // ── SIDEWALL STAMPED TEXT ────────────────────────────────────────────
    _drawArcText(canvas, sc, alpha,
        text: 'TORQUEDEN', r: 544, deg: 0, size: 54, spacing: 10,
        base: Color(0xFF4b4b4f), hi: Colors.white.withValues(alpha: 0.32),
        sh: Colors.black.withValues(alpha: 0.75), off: 2.5);

    _drawArcText(canvas, sc, alpha,
        text: '285/30/20', r: 542, deg: 180, size: 40, spacing: 6,
        base: Color(0xFF48484c), hi: Colors.white.withValues(alpha: 0.30),
        sh: Colors.black.withValues(alpha: 0.72), off: 2.5, flip: true);

    _drawArcText(canvas, sc, alpha,
        text: 'TUBELESS RADIAL', r: 544, deg: -50, size: 20, spacing: 4,
        base: Color(0xFF434347), hi: Colors.white.withValues(alpha: 0.22),
        sh: Colors.black.withValues(alpha: 0.60), off: 1.2);

    _drawArcText(canvas, sc, alpha,
        text: 'WELCHY', r: 544, deg: 50, size: 20, spacing: 4,
        base: Color(0xFF434347), hi: Colors.white.withValues(alpha: 0.22),
        sh: Colors.black.withValues(alpha: 0.60), off: 1.2);

    // Balance-mark dot
    final bmAngle = (150 - 90) * math.pi / 180;
    final bmOffset = Offset(528 * sc * math.cos(bmAngle), 528 * sc * math.sin(bmAngle));
    canvas.drawCircle(bmOffset, 6 * sc,
        Paint()..color = Color.fromRGBO(214, 190, 44, 0.85 * alpha));
    canvas.drawCircle(bmOffset, 6 * sc,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4 * alpha)
          ..strokeWidth = 1.5 * sc
          ..style = PaintingStyle.stroke);

    // ── CENTRE HUB DISC ──────────────────────────────────────────────────
    const R_HUB = 473.0;

    final discGrad = ui.Gradient.radial(
      Offset(-80 * sc, -80 * sc), R_HUB * sc,
      [
        Color(0xFF3a3d46).withValues(alpha: alpha),
        Color(0xFF252830).withValues(alpha: alpha),
        Color(0xFF181a20).withValues(alpha: alpha),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawCircle(Offset.zero, R_HUB * sc, Paint()..shader = discGrad);

    // Ember glow behind TD
    final glowGrad = ui.Gradient.radial(
      Offset.zero, 220 * sc,
      [
        Color.fromRGBO(255, 92, 0, 0.14 * alpha),
        Colors.transparent,
      ],
      [0.0, 1.0],
    );
    canvas.drawCircle(Offset.zero, 220 * sc, Paint()..shader = glowGrad);

    // Inner ember ring
    canvas.drawCircle(Offset.zero, (R_HUB - 4) * sc,
        Paint()
          ..color = Color.fromRGBO(255, 92, 0, 0.20 * alpha)
          ..strokeWidth = 8 * sc
          ..style = PaintingStyle.stroke);

    // Hub divider ring
    canvas.drawCircle(Offset.zero, R_HUB * sc,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.7 * alpha)
          ..strokeWidth = 3 * sc
          ..style = PaintingStyle.stroke);
  }

  void _drawArcText(
    Canvas canvas,
    double sc,
    double alpha, {
    required String text,
    required double r,
    required double deg,
    required double size,
    required double spacing,
    required Color base,
    required Color hi,
    required Color sh,
    required double off,
    bool flip = false,
  }) {
    final chars = text.split('');
    final fontSize = size * sc;
    final sp = spacing * sc;
    final o = off * sc;
    final radius = r * sc;

    // Measure each char
    final widths = chars.map((ch) {
      final tp = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            fontFamily: 'Arial',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }).toList();

    final total = widths.fold(0.0, (a, b) => a + b) + sp * (widths.length - 1);
    final totalA = total / radius;

    final passes = [
      [-o, hi.withValues(alpha: hi.a * alpha)],
      [o, sh.withValues(alpha: sh.a * alpha)],
      [0.0, base.withValues(alpha: base.a * alpha)],
    ];

    for (final pass in passes) {
      final offset = pass[0] as double;
      final color = pass[1] as Color;

      double acc = 0;
      for (int i = 0; i < chars.length; i++) {
        final t = (acc + widths[i] / 2) / radius;
        final degRad = deg * math.pi / 180;
        final a = flip
            ? degRad + totalA / 2 - t
            : degRad - totalA / 2 + t;

        canvas.save();
        canvas.translate(offset, offset);
        canvas.translate(0, 0); // at tyre centre
        canvas.rotate(a);
        canvas.translate(0, -radius);
        if (flip) canvas.rotate(math.pi);

        final tp = TextPainter(
          text: TextSpan(
            text: chars[i],
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: color,
              fontFamily: 'Arial',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

        canvas.restore();
        acc += widths[i] + sp;
      }
    }
  }

  @override
  bool shouldRepaint(_TyrePainter old) => old.elapsedMs != elapsedMs;
}

// ── helpers ──────────────────────────────────────────────────────────────────

double _clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;
double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
