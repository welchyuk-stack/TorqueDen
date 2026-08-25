import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/ads/consent_service.dart';
import 'package:torqueden/iap/iap_service.dart';
import 'package:torqueden/push/push_service.dart';
import 'package:torqueden/screens/splash_screen.dart';
import 'package:torqueden/services/biometric_lock.dart';
import 'package:torqueden/services/feed_prefs.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/services/theme_pref.dart';
import 'package:torqueden/services/units_pref.dart';
import 'package:torqueden/supabase_config.dart';
import 'package:torqueden/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load local preferences (distance units default to km; saved search location;
  // biometric-lock setting).
  await UnitsPref.load();
  await SavedLocation.load();
  await BiometricLock.load();
  await ThemePref.load();
  await FeedPrefs.load();

  // Connect to Supabase (credentials live in supabase_config.dart).
  // Guarded so the app still runs if the config hasn't been filled in.
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  // Configure RevenueCat for in-app purchases (no-op until a real key is set).
  await IapService.instance.configure();

  // Initialise push (no-op until a Firebase project is configured).
  await PushService.instance.init();

  runApp(const TorqueDenApp());
}

class TorqueDenApp extends StatefulWidget {
  const TorqueDenApp({super.key});

  @override
  State<TorqueDenApp> createState() => _TorqueDenAppState();
}

class _TorqueDenAppState extends State<TorqueDenApp> {
  @override
  void initState() {
    super.initState();
    // Gather ad consent (UMP form + iOS ATT prompt) and initialise the ads SDK
    // once the first frame is up. Runs once; ads won't load until it resolves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ConsentService.instance.ensureReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemePref.notifier,
      builder: (context, mode, _) {
        final systemBrightness = MediaQuery.platformBrightnessOf(context);
        final effective = mode == ThemeMode.system
            ? systemBrightness
            : (mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
        // Most of the app reads AppColors.* as a static property rather than
        // via Theme.of(context), so switching brightness has to be a real
        // remount (not just a rebuild): a `const` widget anywhere in the tree
        // (there are many) is otherwise never revisited by Flutter once
        // built, since its widget instance stays identical across rebuilds
        // and gets skipped rather than re-evaluated. Keying on the resolved
        // brightness forces the whole subtree to unmount/remount on every
        // theme change, so every AppColors.* reference — const or not — is
        // freshly read against the new value.
        AppColors.updateBrightness(effective);
        return KeyedSubtree(
          key: ValueKey(effective),
          child: MaterialApp(
            title: 'TorqueDen',
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: buildTorqueDenTheme(Brightness.light),
            darkTheme: buildTorqueDenTheme(Brightness.dark),
            home: const SplashScreen(),
          ),
        );
      },
    );
  }
}
