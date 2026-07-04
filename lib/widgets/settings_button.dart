import 'package:flutter/material.dart';
import 'package:torqueden/screens/settings_screen.dart';
import 'package:torqueden/theme.dart';

/// A gear button that opens Settings, for the top-right of every main screen's
/// app bar (Settings moved out of the bottom bar).
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined, color: AppColors.steel),
      tooltip: 'Settings',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
