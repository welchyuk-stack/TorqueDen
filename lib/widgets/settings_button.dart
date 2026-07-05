import 'package:flutter/material.dart';
import 'package:torqueden/screens/settings_screen.dart';
import 'package:torqueden/theme.dart';

/// A gear button that opens Settings, for the top-right of every main screen's
/// app bar (Settings moved out of the bottom bar).
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Nudged slightly left off the edge; icon 5% larger than the default 24.
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        icon: const Icon(Icons.settings_outlined, color: AppColors.steel, size: 25.2),
        tooltip: 'Settings',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    );
  }
}
