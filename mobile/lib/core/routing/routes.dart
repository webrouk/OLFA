/// Route map: the 26 core screens plus the location step, Archive /
/// Unmatched and the consultation screens (C1–C6). Paths are stable identifiers used by
/// deep links, push notifications and analytics — do not rename casually.
abstract final class Routes {
  // 1. Authentication & onboarding (6)
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const language = '/language';
  static const phone = '/auth/phone';
  static const otp = '/auth/otp';
  static const age = '/auth/age';

  // 2. Profile setup (5)
  static const gender = '/setup/gender';
  static const accountType = '/setup/account-type'; // member · psychologist · family counselor
  static const professionalInfo = '/setup/professional'; // "about you" for professionals
  static const profileInfo = '/setup/info';
  static const preferences = '/setup/preferences';
  static const photos = '/setup/photos';
  static const verification = '/setup/verification';
  static const location = '/setup/location';

  // 3. Discovery (6) — tabs live inside the floating-nav shell
  static const discover = '/discover';
  static const profileDetails = '/discover/profile/:id';
  static const search = '/discover/search';
  static const likes = '/likes';
  static const matches = '/matches';
  static const myProfile = '/me';

  // 4. Communication (3)
  static const conversations = '/messages';
  static const chat = '/messages/:conversationId';
  static const archive = '/messages/archive'; // registered before [chat]
  static const unmatched = '/messages/unmatched';
  static const notifications = '/notifications';

  // 5. Account & services (6)
  static const editProfile = '/me/edit';
  static const plans = '/me/plans';
  static const payments = '/me/payments';
  static const privacy = '/me/privacy';
  static const help = '/me/help';
  static const settings = '/me/settings';
  static const devices = '/me/privacy/devices';
  static const blockedUsers = '/me/privacy/blocked';
  static const languageSettings = '/me/settings/language';
  static const terms = '/legal/terms';
  static const privacyPolicy = '/legal/privacy';
  static const frozen = '/account/frozen';

  // 6. Family & marital consultations
  static const consultations = '/consultations';
  static const myConsultations = '/consultations/mine';
  static const counselor = '/consultations/counselor/:id';
  static const book = '/consultations/counselor/:id/book';
  static const counselorApply = '/counselor/apply';
  static const reviewConsultationPath = '/consultations/:id/review'; // mandatory questionnaire

  // 7. Professional workspace (psychologist / family counselor accounts) — floating-nav tabs
  static const counselorDesk = '/counselor/desk';
  static const wallet = '/counselor/wallet';
  static const proMessages = '/counselor/messages';
  static const proProfile = '/counselor/profile';
  static const payoutMethods = '/counselor/wallet/payout-methods';
  static const withdrawals = '/counselor/wallet/withdrawals';
  static const professionalPolicy = '/legal/professional';

  /// Marriage-only areas a professional account never reaches (router redirect;
  /// the server refuses them too).
  static bool memberOnly(String loc) =>
      loc.startsWith('/discover') || loc.startsWith('/likes') || loc.startsWith('/matches') || loc == myProfile || loc == conversations ||
      loc == editProfile || loc == plans || loc == preferences || loc == profileInfo || loc == archive || loc == unmatched ||
      loc.startsWith('/consultations');

  /// The professional workspace (members are sent to Discover).
  static bool professionalOnly(String loc) => loc.startsWith('/counselor/') || loc == professionalInfo;

  static String reviewConsultation(String id) => '/consultations/$id/review';

  static String counselorDetails(String id) => '/consultations/counselor/$id';
  static String bookCounselor(String id) => '/consultations/counselor/$id/book';
  static String profile(String id) => '/discover/profile/$id';
  static String chatWith(String conversationId) => '/messages/$conversationId';
}
