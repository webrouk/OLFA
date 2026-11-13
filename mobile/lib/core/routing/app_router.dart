import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/auth_screens.dart';
import '../../features/discovery/presentation/discover_screen.dart';
import '../../features/onboarding/presentation/onboarding_screens.dart';
import '../../features/profile/presentation/gender_screen.dart';
import '../../shared/components/in_progress_screen.dart';
import '../localization/generated/app_localizations.dart';
import '../widgets/floating_nav_bar.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Builds an "in progress" page whose title is localised at build time.
GoRouterWidgetBuilder _wip(String Function(AppLocalizations l) title, {bool back = true}) =>
    (context, state) => InProgressScreen(title: title(AppLocalizations.of(context)), showBack: back);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    // Phase 2: redirect by auth/account status (pending, rejected, active...).
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: Routes.language, builder: (_, __) => const LanguageScreen()),
      GoRoute(path: Routes.phone, builder: (_, __) => const PhoneScreen()),
      GoRoute(path: Routes.otp, builder: (_, s) => OtpScreen(phone: (s.extra as String?) ?? '')),
      GoRoute(path: Routes.age, builder: (_, __) => const AgeScreen()),
      GoRoute(path: Routes.gender, builder: (_, __) => const GenderScreen()),
      GoRoute(path: Routes.profileInfo, builder: _wip((l) => l.screenProfileInfo)),
      GoRoute(path: Routes.preferences, builder: _wip((l) => l.screenPreferences)),
      GoRoute(path: Routes.photos, builder: _wip((l) => l.screenPhotos)),
      GoRoute(path: Routes.verification, builder: _wip((l) => l.screenVerification)),

      // Full-screen routes pushed above the tab shell.
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.profileDetails, builder: _wip((l) => l.screenProfileDetails)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.search, builder: _wip((l) => l.screenSearch)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.chat, builder: _wip((l) => l.screenChat)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.notifications, builder: _wip((l) => l.screenNotifications)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.editProfile, builder: _wip((l) => l.screenEditProfile)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.plans, builder: _wip((l) => l.screenPlans)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.payments, builder: _wip((l) => l.screenPayments)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.privacy, builder: _wip((l) => l.screenPrivacy)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.help, builder: _wip((l) => l.screenHelp)),
      GoRoute(parentNavigatorKey: _rootKey, path: Routes.settings, builder: _wip((l) => l.screenSettings)),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.discover, builder: (_, __) => const DiscoverScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.likes, builder: _wip((l) => l.screenLikes, back: false))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.matches, builder: _wip((l) => l.screenMatches, back: false))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.conversations, builder: _wip((l) => l.screenConversations, back: false))]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.myProfile, builder: _wip((l) => l.screenMyProfile, back: false))]),
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
