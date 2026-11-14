import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/auth_screens.dart';
import '../../features/discovery/presentation/discover_screen.dart';
import '../../features/discovery/presentation/search_filters_screen.dart';
import '../../features/likes/presentation/likes_screen.dart';
import '../../features/matching/presentation/matches_screen.dart';
import '../../features/messaging/presentation/chat_screen.dart';
import '../../features/messaging/presentation/conversations_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/onboarding_screens.dart';
import '../../features/payments/presentation/payment_history_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/my_profile_screen.dart';
import '../../features/profile/presentation/profile_details_screen.dart';
import '../../features/profile/presentation/setup_screens.dart';
import '../../features/settings/presentation/privacy_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/subscriptions/presentation/plans_screen.dart';
import '../../features/support/presentation/help_screen.dart';
import '../widgets/floating_nav_bar.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRoute _root(String path, Widget Function(GoRouterState s) build) =>
    GoRoute(parentNavigatorKey: rootNavigatorKey, path: path, builder: (_, s) => build(s));

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    // Phase 3: redirect by session + account status (pending/rejected/active…).
    routes: [
      // A — Authentication & onboarding
      _root(Routes.splash, (_) => const SplashScreen()),
      _root(Routes.onboarding, (_) => const OnboardingScreen()),
      _root(Routes.language, (_) => const LanguageScreen()),
      _root(Routes.phone, (_) => const PhoneScreen()),
      _root(Routes.otp, (_) => const OtpScreen()),
      _root(Routes.age, (_) => const AgeScreen()),
      // B — Profile setup
      _root(Routes.gender, (_) => const GenderScreen()),
      _root(Routes.profileInfo, (_) => const ProfileInfoScreen()),
      _root(Routes.preferences, (_) => const PreferencesScreen()),
      _root(Routes.photos, (_) => const PhotosScreen()),
      _root(Routes.verification, (_) => const VerificationScreen()),
      // Full-screen pages pushed above the tab shell
      _root(Routes.profileDetails, (s) => ProfileDetailsScreen(userId: s.pathParameters['id']!)),
      _root(Routes.search, (_) => const SearchFiltersScreen()),
      _root(Routes.chat, (s) => ChatScreen(conversationId: s.pathParameters['conversationId']!)),
      _root(Routes.notifications, (_) => const NotificationsScreen()),
      _root(Routes.editProfile, (_) => const EditProfileScreen()),
      _root(Routes.plans, (_) => const PlansScreen()),
      _root(Routes.payments, (_) => const PaymentHistoryScreen()),
      _root(Routes.privacy, (_) => const PrivacyScreen()),
      _root(Routes.help, (_) => const HelpScreen()),
      _root(Routes.settings, (_) => const SettingsScreen()),
      // C/D — Tabs with the floating navigation
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.discover, builder: (_, __) => const DiscoverScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.likes, builder: (_, __) => const LikesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.matches, builder: (_, __) => const MatchesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.conversations, builder: (_, __) => const ConversationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.myProfile, builder: (_, __) => const MyProfileScreen())]),
        ],
      ),
    ],
  );
});

/// Tab shell hosting the floating bottom navigation.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavBar(
        index: shell.currentIndex,
        badges: const {1, 3},
        onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
