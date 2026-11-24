import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_type.dart';
import '../../features/authentication/presentation/auth_screens.dart';
import '../../features/consultations/application/consultation_providers.dart';
import '../../features/consultations/presentation/review_screen.dart';
import '../../features/profile/presentation/account_type_screen.dart';
import '../../features/profile/presentation/professional_profile_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../../features/consultations/presentation/consultation_screens.dart';
import '../../features/discovery/presentation/discover_screen.dart';
import '../../features/discovery/presentation/search_filters_screen.dart';
import '../../features/legal/legal_screens.dart';
import '../../features/likes/presentation/likes_screen.dart';
import '../../features/location/presentation/location_screen.dart';
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
import '../../features/support/presentation/support_thread_screen.dart';
import '../../features/account/closed_account_screen.dart';
import '../../features/consultations/presentation/counselor_schedule_screen.dart';
import '../security/account_restriction.dart';
import '../../features/verification/presentation/selfie_screen.dart';
import '../widgets/floating_nav_bar.dart';
import '../../shared/models/models.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRoute _root(String path, Widget Function(GoRouterState s) build) =>
    GoRoute(parentNavigatorKey: rootNavigatorKey, path: path, builder: (_, s) => build(s));

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: Listenable.merge([accountTypeListenable, accountRestriction]),
    // Each account type only reaches its own area (the server enforces the same rule).
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // A closed account only sees the closed-account screen (and the legal pages).
      if (accountRestriction.value != null) {
        return loc == Routes.closed || loc.startsWith('/legal/') ? null : Routes.closed;
      }
      if (loc == Routes.closed) return Routes.splash;
      final type = ref.read(accountTypeProvider);
      if (type == null) return null;
      if (type.isProfessional && Routes.memberOnly(loc)) return Routes.counselorDesk;
      if (!type.isProfessional && Routes.professionalOnly(loc)) return Routes.discover;
      return null;
    },
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
      _root(Routes.accountType, (_) => const AccountTypeScreen()),
      _root(Routes.professionalInfo, (_) => const CounselorApplyScreen(setupMode: true)),
      _root(Routes.profileInfo, (_) => const ProfileInfoScreen()),
      _root(Routes.preferences, (_) => const PreferencesScreen()),
      _root(Routes.photos, (_) => const PhotosScreen()),
      _root(Routes.location, (_) => const LocationScreen()),
      _root(Routes.selfie, (_) => const SelfieScreen()),
      _root(Routes.selfieRetake, (_) => const SelfieScreen(retake: true)),
      _root(Routes.verification, (_) => const VerificationScreen()),
      // Full-screen pages pushed above the tab shell
      _root(Routes.profileDetails, (s) => ProfileDetailsScreen(userId: s.pathParameters['id']!)),
      _root(Routes.search, (_) => const SearchFiltersScreen()),
      _root(Routes.archive, (_) => const ArchiveScreen()),
      _root(Routes.unmatched, (_) => const UnmatchedScreen()),
      _root(Routes.chat, (s) => ChatScreen(conversationId: s.pathParameters['conversationId']!)),
      // F — Consultations (fixed paths before parameterised ones)
      _root(Routes.consultations, (_) => const ConsultationsScreen()),
      _root(Routes.myConsultations, (_) => const MyConsultationsScreen()),
      _root(Routes.book, (s) => BookConsultationScreen(counselorId: s.pathParameters['id']!)),
      _root(Routes.counselor, (s) => CounselorDetailsScreen(counselorId: s.pathParameters['id']!)),
      _root(Routes.counselorApply, (_) => const CounselorApplyScreen()),
      _root(Routes.reviewConsultationPath, (s) => ConsultationReviewScreen(consultationId: s.pathParameters['id']!, counselorName: s.extra as String?)),
      _root(Routes.payoutMethods, (_) => const PayoutMethodsScreen()),
      _root(Routes.withdrawals, (_) => const WithdrawalsScreen()),
      _root(Routes.professionalPolicy, (_) => const LegalScreen.professional()),
      _root(Routes.notifications, (_) => const NotificationsScreen()),
      _root(Routes.editProfile, (_) => const EditProfileScreen()),
      _root(Routes.plans, (_) => const PlansScreen()),
      _root(Routes.payments, (_) => const PaymentHistoryScreen()),
      _root(Routes.privacy, (_) => const PrivacyScreen()),
      _root(Routes.help, (_) => const HelpScreen()),
      _root(Routes.settings, (_) => const SettingsScreen()),
      _root(Routes.devices, (_) => const DevicesScreen()),
      _root(Routes.blockedUsers, (_) => const BlockedUsersScreen()),
      _root(Routes.languageSettings, (_) => const LanguageSettingsScreen()),
      _root(Routes.terms, (_) => const LegalScreen.terms()),
      _root(Routes.privacyPolicy, (_) => const LegalScreen.privacy()),
      _root(Routes.frozen, (_) => const FrozenAccountScreen()),
      _root(Routes.closed, (_) => const ClosedAccountScreen()),
      _root(Routes.newTicket, (_) => const NewTicketScreen()),
      _root(Routes.supportThread, (s) => SupportThreadScreen(ticketId: s.pathParameters['id']!)),
      _root(Routes.counselorSchedule, (_) => const CounselorScheduleScreen()),
      _root(Routes.counselorReviews, (_) => const CounselorReviewsScreen()),
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
      // Professional workspace: desk, wallet, messages (consultation chats), profile
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ProfessionalShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.counselorDesk, builder: (_, __) => const CounselorDeskScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.wallet, builder: (_, __) => const WalletScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.proMessages, builder: (_, __) => const ConversationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.proProfile, builder: (_, __) => const ProfessionalProfileScreen())]),
        ],
      ),
    ],
  );
});

/// Tab shell hosting the floating bottom navigation (marriage members).
/// Once per session it reminds a member of a consultation they still have to
/// review (the questionnaire is required before booking again).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

bool _reviewPrompted = false;

class _MainShellState extends ConsumerState<MainShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_reviewPrompted) return;
      _reviewPrompted = true;
      final pending = await ref.read(pendingReviewsProvider.future).catchError((Object _) => const <PendingReview>[]);
      if (pending.isNotEmpty && mounted) await promptPendingReview(context, pending.first);
    });
  }

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

/// Tab shell for psychologists and family counselors.
class ProfessionalShell extends StatelessWidget {
  const ProfessionalShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: FloatingNavBar(
        professional: true,
        index: shell.currentIndex,
        badges: const {0},
        onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
