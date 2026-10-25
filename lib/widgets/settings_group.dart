import 'package:flutter/material.dart';
import 'package:torqueden/theme.dart';

/// A glass card grouping a settings section's rows, with hairline dividers —
/// the settings equivalent of the feed's translucent surfaces, so list rows
/// don't float bare on the carbon weave canvas.
///
/// Compose visibility at the call site (`if (...) MyTile()`) rather than
/// returning [SizedBox.shrink] from a row, so dividers always sit between
/// two real rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.glassCard(radius: 14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 56, color: AppColors.hairline),
            children[i],
          ],
        ],
      ),
    );
  }
}
