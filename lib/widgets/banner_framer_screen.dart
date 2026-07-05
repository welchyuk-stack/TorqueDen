import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:torqueden/theme.dart';

/// Background choices for "Fit" mode (logos often need white or black).
const List<({String label, int r, int g, int b})> _backgrounds = [
  (label: 'Dark', r: 0x12, g: 0x14, b: 0x18),
  (label: 'Black', r: 0x00, g: 0x00, b: 0x00),
  (label: 'White', r: 0xFF, g: 0xFF, b: 0xFF),
];

/// Composites the chosen image onto a 1600×900 banner. Runs in an isolate.
/// job: {src: Uint8List, fill: bool, r/g/b: int}.
Uint8List _renderBanner(Map<String, dynamic> job) {
  final src = job['src'] as Uint8List;
  final fill = job['fill'] as bool;
  final decoded = img.decodeImage(src);
  if (decoded == null) return src;
  const w = 1600, h = 900;
  final canvas = img.Image(width: w, height: h);
  img.fill(canvas, color: img.ColorRgb8(job['r'] as int, job['g'] as int, job['b'] as int));
  final scale = fill
      ? math.max(w / decoded.width, h / decoded.height) // cover
      : math.min(w / decoded.width, h / decoded.height); // contain
  final rw = (decoded.width * scale).round();
  final rh = (decoded.height * scale).round();
  final resized = img.copyResize(decoded, width: rw, height: rh);
  img.compositeImage(canvas, resized, dstX: ((w - rw) / 2).round(), dstY: ((h - rh) / 2).round());
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
}

/// Frames an image into a 16:9 banner. "Fit" auto-scales the whole image onto a
/// background (good for logos); "Fill" covers the frame (good for photos).
/// Pops the composited [Uint8List], or null if cancelled.
class BannerFramerScreen extends StatefulWidget {
  const BannerFramerScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<BannerFramerScreen> createState() => _BannerFramerScreenState();
}

class _BannerFramerScreenState extends State<BannerFramerScreen> {
  bool _fill = false; // default = Fit (whole image visible)
  int _bg = 0;
  bool _busy = false;

  Color get _bgColor => Color.fromARGB(255, _backgrounds[_bg].r, _backgrounds[_bg].g, _backgrounds[_bg].b);

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final out = await compute(_renderBanner, {
        'src': widget.bytes,
        'fill': _fill,
        'r': _backgrounds[_bg].r,
        'g': _backgrounds[_bg].g,
        'b': _backgrounds[_bg].b,
      });
      if (mounted) Navigator.of(context).pop(out);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not process that image.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.carbon,
      appBar: AppBar(
        title: const Text('Frame your banner'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _apply,
            child: Text('Use', style: GoogleFonts.inter(color: AppColors.ember, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Live preview — matches exactly what gets saved.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: _bgColor,
                    child: Image.memory(widget.bytes, fit: _fill ? BoxFit.cover : BoxFit.contain),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Fit / Fill
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Seg(label: 'Fit whole image', selected: !_fill, onTap: () => setState(() => _fill = false)),
                const SizedBox(width: 8),
                _Seg(label: 'Fill frame', selected: _fill, onTap: () => setState(() => _fill = true)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _fill ? 'The image covers the banner — edges may be cropped.' : 'The whole image is shown on a background.',
              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
            ),
            // Background swatches (Fit only)
            if (!_fill) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _backgrounds.length; i++) ...[
                    _Swatch(
                      color: Color.fromARGB(255, _backgrounds[i].r, _backgrounds[i].g, _backgrounds[i].b),
                      label: _backgrounds[i].label,
                      selected: _bg == i,
                      onTap: () => setState(() => _bg = i),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ],
            const Spacer(),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: CircularProgressIndicator(color: AppColors.ember),
              ),
          ],
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ember : AppColors.graphiteRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.ember : AppColors.hairline),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.onEmber : AppColors.steel)),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label, required this.selected, required this.onTap});
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.ember : AppColors.hairline, width: selected ? 2.5 : 1),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
