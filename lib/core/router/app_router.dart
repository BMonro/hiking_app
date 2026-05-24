import 'dart:async';

import '../logging/app_log.dart';
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
import '../../features/profile/presentation/notifications_screen.dart';
import '../shell/main_shell.dart';

String? _profileCheckedUserId;
bool _profilePhysicalComplete = false;

void _resetProfileCheckCache() {
  _profileCheckedUserId = null;
  _profilePhysicalComplete = false;
}

Future<bool> _needsPhysicalProfile(String userId) async {
  if (_profileCheckedUserId == userId && _profilePhysicalComplete) {
    return false;
  }

  final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
  if (meta?['onboarding_complete'] == true) {
    _profileCheckedUserId = userId;
    _profilePhysicalComplete = true;
    return false;
  }

  try {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('age')
        .eq('id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 3));
    final needs = profile == null || profile['age'] == null;
    _profileCheckedUserId = userId;
    _profilePhysicalComplete = !needs;
    return needs;
  } catch (_) {
    if (_profileCheckedUserId == userId) {
      return !_profilePhysicalComplete;
    }

    return true;
  }
}

class AuthSessionRefreshNotifier extends ChangeNotifier {
  AuthSessionRefreshNotifier() {
    _subscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut) {
        _resetProfileCheckCache();
      }
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
          final onOAuthStep =
              state.uri.queryParameters['oauth'] == '1';
          if (isRegisterRoute && onOAuthStep) return null;
          return '/register?oauth=1';
        }

        if (!needsPhysical) {
          if (isRegisterRoute || isLoginRoute) return '/home';
        }

        return null;
      } catch (e, st) {
        appLog('GoRouter redirect error', e, st);
        if (Supabase.instance.client.auth.currentSession != null) {
          return null;
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
              forceOfflineNavigation:
                  state.uri.queryParameters['offline'] == 'true',
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
          GoRoute(
            path: '/notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
        ],
      ),
    ],
  );
});
