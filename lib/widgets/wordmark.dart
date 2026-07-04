import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';

/// The TorqueDen wordmark: "Torque" in Cream, "Den" in Ember (Archivo, heavy).
/// Keeps its native casing — never all-caps.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.archivo(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.01 * fontSize,
      height: 1.0,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Torque', style: style.copyWith(color: AppColors.cream)),
          TextSpan(text: 'Den', style: style.copyWith(color: AppColors.ember)),
        ],
      ),
    );
  }
}
