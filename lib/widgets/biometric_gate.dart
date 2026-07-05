import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/services/biometric_lock.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/wordmark.dart';

/// Wraps the app in a biometric lock. When [BiometricLock.enabled] and a user is
/// signed in, the app locks on launch and whenever it returns from the
/// background, requiring Face ID / Touch ID (or device passcode) to unlock.
class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.child});

  final Widget child;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  bool _locked = false;
  bool _prompting = false;

  bool get _shouldLock =>
      BiometricLock.enabled && Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    // Lock once per app session (at launch). We deliberately do NOT re-lock on
    // background/resume — that re-prompted on every app switch, and even on
    // transient 'inactive' states (Control Center, the app switcher, system
    // dialogs). Face ID is asked for once when the app opens.
    if (_shouldLock) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  Future<void> _unlock() async {
    if (_prompting || !_locked) return;
    _prompting = true;
    final ok = await BiometricLock.authenticate('Unlock TorqueDen');
    _prompting = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.carbon,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Wordmark(fontSize: 34),
                      const SizedBox(height: 28),
                      const Icon(Icons.lock_outline, size: 40, color: AppColors.steel),
                      const SizedBox(height: 20),
                      Text('TorqueDen is locked',
                          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 15)),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _unlock,
                        icon: const Icon(Icons.fingerprint, size: 20),
                        label: const Text('Unlock'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
