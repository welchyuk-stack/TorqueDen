import 'package:flutter/material.dart';
import 'package:torqueden/screens/clubs_screen.dart';
import 'package:torqueden/screens/create_post_screen.dart';
import 'package:torqueden/screens/discover_screen.dart';
import 'package:torqueden/screens/feed_screen.dart';
import 'package:torqueden/screens/garage_screen.dart';
import 'package:torqueden/screens/settings_screen.dart';
import 'package:torqueden/widgets/floating_nav_bar.dart';

/// The app shell: a floating glass bottom bar with a centre "+" create button,
/// holding the whole app. Uses an IndexedStack so each tab keeps its state
/// (scroll position, etc.) when you switch between them.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = [
    FeedScreen(),
    DiscoverScreen(),
    ClubsScreen(),
    GarageScreen(),
    SettingsScreen(),
  ];

  Future<void> _createPost() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    // On a successful post, jump to Home so it's front and centre.
    if (posted == true && mounted) setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Let content sit behind the floating bar so the glass blur has something
      // to work with.
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: FloatingNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        onCreate: _createPost,
      ),
    );
  }
}
