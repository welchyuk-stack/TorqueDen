import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette — straight from `TorqueDen-brand-and-theme.md`.
/// Dark-mode-first: Ember is the single hot accent, used sparingly.
///
/// Most call sites reference these as static properties rather than going
/// through `Theme.of(context)`, so light/dark switching is done by flipping
/// [_brightness] (kept in sync with the resolved [ThemeData.brightness] from
/// `MaterialApp.builder` in main.dart) and re-evaluating on every rebuild.
/// Tokens that don't change between themes (the ember accent, status colors,
/// the dark-only weave tile) stay `static const` so existing `const`
/// constructors that use them keep working unchanged.
class AppColors {
  AppColors._();

  static Brightness _brightness = Brightness.dark;
  static bool get _isDark => _brightness == Brightness.dark;
  static bool get isDark => _isDark;

  /// Called once per rebuild from `MaterialApp.builder` with the resolved
  /// theme brightness (accounts for ThemeMode.system automatically).
  static void updateBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static Color get carbon =>
      _isDark ? const Color(0xFF15171B) : const Color(0xFFFFFFFF); // deep ink (dark) / canvas (light)
  static Color get background =>
      _isDark ? const Color(0xFF0E1013) : const Color(0xFFFFFFFF); // app canvas
  static Color get graphite =>
      _isDark ? const Color(0xFF1C2026) : const Color(0xFFEEEEEE); // card surface
  static Color get graphiteRaised =>
      _isDark ? const Color(0xFF23272E) : const Color(0xFFE2E2E2); // elevated wells
  static Color get hairline =>
      _isDark ? const Color(0xFF2C313A) : const Color(0x1A15171B); // borders / dividers
  static const ember = Color(0xFFFF6A2B); // primary accent, CTAs, "flame"
  static const emberHover = Color(0xFFF2581C); // accent hover / pressed
  static const onEmber = Color(0xFF2A0F04); // text / icons on ember fills
  static Color get steel =>
      _isDark ? const Color(0xFF7C8B99) : const Color(0xFF6B7280); // secondary accent, inactive
  static Color get cream =>
      _isDark ? const Color(0xFFF3ECE1) : const Color(0xFF15171B); // primary text
  static Color get textSecondary =>
      _isDark ? const Color(0xFFA8B1BB) : const Color(0xFF44464B);
  static Color get textMuted =>
      _isDark ? const Color(0xFF9AA3AD) : const Color(0xFF5B5E63);
  static const success = Color(0xFF4FB477);
  static const warning = Color(0xFFE8A13A);
  static const danger = Color(0xFFE5484D);

  // Matte carbon-fibre weave (2×2 twill) — the canvas texture. Kept extremely
  // low-contrast so at phone scale it reads as material, not wallpaper.
  // Dark-mode only — the light canvas is a plain white fill, no weave.
  static const weaveBase = Color(0xFF0C0E11); // gap between tows
  static const weaveTow = Color(0xFF101318); // the raised tow blocks
  static const weaveSheen = Color(0xFF13161B); // top-edge catch light
}

/// Shared elevation treatments for card-like surfaces and CTAs.
/// Dark-mode shadows should read as soft ambient lift, not a hard drop shadow.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.30),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.18),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  /// A soft ember-tinted glow, for the primary CTA on a screen.
  static List<BoxShadow> get emberGlow => [
    BoxShadow(
      color: AppColors.ember.withValues(alpha: 0.28),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  /// The deeper lift used behind "glass" cards — softer than [card] but wider.
  static List<BoxShadow> get glass => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.34),
      blurRadius: 26,
      offset: const Offset(0, 14),
    ),
  ];
}

/// "Glass rim" surface treatment: a faint top-lit gradient with a rim-light
/// border (brighter at the top edge, darker at the bottom) so cards read as
/// gently curved glass rather than flat filled boxes.
class AppDecorations {
  AppDecorations._();

  // Flutter can't paint a borderRadius on a Border whose sides have
  // different colors, so the "rim light" reads through the gradient fill
  // and shadow instead of a differentiated per-side border color.
  //
  // The fill is deliberately translucent (liquid-glass): the carbon weave and
  // ambient glows of [CarbonCanvas] bleed through as content scrolls. No
  // per-card BackdropFilter — real blur on every feed card kills scroll
  // performance on mid-range Android; over a dark canvas a translucent fill
  // is visually indistinguishable and stays at 60fps.
  //
  // Light mode has no canvas texture to refract, so there's nothing for a
  // translucent fill to do — cards there are a flat, plain, light-grey
  // surface instead (see the light-mode mockup: white canvas, `#EEEEEE`
  // cards, no weave, no glass).
  static BoxDecoration glassCard({double radius = 16}) {
    if (!AppColors.isDark) {
      return BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x1A15171B)),
      );
    }
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xC225292F), Color(0xA81A1E24)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.cream.withValues(alpha: 0.10)),
      boxShadow: AppShadows.glass,
    );
  }

  /// Same rim border without a background fill or shadow — for tiles whose
  /// surface is already covered by a photo (the border sits in the
  /// foreground, on top of the image).
  static Border glassRimBorder() => Border.all(
    color: AppColors.isDark
        ? AppColors.cream.withValues(alpha: 0.12)
        : const Color(0x2915171B),
  );
}

/// The app canvas: a matte carbon-fibre weave over a sunk near-black base,
/// with faint ember and steel ambient glows — the "light sources in a dark
/// garage" that the liquid-glass surfaces above it refract.
///
/// Sits once behind the whole app (via `MaterialApp.builder`), so every
/// screen with a transparent [Scaffold] shares it. The weave is rasterised to
/// a tiny tile exactly once and painted with a repeating [ui.ImageShader]:
/// one draw call for the full screen, zero per-frame cost.
class CarbonCanvas extends StatefulWidget {
  const CarbonCanvas({super.key, required this.child, this.textureOpacity = 1.0});

  final Widget child;

  /// Dial for the weave's visibility (0 = plain sunk canvas, 1 = full weave).
  /// The texture is already near-subliminal at 1.0; this exists so the feel
  /// can be tuned on-device without touching the palette.
  final double textureOpacity;

  @override
  State<CarbonCanvas> createState() => _CarbonCanvasState();
}

class _CarbonCanvasState extends State<CarbonCanvas> {
  // One tile shared by every CarbonCanvas for the app's lifetime.
  static ui.Image? _tile;
  static Future<ui.Image>? _tileFuture;

  @override
  void initState() {
    super.initState();
    if (_tile == null) {
      _tileFuture ??= _makeTile();
      _tileFuture!.then((img) {
        _tile = img;
        if (mounted) setState(() {});
      });
    }
  }

  /// Rasterises one 2×2-twill weave cell (10 logical px, drawn at 3× for
  /// crispness on high-density screens).
  static Future<ui.Image> _makeTile() async {
    const scale = 3.0;
    const cell = 10.0 * scale;
    const half = cell / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, cell, cell),
      paint..color = AppColors.weaveBase,
    );
    // Alternating warp/weft tow blocks.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, half, half),
      paint..color = AppColors.weaveTow,
    );
    canvas.drawRect(
      const Rect.fromLTWH(half, half, half, half),
      paint..color = AppColors.weaveTow,
    );
    // A 1px catch-light along each tow's top edge — the matte sheen.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, half, 1 * scale),
      paint..color = AppColors.weaveSheen,
    );
    canvas.drawRect(
      const Rect.fromLTWH(half, half, half, 1 * scale),
      paint..color = AppColors.weaveSheen,
    );

    return recorder.endRecording().toImage(cell.toInt(), cell.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isDark)
          RepaintBoundary(
            child: CustomPaint(
              painter: _CanvasPainter(
                tile: _tile,
                textureOpacity: widget.textureOpacity,
              ),
            ),
          )
        else
          // Light mode: a plain white canvas, no weave, no ambient glows.
          const ColoredBox(color: Color(0xFFFFFFFF)),
        widget.child,
      ],
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({required this.tile, required this.textureOpacity});

  final ui.Image? tile;
  final double textureOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;

    // Base — also the 1-frame fallback while the weave tile rasterises.
    canvas.drawRect(full, Paint()..color = AppColors.weaveBase);

    if (tile != null && textureOpacity > 0) {
      // Tile is drawn at 3×; scale back to 10 logical px per cell.
      final matrix = Matrix4.diagonal3Values(1 / 3, 1 / 3, 1).storage;
      canvas.drawRect(
        full,
        Paint()
          ..shader = ui.ImageShader(
            tile!,
            TileMode.repeated,
            TileMode.repeated,
            matrix,
          )
          ..color = Color.fromRGBO(0, 0, 0, textureOpacity),
      );
    }

    // Ambient garage glows — what the glass surfaces refract. Kept faint so
    // photos stay the hero; positions echo a workshop lamp top-right and a
    // cool spill mid-left.
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [color, color.withValues(alpha: 0)]),
      );
    }

    glow(
      Offset(size.width * 1.05, -size.height * 0.02),
      size.width * 0.55,
      AppColors.ember.withValues(alpha: 0.10),
    );
    glow(
      Offset(-size.width * 0.15, size.height * 0.45),
      size.width * 0.60,
      const Color(0xFF375A8C).withValues(alpha: 0.10),
    );
    glow(
      Offset(size.width * 0.95, size.height * 1.02),
      size.width * 0.45,
      AppColors.ember.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.tile != tile || old.textureOpacity != textureOpacity;
}

/// The app-wide theme for a given [brightness], derived from the brand
/// guide. Built independently of [AppColors]'s mutable brightness flag (both
/// variants are constructed once at app start, before that flag is known to
/// be correct for either one) — tokens that flip between themes are computed
/// locally from the [brightness] argument instead.
ThemeData buildTorqueDenTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  final carbon = isDark ? const Color(0xFF15171B) : const Color(0xFFFFFFFF);
  final graphite = isDark ? const Color(0xFF1C2026) : const Color(0xFFEEEEEE);
  final graphiteRaised = isDark ? const Color(0xFF23272E) : const Color(0xFFE2E2E2);
  final hairline = isDark ? const Color(0xFF2C313A) : const Color(0x1A15171B);
  final steel = isDark ? const Color(0xFF7C8B99) : const Color(0xFF6B7280);
  final cream = isDark ? const Color(0xFFF3ECE1) : const Color(0xFF15171B);
  final textSecondary = isDark ? const Color(0xFFA8B1BB) : const Color(0xFF44464B);
  final textMuted = isDark ? const Color(0xFF9AA3AD) : const Color(0xFF5B5E63);

  // Inter for body/UI text.
  final textTheme = GoogleFonts.interTextTheme(
    base.textTheme,
  ).apply(bodyColor: cream, displayColor: cream);

  return base.copyWith(
    // Transparent so every route reveals the one shared [CarbonCanvas]
    // mounted behind the Navigator (see MaterialApp.builder in main.dart).
    scaffoldBackgroundColor: carbon,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: AppColors.ember,
      onPrimary: AppColors.onEmber,
      secondary: steel,
      onSecondary: carbon,
      surface: graphite,
      onSurface: cream,
      error: AppColors.danger,
      onError: cream,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: cream,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: hairline,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: graphiteRaised,
      hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 15),
      labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 15),
      floatingLabelStyle: GoogleFonts.inter(
        color: textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      contentPadding: const EdgeInsets.fromLTRB(14, 20, 14, 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: hairline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ember, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: steel,
      textColor: cream,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: carbon,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.ember.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: selected ? cream : steel,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? AppColors.ember : steel,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: graphiteRaised,
      contentTextStyle: GoogleFonts.inter(color: cream),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ember,
        foregroundColor: AppColors.onEmber,
        disabledBackgroundColor: hairline,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        shadowColor: AppColors.ember.withValues(alpha: 0.4),
        surfaceTintColor: Colors.transparent,
      ).copyWith(elevation: const WidgetStatePropertyAll(2)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cream,
        side: BorderSide(color: hairline),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ember,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
