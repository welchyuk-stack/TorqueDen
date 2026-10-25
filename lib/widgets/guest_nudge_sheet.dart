import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/screens/auth/auth_screen.dart';
import 'package:torqueden/services/guest_mode.dart';
import 'package:torqueden/theme.dart';

/// Shows a bottom sheet prompting the guest to create an account or log in.
/// [reason] is a short phrase explaining what they were trying to do,
/// e.g. "like posts", "RSVP to meets", "follow a car".
Future<void> showGuestNudge(BuildContext context, {String reason = 'do that'}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.graphite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _GuestNudgeSheet(reason: reason),
  );
}

class _GuestNudgeSheet extends StatelessWidget {
  const _GuestNudgeSheet({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.steel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Icon(Icons.people_outline, color: AppColors.ember, size: 40),
            const SizedBox(height: 12),
            Text(
              'Join TorqueDen',
              style: GoogleFonts.archivo(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a free account to $reason and connect with the car community.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  GuestMode.clear();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen(initialLogin: false)),
                  );
                },
                child: const Text('Create account'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  GuestMode.clear();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen(initialLogin: true)),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.cream,
                  side: BorderSide(color: AppColors.steel),
                ),
                child: const Text('Log in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
