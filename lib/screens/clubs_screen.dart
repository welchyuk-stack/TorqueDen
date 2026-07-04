import 'package:flutter/material.dart';
import 'package:torqueden/widgets/empty_state.dart';

/// Clubs tab — groups/communities of car people (crews, local meets, marque
/// clubs). Placeholder for now; the feature is coming.
class ClubsScreen extends StatelessWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clubs')),
      body: const SafeArea(
        child: EmptyState(
          icon: Icons.groups_outlined,
          title: 'Clubs are coming',
          message:
              'Find your crew — local meets, marque clubs, and build communities. '
              'This is where they\'ll live.',
        ),
      ),
    );
  }
}
