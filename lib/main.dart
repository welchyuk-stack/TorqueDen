import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/ads/consent_service.dart';
import 'package:torqueden/screens/auth/auth_gate.dart';
import 'package:torqueden/services/biometric_lock.dart';
import 'package:torqueden/services/saved_location.dart';
import 'package:torqueden/services/units_pref.dart';
import 'package:torqueden/supabase_config.dart';
import 'package:torqueden/theme.dart';
import 'package:torqueden/widgets/biometric_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load local preferences (distance units default to km; saved search location;
  // biometric-lock setting).
  await UnitsPref.load();
  await SavedLocation.load();
  await BiometricLock.load();

  // Connect to Supabase (credentials live in supabase_config.dart).
  // Guarded so the app still runs if the config hasn't been filled in.
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

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
    return MaterialApp(
      title: 'TorqueDen',
      debugShowCheckedModeBanner: false,
      theme: buildTorqueDenTheme(),
      home: const BiometricGate(child: AuthGate()),
    );
  }
}
