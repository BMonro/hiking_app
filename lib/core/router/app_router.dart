import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/routes/presentation/routes_screen.dart';
import '../../features/routes/presentation/route_details_screen.dart';
import '../../features/routes/presentation/route_weather_screen.dart';
import '../../features/navigation/presentation/navigation_screen.dart';
import '../../features/group_hikes/presentation/group_hikes_screen.dart';
import '../../features/trips/presentation/trip_chat_screen.dart';
import '../../features/trips/presentation/trip_detail_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/weather/presentation/weather_screen.dart';
import '../../features/profile/presentation/achievements_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/my_routes_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/statistics_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../shell/main_shell.dart';

Future<bool> _needsPhysicalProfile(String userId) async {
  final profile = await Supabase.instance.client
      .from('profiles')
      .select('age')
      .eq('id', userId)
      .maybeSingle();
  return profile == null || profile['age'] == null;
}

/// Notifies [GoRouter] when Supabase auth session changes (e.g. OAuth deep link).
class AuthSessionRefreshNotifier extends ChangeNotifier {
  AuthSessionRefreshNotifier() {
    _subscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = AuthSessionRefreshNotifier();
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) async {
      try {
        final session = Supabase.instance.client.auth.currentSession;
        final loc = state.matchedLocation;
        final isLoggedIn = session != null;
        final isLoginRoute = loc == '/login';
        final isRegisterRoute = loc == '/register';

        if (!isLoggedIn) {
          if (isLoginRoute || isRegisterRoute) return null;
          return '/login';
        }

        final userId = session.user.id;
        final needsPhysical = await _needsPhysicalProfile(userId);

        if (needsPhysical) {
          if (isRegisterRoute) return null;
          return '/register?oauth=1';
        }

        if (!needsPhysical) {
          if (isRegisterRoute || isLoginRoute) return '/home';
        }

        return null;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('GoRouter redirect error: $e\n$st');
        }
        return '/login';
      }
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Помилка')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(state.error?.toString() ?? 'Невідома помилка навігації'),
      ),
    ),
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => RegisterScreen(
          physicalStepOnly: state.uri.queryParameters['oauth'] == '1',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/routes',
            builder: (context, state) => const RoutesScreen(),
          ),
          GoRoute(
            path: '/routes/detail/:routeId',
            builder: (context, state) => RouteDetailsScreen(
              routeId: state.pathParameters['routeId']!,
            ),
          ),
          GoRoute(
            path: '/routes/detail/:routeId/weather',
            builder: (context, state) => RouteWeatherScreen(
              routeId: state.pathParameters['routeId']!,
            ),
          ),
          GoRoute(
            path: '/trips',
            builder: (context, state) => const GroupHikesScreen(),
            routes: [
              GoRoute(
                path: 'detail/:tripId',
                builder: (context, state) => TripDetailScreen(
                  tripId: state.pathParameters['tripId']!,
                ),
              ),
              GoRoute(
                path: 'chat/:tripId',
                builder: (context, state) {
                  final tripId = state.pathParameters['tripId']!;
                  final title = state.uri.queryParameters['title'] ?? 'Похід';
                  return TripChatScreen(
                    tripId: tripId,
                    tripTitle: title,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/navigation',
            builder: (context, state) => NavigationScreen(
              routeIdToFollow: state.uri.queryParameters['routeId'],
            ),
          ),
          GoRoute(
            path: '/weather',
            builder: (context, state) => const WeatherScreen(),
          ),
          GoRoute(
            path: '/journal',
            builder: (context, state) => const JournalScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/profile/my-routes',
            builder: (context, state) => const MyRoutesScreen(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (context, state) => const StatisticsScreen(),
          ),
          GoRoute(
            path: '/edit-profile',
            builder: (context, state) => const EditProfileScreen(),
          ),
          GoRoute(
            path: '/achievements',
            builder: (context, state) => const AchievementsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
