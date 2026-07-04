import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:torqueden/screens/auth/auth_gate.dart';
import 'package:torqueden/supabase_config.dart';
import 'package:torqueden/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class TorqueDenApp extends StatelessWidget {
  const TorqueDenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TorqueDen',
      debugShowCheckedModeBanner: false,
      theme: buildTorqueDenTheme(),
      home: const AuthGate(),
    );
  }
}
