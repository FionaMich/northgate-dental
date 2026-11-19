import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/account_repository.dart';
import 'data/secure_session_storage.dart';
import 'state.dart';

// Passed at build time: flutter run --dart-define-from-file=staging.env (the file is git-ignored).
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _publishableKey.isEmpty) {
    throw StateError('Run with --dart-define-from-file=staging.env (SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY).');
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _publishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  runApp(ProviderScope(
    overrides: [accountRepositoryProvider.overrideWithValue(SupabaseAccountRepository(Supabase.instance.client))],
    child: const NorthgateApp(),
  ));
}
