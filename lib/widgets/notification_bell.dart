import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:torqueden/screens/notifications_list_screen.dart';
import 'package:torqueden/services/notifications_service.dart';
import 'package:torqueden/theme.dart';

/// Bell button for the top-right of the main screens' app bars, with an unread
/// count badge. Opens the notifications inbox and refreshes its count on return.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await NotificationsService.unreadCount();
    if (mounted) setState(() => _unread = n);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsListScreen()),
    );
    _refresh(); // reflect anything read while the inbox was open
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none, color: AppColors.steel, size: 25.2),
          tooltip: 'Notifications',
          onPressed: _open,
        ),
        if (_unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppColors.ember,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
              child: Text(
                _unread > 9 ? '9+' : '$_unread',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onEmber,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
