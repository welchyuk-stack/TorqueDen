import 'dart:async';

import 'package:flutter/material.dart';
import 'package:torqueden/screens/community_screen.dart';
import 'package:torqueden/screens/discover_screen.dart';
import 'package:torqueden/screens/dm_inbox_screen.dart';
import 'package:torqueden/screens/feed_screen.dart';
import 'package:torqueden/screens/garage_screen.dart';
import 'package:torqueden/screens/news_screen.dart';
import 'package:torqueden/screens/settings_screen.dart';
import 'package:torqueden/services/dm_service.dart';
import 'package:torqueden/services/notifications_service.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/floating_nav_bar.dart';

/// The app shell: a floating glass bottom bar holding the whole app.
/// All tabs are accessible without an account — write actions gate to sign-up.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Emit on this to switch the shell to the feed tab (e.g. after sign-out).
  static final jumpToFeed = StreamController<void>.broadcast();

  /// Emit on this to switch the shell to the Discover tab.
  static final jumpToDiscover = StreamController<void>.broadcast();

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _navVisible = true;
  late final StreamSubscription<void> _jumpSub;

  static const _screens = [
    FeedScreen(),
    NewsScreen(),
    DiscoverScreen(),
    GarageScreen(),
    CommunityScreen(),
    DmInboxScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    NotificationsService.refreshUnread();
    DmService.refreshUnread();
    _jumpSub = MainShell.jumpToFeed.stream.listen((_) {
      if (mounted) setState(() => _index = 0);
    });
    MainShell.jumpToDiscover.stream.listen((_) {
      if (mounted) setState(() => _index = 2);
    });
  }

  @override
  void dispose() {
    _jumpSub.cancel();
    super.dispose();
  }

  void _onTabSelect(int i) {
    if (i == 0) FeedScreen.refreshSignal.add(null);
    if (i == 5) DmInboxScreen.refreshSignal.add(null);
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Keep nav pinned on messages and settings tabs.
          if (_index == 5 || _index == 6) return false;
          if (notification is ScrollUpdateNotification) {
            final delta = notification.scrollDelta ?? 0;
            if (delta > 2 && _navVisible) {
              setState(() => _navVisible = false);
            } else if (delta < -2 && !_navVisible) {
              setState(() => _navVisible = true);
            }
          }
          if (notification is ScrollEndNotification) {
            if (!_navVisible) setState(() => _navVisible = true);
          }
          return false;
        },
        child: CarbonCanvas(
          child: IndexedStack(
            index: _index,
            children: _screens,
          ),
        ),
      ),
      bottomNavigationBar: AnimatedSlide(
        offset: _navVisible ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: _navVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 180),
          child: ValueListenableBuilder<int>(
            valueListenable: NotificationsService.unread,
            builder: (context, notifUnread, _) => ValueListenableBuilder<int>(
              valueListenable: DmService.unread,
              builder: (context, dmUnread, _) => FloatingNavBar(
                index: _index,
                onSelect: _onTabSelect,
                homeUnread: notifUnread,
                dmUnread: dmUnread,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
