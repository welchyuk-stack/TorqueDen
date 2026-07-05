import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/screens/membership_screen.dart';
import 'package:torqueden/theme.dart';

/// A calm "upgrade to Premium" nudge shown when a Free-tier limit is hit
/// (e.g. car or club limit). Routes to the Membership screen.
Future<void> showUpgradeSheet(BuildContext context, {required String title, required String message}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.graphite,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.ember.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.workspace_premium_outlined, size: 34, color: AppColors.ember),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.archivo(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.cream)),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.45)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembershipScreen()));
                },
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('See Membership'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Not now', style: GoogleFonts.inter(color: AppColors.steel)),
            ),
          ],
        ),
      ),
    ),
  );
}
