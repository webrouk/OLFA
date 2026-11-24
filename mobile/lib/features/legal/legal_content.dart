/// Terms of Use and Privacy Policy shown in the app (screens + links from
/// sign-up, settings, plans and help). Written to cover what the App Store
/// Review Guidelines (1.2 user-generated content, 3.1.2 subscriptions, 5.1.1
/// data collection & in-app account deletion) and Google Play policies
/// (User Data, Data safety, Account deletion, Dating apps, Subscriptions)
/// require an app like OLFA to disclose. The version is stored with the
/// user's acceptance (kTermsVersion). Have counsel review before release.
library;

import 'legal_content_fr.dart';

const kLegalVersion = '2026-11';

class LegalSection {
  const LegalSection(this.title, this.body);
  final String title;
  final String body;
}

class LegalDoc {
  const LegalDoc({required this.title, required this.updated, required this.intro, required this.sections});
  final String title;
  final String updated;
  final String intro;
  final List<LegalSection> sections;
}

/// Arabic, English or French; any other language gets English.
LegalDoc termsOf(String lang) => switch (lang) { 'ar' => _termsAr, 'fr' => termsFr, _ => _termsEn };
LegalDoc privacyOf(String lang) => switch (lang) { 'ar' => _privacyAr, 'fr' => privacyFr, _ => _privacyEn };
LegalDoc professionalPolicyOf(String lang) => switch (lang) { 'ar' => _proAr, 'fr' => professionalPolicyFr, _ => _proEn };

// ───────────────────────────── Terms (EN) ─────────────────────────────
const _termsEn = LegalDoc(
  title: 'Terms of Use',
  updated: 'Last updated: November 2026 · Version 2026-11',
  intro:
      'OLFA is a community for adults who are looking for a serious relationship with marriage in mind. By creating an account you agree to these Terms and to our Privacy Policy. If you do not agree, please do not use OLFA.',
  sections: [
    LegalSection('1. Who can use OLFA',
        '• You must be at least 18 years old (or the age of majority where you live, if higher).\n• You may have only one account, registered with a phone number you own.\n• You must not be prohibited from using the service by law, and you must not have been removed from OLFA before.\n• You confirm that you are seeking a serious relationship and are legally able to marry where you live.'),
    LegalSection('2. Account types',
        'When you sign up you choose one account type, which cannot be changed later: a member looking for marriage, a psychologist, or a family counselor. Professional accounts never appear in discovery, cannot like or match, and use the counselor workspace (requests, wallet, chats with clients) under the Professional Policy. A person who is both looks for marriage with a member account and offers consultations with a separate professional account.'),
    LegalSection('2a. Your account',
        '• Keep your login secure; you are responsible for activity on your account.\n• You can see and sign out of your devices in Privacy & Security › Signed-in devices.\n• Information you provide must be true and current. Photos must show you and you must have the right to use them.'),
    LegalSection('3. Community rules — zero tolerance',
        'OLFA has zero tolerance for objectionable content and abusive users. You must not:\n• harass, threaten, insult, stalk or discriminate against anyone;\n• post nudity, sexual, violent or hateful content, or content involving minors;\n• impersonate anyone or create fake profiles;\n• share contact details, links or payment requests in your bio, or solicit money;\n• advertise, sell, spam, or use the service for commercial purposes;\n• use bots, scrapers or other automated access;\n• use the service for anything illegal.\nEvery profile and photo is reviewed before it is shown. You can report or block any member from their profile or chat; reports are reviewed by our team, usually within 24 hours, and we remove content and accounts that break these rules.'),
    LegalSection('4. Your content',
        'You keep ownership of what you post. You give OLFA a limited, non-exclusive, worldwide licence to host, display and process it only to operate and improve the service (for example, to show your profile to compatible members). The licence ends when your content or account is deleted, except for copies we must keep by law or for safety (see the Privacy Policy).'),
    LegalSection('5. Matching, messages and safety',
        '• Profiles are shown only to members whose preferences match yours and vice versa.\n• We do not run criminal background checks and cannot guarantee anyone\'s identity or intentions. Verification badges mean only what they describe.\n• Meet in public places, tell someone you trust, never send money, and report anything suspicious.\n• Conversations with no messages for 15 days are removed from your list (we remind you after 10 days); archived conversations are kept for 30 days; unmatched conversations are deleted after 30 days. One re-match request is allowed per conversation.'),
    LegalSection('6. Subscriptions and in-app purchases',
        '• OLFA Plus and Premium are auto-renewing subscriptions bought through the App Store or Google Play. Payment is charged to your store account at confirmation of purchase.\n• Moving up to Premium takes effect immediately (the store credits the unused part of the current period). Moving down to Plus takes effect at your next renewal date; you keep Premium until then.\n• If a renewal payment fails, the store retries it; during the store\'s grace period you keep your plan, after that it is paused until the payment is fixed.\n• Restore purchases (on the Plans screen) re-links an active subscription bought with the same App Store or Google Play account.\n• A subscription renews automatically unless auto-renew is turned off at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours before the end of the period.\n• You can manage or cancel subscriptions in your App Store or Google Play account settings. Deleting the app or your account does not cancel a store subscription.\n• Prices are shown in the app before purchase. Refunds are handled by Apple or Google under their policies.\n• Plan limits (likes, conversation starters, visible conversations, compliments) are shown in the app and enforced by our servers.'),
    LegalSection('7. Family consultations',
        'Consultations are a person-to-person service between you and an independent licensed counselor. You pay before the request is sent; if the counselor declines, or you cancel before confirmation, you are refunded in full. OLFA keeps a 15% platform commission on each consultation; the rest is the counselor\'s. After each completed session you answer a short questionnaire about its quality and about any attempt to move sessions or payments outside OLFA; you need to answer it before booking again, and your answers are confidential. Never pay a counselor outside OLFA — payments outside the app are not protected. Counselors are reviewed but are responsible for their own professional advice. Consultations are not emergency or medical care — in an emergency, contact local emergency services.'),
    LegalSection('8. Freezing or deleting your account',
        '• Freeze (take a break): your profile is hidden from everyone and your data, matches, chats and subscription are kept until you return.\n• Delete: from Settings › Delete account. Your account is hidden immediately and permanently deleted after 30 days; signing in during that time cancels the deletion.'),
    LegalSection('9. Suspension and termination',
        'We may restrict, suspend or remove accounts that break these Terms or the law, or that put members at risk. Serious or repeated violations — including professionals moving clients or payments outside OLFA — can lead to a permanent ban after a fair review in which the account holder is told what was found and can respond. A permanently banned person may not open a new account; to enforce this we keep one-way hashes of the phone number, device, licence and payout account of the banned account (never the values themselves). You can contact support from Help & support to ask about or appeal a decision.'),
    LegalSection('10. Disclaimers and liability',
        'OLFA is provided "as is". To the extent permitted by law, we are not liable for the conduct of members on or off the service, or for indirect or consequential losses. Nothing in these Terms limits rights you have under consumer law that cannot be excluded.'),
    LegalSection('11. Changes',
        'If we change these Terms in a material way, we will tell you in the app and ask you to accept the new version before continuing.'),
    LegalSection('12. Contact', 'Questions about these Terms: Settings › Help & support › Contact us.'),
  ],
);

// ───────────────────────────── Terms (AR) ─────────────────────────────
const _termsAr = LegalDoc(
  title: 'شروط الاستخدام',
  updated: 'آخر تحديث: نوفمبر 2026 · الإصدار 2026-11',
  intro:
      'ألفة مجتمع للبالغين الباحثين عن علاقة جادة بهدف الزواج. بإنشاء حساب فإنك توافق على هذه الشروط وعلى سياسة الخصوصية. إن لم توافق، يُرجى عدم استخدام ألفة.',
  sections: [
    LegalSection('1. من يمكنه استخدام ألفة',
        '• يجب ألا يقل عمرك عن 18 عامًا (أو سن الرشد في بلدك إن كان أعلى).\n• حساب واحد فقط لكل شخص، مسجّل برقم هاتف تملكه.\n• ألا يكون استخدامك للخدمة محظورًا قانونًا، وألا يكون حسابك قد أُزيل من ألفة سابقًا.\n• تؤكد أنك تبحث عن علاقة جادة وأنه يحق لك الزواج قانونًا حيث تقيم.'),
    LegalSection('2. أنواع الحسابات',
        'عند التسجيل تختار نوع حساب واحدًا لا يمكن تغييره لاحقًا: عضو يبحث عن الزواج، أو مختص نفسي، أو استشاري أسري. حسابات المختصين لا تظهر في الاستكشاف ولا يمكنها الإعجاب أو التوافق، وتستخدم لوحة المستشار (الطلبات، المحفظة، محادثات العملاء) وفق سياسة المختصين. ومن كان الاثنين معًا يبحث عن الزواج بحساب عضو ويقدّم الاستشارات بحساب مختص منفصل.'),
    LegalSection('2أ. حسابك',
        '• حافظ على أمان تسجيل دخولك، فأنت مسؤول عن النشاط على حسابك.\n• يمكنك رؤية أجهزتك وتسجيل الخروج منها من «الخصوصية والأمان › الأجهزة المتصلة».\n• يجب أن تكون معلوماتك صحيحة ومحدّثة، وأن تكون الصور لك ولديك حق استخدامها.'),
    LegalSection('3. قواعد المجتمع — عدم التسامح مطلقًا',
        'لا تتسامح ألفة مطلقًا مع المحتوى المسيء أو المستخدمين المسيئين. يُمنع:\n• التحرش أو التهديد أو الإهانة أو الملاحقة أو التمييز ضد أي شخص؛\n• نشر محتوى عارٍ أو جنسي أو عنيف أو يحض على الكراهية أو يتعلق بقاصرين؛\n• انتحال شخصية أي أحد أو إنشاء ملفات مزيفة؛\n• وضع بيانات تواصل أو روابط أو طلبات أموال في النبذة، أو طلب المال من أي عضو؛\n• الإعلان أو البيع أو الرسائل المزعجة أو الاستخدام التجاري؛\n• استخدام الروبوتات أو أدوات الجمع الآلي؛\n• استخدام الخدمة لأي غرض غير قانوني.\nتُراجع كل الملفات والصور قبل ظهورها. يمكنك الإبلاغ عن أي عضو أو حظره من ملفه أو المحادثة، ويراجع فريقنا البلاغات عادةً خلال 24 ساعة، ونزيل المحتوى والحسابات المخالفة.'),
    LegalSection('4. المحتوى الخاص بك',
        'تبقى ملكية ما تنشره لك. وتمنح ألفة ترخيصًا محدودًا وغير حصري وعالميًا لاستضافته وعرضه ومعالجته فقط لتشغيل الخدمة وتحسينها (مثل عرض ملفك على الأعضاء المتوافقين). ينتهي الترخيص بحذف المحتوى أو الحساب، إلا ما يلزم الاحتفاظ به قانونًا أو للسلامة (انظر سياسة الخصوصية).'),
    LegalSection('5. التوافق والرسائل والسلامة',
        '• لا يظهر ملفك إلا لمن تتوافق تفضيلاته مع تفضيلاتك والعكس.\n• لا نُجري فحوصًا جنائية ولا نضمن هوية أي شخص أو نواياه، وتعني شارات التحقق ما تصفه فقط.\n• التقِ في أماكن عامة، وأخبر شخصًا تثق به، ولا ترسل المال أبدًا، وأبلغ عن أي أمر مريب.\n• تُزال من قائمتك المحادثات التي لا تُرسل فيها رسائل لمدة 15 يومًا (مع تذكير بعد 10 أيام)، وتبقى المحادثات المؤرشفة 30 يومًا، وتُحذف محادثات إلغاء التطابق بعد 30 يومًا. يُسمح بطلب إعادة تطابق واحد لكل محادثة.'),
    LegalSection('6. الاشتراكات والمشتريات داخل التطبيق',
        '• «ألفة بلس» و«بريميوم» اشتراكات تتجدد تلقائيًا عبر App Store أو Google Play، ويُخصم المبلغ من حسابك في المتجر عند تأكيد الشراء.\n• الترقية إلى بريميوم تسري فورًا (ويحتسب المتجر الجزء غير المستخدم من الفترة الحالية)، والتخفيض إلى بلس يسري في تاريخ التجديد القادم وتبقى على بريميوم حتى ذلك الحين.\n• إذا تعذّر تحصيل التجديد يعيد المتجر المحاولة؛ وخلال فترة السماح لدى المتجر تبقى خطتك فعّالة، وبعدها تتوقف حتى يُصلح الدفع.\n• «استعادة المشتريات» في صفحة الخطط تعيد ربط اشتراك فعّال اشتريته بحساب App Store أو Google Play نفسه.\n• يتجدد الاشتراك تلقائيًا ما لم يُوقف التجديد التلقائي قبل 24 ساعة على الأقل من نهاية الفترة الحالية، ويُخصم التجديد خلال الـ24 ساعة السابقة لنهاية الفترة.\n• يمكنك إدارة الاشتراك أو إلغاؤه من إعدادات حسابك في App Store أو Google Play. حذف التطبيق أو الحساب لا يلغي اشتراك المتجر.\n• تُعرض الأسعار في التطبيق قبل الشراء، وتتولى Apple أو Google طلبات الاسترداد وفق سياساتهما.\n• حدود الخطط (الإعجابات، بدء المحادثات، المحادثات الظاهرة، رسائل الإطراء) معروضة في التطبيق ويطبقها خادمنا.'),
    LegalSection('7. الاستشارات الأسرية',
        'الاستشارة خدمة مباشرة بينك وبين استشاري مرخّص مستقل. تدفع قبل إرسال الطلب، وإذا اعتذر الاستشاري أو ألغيت قبل التأكيد يُسترد المبلغ كاملًا. تحتفظ ألفة بعمولة 15% من قيمة كل استشارة والباقي للاستشاري. بعد كل جلسة مكتملة تجيب عن استبيان قصير عن جودتها وعن أي محاولة لنقل الجلسات أو الدفع خارج ألفة، ويلزم إكماله قبل الحجز مرة أخرى، وإجاباتك سرية. لا تدفع لأي استشاري خارج ألفة — المدفوعات خارج التطبيق غير محمية. تتم مراجعة الاستشاريين لكنهم مسؤولون عن مشورتهم المهنية. الاستشارات ليست رعاية طارئة أو طبية — في الطوارئ تواصل مع خدمات الطوارئ المحلية.'),
    LegalSection('8. تجميد الحساب أو حذفه',
        '• التجميد (أخذ استراحة): يُخفى ملفك عن الجميع وتبقى بياناتك وتوافقاتك ومحادثاتك واشتراكك كما هي حتى تعود.\n• الحذف: من «الإعدادات › حذف الحساب». يُخفى الحساب فورًا ويُحذف نهائيًا بعد 30 يومًا، وتسجيل الدخول خلال هذه المدة يلغي الحذف.'),
    LegalSection('9. التقييد والإيقاف',
        'قد نقيّد أو نوقف أو نزيل الحسابات المخالفة لهذه الشروط أو للقانون أو التي تعرّض الأعضاء للخطر. المخالفات الجسيمة أو المتكررة — ومنها نقل المختصين للعملاء أو المدفوعات خارج ألفة — قد تؤدي إلى حظر نهائي بعد مراجعة عادلة يُبلَّغ فيها صاحب الحساب بما وُجد ويُمنح فرصة الرد. ولا يجوز لمن حُظر نهائيًا فتح حساب جديد؛ ولتطبيق ذلك نحتفظ بقيم مجزأة أحادية الاتجاه لرقم الهاتف والجهاز والترخيص وحساب التحويل الخاصة بالحساب المحظور (وليس القيم نفسها). يمكنك مراسلة الدعم من «المساعدة والدعم» للاستفسار عن أي قرار أو التظلم منه.'),
    LegalSection('10. إخلاء المسؤولية',
        'تُقدَّم ألفة «كما هي». وفي حدود ما يسمح به القانون، لا نتحمل المسؤولية عن سلوك الأعضاء داخل الخدمة أو خارجها، ولا عن الخسائر غير المباشرة. لا يحدّ أي شيء في هذه الشروط من حقوقك التي يكفلها قانون حماية المستهلك ولا يجوز استبعادها.'),
    LegalSection('11. التعديلات', 'إذا عدّلنا هذه الشروط تعديلًا جوهريًا فسنخبرك داخل التطبيق ونطلب موافقتك على الإصدار الجديد قبل المتابعة.'),
    LegalSection('12. التواصل', 'للاستفسار عن هذه الشروط: الإعدادات › المساعدة والدعم › تواصل معنا.'),
  ],
);

// ───────────────────────────── Privacy (EN) ─────────────────────────────
const _privacyEn = LegalDoc(
  title: 'Privacy Policy',
  updated: 'Last updated: November 2026 · Version 2026-11',
  intro:
      'This policy explains what OLFA collects, why, who it is shared with, how long it is kept, and the choices you have. We do not sell your personal data and we do not use it for third-party advertising.',
  sections: [
    LegalSection('1. What we collect',
        '• Account: phone number (verified by SMS code), device identifier and type, app version, language and time zone, and your account type (member or professional).\n• Profile: name, date of birth, gender, country of residence, nationality, city, marital status, education, occupation, height and weight (optional), marriage timeline, bio, interests, photos and partner preferences.\n• Religion and sect (only with your explicit consent): you can choose "Prefer not to say". They are shown on your profile and used only as filters that you or other members set; they never affect compatibility scores.\n• Professionals: payout account details, sealed with encryption and readable only by our finance team when they send a payout; your earnings ledger.\n• Consultation questionnaires: your answers after each session, kept confidential and used only for quality and to protect clients.\n• Approximate location (only if you allow it): rounded to about 1 km to show nearby members first. Others see only an approximate distance — never your location.\n• Activity: likes, passes, matches, messages, compliments, reports and blocks.\n• Purchases: subscription status from Apple or Google; for consultations, payment status from our payment provider (we never receive or store full card numbers).\n• Counselors: licence details and documents, kept private and seen only by our review team.\n• Technical: hashed IP address, crash and performance data, and security logs.'),
    LegalSection('2. Why we use it',
        'To create and secure your account; to show your profile only to compatible members; to run discovery, matching, chat and consultations; to enforce plan limits; to review profiles and photos and keep the community safe; to prevent fraud and abuse; to send notifications you can control; and to meet legal obligations. Sensitive details you choose to share (for example your religion or nationality) are used only to provide the service and are never sold.'),
    LegalSection('3. What other members see',
        'Your public profile: name, age, photos (after review), city and distance (unless you hide them), nationality, bio, interests and the details you add. Never your phone number, exact birth date, exact location or account status. You control discovery visibility, incognito (Premium), blurred photos until match, online status and read receipts in Privacy & Security.'),
    LegalSection('4. Who we share it with',
        'Service providers acting on our instructions: cloud hosting and storage, SMS delivery, push notifications (Apple, Google Firebase), photo moderation tools, payment processing (Apple, Google, Stripe for consultations) and crash reporting. Authorities, only when required by law or to protect someone\'s safety. We do not share data with advertisers or data brokers.'),
    LegalSection('5. How long we keep it',
        '• Active account: while you use OLFA.\n• Conversations: removed from lists after 15 days without messages; archive 30 days; unmatched 30 days.\n• Frozen account: kept until you return or delete it.\n• Deleted account: hidden immediately and permanently deleted after 30 days, including photos and messages. We keep the minimum needed for legal, tax and safety reasons (for example payment records and records of serious violations) for as long as the law requires.\n• Permanently banned accounts: one-way hashes of the phone number, devices, licence and payout account are kept to block re-registration, for as long as the ban lasts.'),
    LegalSection('6. Your rights and choices',
        '• Access and export: Privacy & Security › Download my data.\n• Correct: edit your profile at any time.\n• Delete: Settings › Delete account (in the app — no email needed).\n• Freeze instead of delete: keep everything and take a break.\n• Withdraw location permission or notifications in your device settings.\n• Contact us to object to or restrict processing where the law gives you that right.'),
    LegalSection('7. Security',
        'Data is encrypted in transit; tokens are stored in the device\'s secure storage; verification codes and secrets are stored only as hashes; original photos are kept private and only reviewed copies are published. No system is perfectly secure — tell us right away if you think your account is at risk.'),
    LegalSection('8. Children', 'OLFA is for adults only. We do not knowingly collect data from anyone under 18 and remove such accounts when we find them.'),
    LegalSection('9. International transfers', 'Your data may be processed in countries other than yours, with safeguards required by applicable law.'),
    LegalSection('10. Changes', 'We will tell you in the app before material changes take effect.'),
    LegalSection('11. Contact', 'Privacy questions and requests: Settings › Help & support › Contact us.'),
  ],
);

// ───────────────────────────── Privacy (AR) ─────────────────────────────
const _privacyAr = LegalDoc(
  title: 'سياسة الخصوصية',
  updated: 'آخر تحديث: نوفمبر 2026 · الإصدار 2026-11',
  intro:
      'توضح هذه السياسة ما تجمعه ألفة ولماذا، ومع من تُشارك البيانات، ومدة الاحتفاظ بها، والخيارات المتاحة لك. لا نبيع بياناتك الشخصية ولا نستخدمها للإعلانات الخارجية.',
  sections: [
    LegalSection('1. ما نجمعه',
        '• الحساب: رقم الهاتف (يُتحقق منه برمز SMS)، ومعرّف الجهاز ونوعه، وإصدار التطبيق، واللغة والمنطقة الزمنية، ونوع حسابك (عضو أو مختص).\n• الملف الشخصي: الاسم، وتاريخ الميلاد، والجنس، ودولة الإقامة، والجنسية، والمدينة، والحالة الاجتماعية، والتعليم، والمهنة، والطول والوزن (اختياريان)، وموعد الزواج، والنبذة، والاهتمامات، والصور، وتفضيلات الشريك.\n• الديانة والطائفة (بموافقتك الصريحة فقط): يمكنك اختيار «أفضّل عدم الإفصاح». تظهر في ملفك وتُستخدم فقط كفلاتر تحددها أنت أو الأعضاء الآخرون، ولا تؤثر في نسبة التوافق أبدًا.\n• المختصون: بيانات حساب التحويل مشفّرة ولا يطّلع عليها إلا فريق المالية عند تنفيذ التحويل، وسجل الأرباح.\n• استبيانات الاستشارات: إجاباتك بعد كل جلسة، تبقى سرية وتُستخدم للجودة وحماية العملاء فقط.\n• الموقع التقريبي (عند سماحك فقط): مقرّب إلى نحو 1 كم لعرض الأقرب إليك أولًا، ولا يرى الآخرون إلا مسافة تقريبية — لا موقعك أبدًا.\n• النشاط: الإعجابات، والتجاوزات، والتوافقات، والرسائل، ورسائل الإطراء، والبلاغات، والحظر.\n• المشتريات: حالة الاشتراك من Apple أو Google، وللاستشارات حالة الدفع من مزود الدفع (لا نستلم أرقام البطاقات ولا نخزنها).\n• الاستشاريون: بيانات الترخيص ومستنداته، تُحفظ بشكل خاص ولا يراها إلا فريق المراجعة.\n• بيانات تقنية: عنوان IP مُشفّر بدالة تجزئة، وبيانات الأعطال والأداء، وسجلات الأمان.'),
    LegalSection('2. لماذا نستخدمها',
        'لإنشاء حسابك وحمايته؛ ولعرض ملفك على المتوافقين فقط؛ ولتشغيل الاستكشاف والتوافق والمحادثة والاستشارات؛ ولتطبيق حدود الخطط؛ ولمراجعة الملفات والصور والحفاظ على سلامة المجتمع؛ ولمنع الاحتيال وإساءة الاستخدام؛ ولإرسال الإشعارات التي تتحكم بها؛ وللوفاء بالالتزامات القانونية. التفاصيل الحساسة التي تختار مشاركتها (مثل الجنسية) تُستخدم لتقديم الخدمة فقط ولا تُباع أبدًا.'),
    LegalSection('3. ما يراه الأعضاء الآخرون',
        'ملفك العام: الاسم، والعمر، والصور (بعد المراجعة)، والمدينة والمسافة (ما لم تخفهما)، والجنسية، والنبذة، والاهتمامات والتفاصيل التي تضيفها. ولا يرون أبدًا رقم هاتفك أو تاريخ ميلادك الدقيق أو موقعك الدقيق أو حالة حسابك. وتتحكم من «الخصوصية والأمان» بالظهور في الاستكشاف، والتصفح الخفي (بريميوم)، وتمويه الصور حتى التوافق، وحالة الاتصال، وإشعارات القراءة.'),
    LegalSection('4. مع من نشاركها',
        'مقدمو خدمات يعملون بتعليماتنا: الاستضافة والتخزين السحابي، وإرسال الرسائل النصية، والإشعارات (Apple وGoogle Firebase)، وأدوات مراجعة الصور، ومعالجة المدفوعات (Apple وGoogle وStripe للاستشارات)، وتقارير الأعطال. والجهات الرسمية فقط عند الإلزام القانوني أو لحماية سلامة شخص ما. لا نشارك البيانات مع المعلنين أو وسطاء البيانات.'),
    LegalSection('5. مدة الاحتفاظ',
        '• الحساب النشط: طوال استخدامك لألفة.\n• المحادثات: تُزال من القائمة بعد 15 يومًا دون رسائل، والأرشيف 30 يومًا، ومحادثات إلغاء التطابق 30 يومًا.\n• الحساب المجمّد: يُحفظ حتى تعود أو تحذفه.\n• الحساب المحذوف: يُخفى فورًا ويُحذف نهائيًا بعد 30 يومًا بما في ذلك الصور والرسائل، ونحتفظ بالحد الأدنى اللازم قانونيًا وضريبيًا ولأغراض السلامة (مثل سجلات الدفع وسجلات المخالفات الجسيمة) للمدة التي يفرضها القانون.\n• الحسابات المحظورة نهائيًا: نحتفظ بقيم مجزأة أحادية الاتجاه لرقم الهاتف والأجهزة والترخيص وحساب التحويل لمنع إعادة التسجيل طوال مدة الحظر.'),
    LegalSection('6. حقوقك وخياراتك',
        '• الاطلاع والتنزيل: الخصوصية والأمان › تنزيل بياناتي.\n• التصحيح: عدّل ملفك في أي وقت.\n• الحذف: الإعدادات › حذف الحساب (من داخل التطبيق دون مراسلة).\n• التجميد بدلًا من الحذف: احتفظ بكل شيء وخذ استراحة.\n• سحب إذن الموقع أو الإشعارات من إعدادات جهازك.\n• تواصل معنا للاعتراض على المعالجة أو تقييدها حيث يكفل القانون ذلك.'),
    LegalSection('7. الأمان',
        'تُشفَّر البيانات أثناء النقل، وتُحفظ رموز الدخول في التخزين الآمن للجهاز، وتُخزَّن رموز التحقق والأسرار كقيم مجزأة فقط، وتبقى الصور الأصلية خاصة ولا يُنشر إلا ما تمت مراجعته. لا يوجد نظام آمن تمامًا — أخبرنا فورًا إن ظننت أن حسابك في خطر.'),
    LegalSection('8. القاصرون', 'ألفة للبالغين فقط. لا نجمع بيانات من هم دون 18 عامًا عن علم، ونزيل هذه الحسابات عند اكتشافها.'),
    LegalSection('9. نقل البيانات دوليًا', 'قد تُعالج بياناتك في دول غير دولتك مع الضمانات التي يفرضها القانون المعمول به.'),
    LegalSection('10. التعديلات', 'سنخبرك داخل التطبيق قبل سريان أي تعديل جوهري.'),
    LegalSection('11. التواصل', 'للاستفسارات والطلبات المتعلقة بالخصوصية: الإعدادات › المساعدة والدعم › تواصل معنا.'),
  ],
);

// ───────────────────────── Professional policy (EN) ─────────────────────────
const _proEn = LegalDoc(
  title: 'Professional Policy',
  updated: 'Last updated: November 2026 · Version 2026-11',
  intro:
      'This policy applies to psychologists and family counselors who offer consultations on OLFA. You accept it when you create your professional account; it is part of the Terms of Use.',
  sections: [
    LegalSection('1. The 15% commission',
        'OLFA keeps 15% of the price of every consultation. It funds the platform\'s development and operation, marketing, advertising, and promoting you to members looking for help. The split is fixed when the client pays and is shown on every request and in your wallet: client paid − 15% = your share.'),
    LegalSection('2. Your wallet and payouts',
        '• Your share is credited when you mark the session completed, then held for 7 days (refunds and disputes) before it can be withdrawn.\n• Withdraw to a bank account (IBAN or SWIFT) or to Wise, PayPal or Payoneer. The minimum is 50 units of the currency; one request per currency at a time.\n• Our finance team sends the transfer and records its reference. Bank or provider fees and currency conversion are set by your bank or provider.\n• Account details are encrypted; only a masked form is shown.'),
    LegalSection('3. Keep consultations on OLFA',
        'Do not share your phone number, email, social accounts, website or clinic details with clients you met on OLFA, do not ask for theirs, and do not invite them to book or pay outside OLFA. Contact details sent in a consultation chat are detected automatically and recorded. Follow-up sessions with clients you met on OLFA must be booked on OLFA.'),
    LegalSection('4. How we check — fairly',
        'After every completed session the client answers a confidential questionnaire about quality, commitment, results, whether another session was agreed, and whether you suggested continuing or paying outside OLFA. We look for patterns across several clients and consultations, never a single answer. When the evidence is consistent we open a review, tell you, and give you 7 days to respond before any decision. Payouts are held while a review is open.'),
    LegalSection('5. Decisions',
        'After the review a moderator decides: no action, a written warning, suspension, or a permanent ban for proven circumvention. You are told the outcome and the reason. Earnings already credited for completed sessions are settled according to the decision and applicable law.'),
    LegalSection('6. Permanent ban and re-registration',
        'A permanently banned professional may not open any new OLFA account. We keep one-way hashes of the phone number, devices, licence number and payout accounts of the banned account to enforce this, in line with our Privacy Policy and applicable law.'),
    LegalSection('7. Professional standards',
        'Keep your licence valid and your profile truthful, respect confidentiality, keep appointments, and refer clients to emergency services when needed. Consultations on OLFA are not emergency care.'),
  ],
);

// ───────────────────────── Professional policy (AR) ─────────────────────────
const _proAr = LegalDoc(
  title: 'سياسة المختصين',
  updated: 'آخر تحديث: نوفمبر 2026 · الإصدار 2026-11',
  intro: 'تنطبق هذه السياسة على المختصين النفسيين والاستشاريين الأسريين الذين يقدّمون الاستشارات عبر ألفة، وتوافق عليها عند إنشاء حسابك المهني، وهي جزء من شروط الاستخدام.',
  sections: [
    LegalSection('1. عمولة 15%',
        'تحتفظ ألفة بنسبة 15% من قيمة كل استشارة، وتُخصص لتطوير المنصة وتشغيلها، والتسويق، والإعلان، والترويج لك أمام الأعضاء الباحثين عن المساعدة. تُثبَّت القسمة لحظة دفع العميل وتظهر في كل طلب وفي محفظتك: ما دفعه العميل − 15% = صافي مستحقاتك.'),
    LegalSection('2. المحفظة والسحب',
        '• تُضاف مستحقاتك عند تعليم الجلسة كمكتملة، وتبقى 7 أيام (لفترة الاسترداد والاعتراض) قبل أن تصبح قابلة للسحب.\n• السحب إلى حساب بنكي (IBAN أو SWIFT) أو إلى Wise أو PayPal أو Payoneer، بحد أدنى 50 من وحدة العملة، وطلب واحد مفتوح لكل عملة.\n• ينفّذ فريق المالية التحويل ويسجّل مرجعه، وتحدد جهة التحويل رسومها وسعر الصرف.\n• بيانات الحساب مشفّرة ولا يظهر منها إلا شكل مخفي.'),
    LegalSection('3. أبقِ الاستشارات داخل ألفة',
        'لا تشارك رقم هاتفك أو بريدك أو حساباتك الاجتماعية أو موقعك أو بيانات عيادتك مع عملاء تعرّفت إليهم عبر ألفة، ولا تطلب بياناتهم، ولا تدعُهم للحجز أو الدفع خارج ألفة. تُرصد بيانات التواصل المرسلة في محادثات الاستشارة تلقائيًا وتُسجَّل. والجلسات اللاحقة مع عملاء ألفة تُحجز عبر ألفة.'),
    LegalSection('4. كيف نتحقق — بعدل',
        'بعد كل جلسة مكتملة يجيب العميل عن استبيان سري عن الجودة والالتزام والنتائج، وهل اتُّفق على جلسة أخرى، وهل اقترحت الاستمرار أو الدفع خارج ألفة. نبحث عن أنماط متكررة لدى أكثر من عميل واستشارة، لا عن إجابة واحدة. وعند اتساق الأدلة نفتح مراجعة ونبلغك بها ونمنحك 7 أيام للرد قبل أي قرار، وتُعلَّق التحويلات أثناء المراجعة.'),
    LegalSection('5. القرارات',
        'بعد المراجعة يقرر المشرف: لا إجراء، أو إنذار مكتوب، أو إيقاف، أو حظر نهائي عند ثبوت التحايل. نبلغك بالنتيجة وسببها. وتُسوّى المستحقات المضافة عن جلسات مكتملة وفق القرار والقانون المعمول به.'),
    LegalSection('6. الحظر النهائي ومنع إعادة التسجيل',
        'لا يجوز للمختص المحظور نهائيًا فتح أي حساب جديد في ألفة، ولتطبيق ذلك نحتفظ بقيم مجزأة أحادية الاتجاه لرقم الهاتف والأجهزة ورقم الترخيص وحسابات التحويل الخاصة بالحساب المحظور، بما يتوافق مع سياسة الخصوصية والقانون المعمول به.'),
    LegalSection('7. المعايير المهنية',
        'حافظ على سريان ترخيصك وصدق ملفك، واحترم السرية، والتزم بالمواعيد، ووجّه العملاء إلى خدمات الطوارئ عند الحاجة. الاستشارات عبر ألفة ليست رعاية طارئة.'),
  ],
);
