import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Keep in sync with pubspec.yaml `version:`.
const String kAppVersion = '1.0.0';

/// About TorqueDen — wordmark, tagline, version and a short blurb.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Wordmark(fontSize: 40),
                const SizedBox(height: 10),
                Text('Where the build lives.',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
                const SizedBox(height: 28),
                Text(
                  'TorqueDen is a home for car builds — share your project, follow other '
                  'people\'s work, and find your crew in clubs.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.graphiteRaised,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text('Version $kAppVersion',
                      style: GoogleFonts.inter(color: AppColors.steel, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 40),
                Text('© 2026 TorqueDen',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
