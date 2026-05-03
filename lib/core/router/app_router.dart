import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/routes/presentation/routes_screen.dart';
import '../../features/routes/presentation/route_details_screen.dart';
import '../../features/routes/presentation/route_weather_screen.dart';
import '../../features/navigation/presentation/navigation_screen.dart';
import '../../features/group_hikes/presentation/group_hikes_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/weather/presentation/weather_screen.dart';
import '../../features/profile/presentation/achievements_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../shell/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
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
