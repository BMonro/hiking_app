import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    // Implicit: листи підтвердження/скидання пароля працюють у будь-якому браузері.
    // PKCE прив’язує посилання до одного пристрою (code_verifier) → otp_expired на іншому.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'HikingApp',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
