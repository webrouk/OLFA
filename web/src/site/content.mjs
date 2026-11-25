// Texts of the public website (sukna.online), in Arabic, English and French.
// Rules kept here on purpose: no store badges or "download now" until the app
// is actually published, no invented numbers, testimonials or contact details.

export const LANGS = ['ar', 'en', 'fr'];

export const site = {
  ar: {
    dir: 'rtl',
    name: 'أُلْفَة',
    metaTitle: 'أُلْفَة — للتعارف الجاد بنيّة الزواج',
    metaDesc: 'أُلْفَة مجتمع للبالغين الباحثين عن علاقة جادة بنيّة الزواج: حسابات موثّقة بصورة سيلفي، خصوصية أولاً، واستشارات مع مختصين.',
    nav: { how: 'كيف تعمل', safety: 'الأمان', experts: 'المختصون', faq: 'أسئلة', legal: 'السياسات' },
    hero: {
      kicker: 'تعارف جاد · بنيّة الزواج',
      title: 'تعارفٌ يبدأ بالاحترام،\nوينتهي بأُلْفَة.',
      body: 'تطبيق للبالغين الباحثين عن شريك حياة. كل حساب يمرّ بمراجعة وتحقّق بصورة سيلفي قبل ظهوره، والتواصل بإيقاع هادئ يحترم القيم والخصوصية.',
      status: 'التطبيق قيد الإعداد للإطلاق على iOS وAndroid — لم يُنشر في المتاجر بعد.',
    },
    pillars: [
      ['نيّة واضحة', 'الجميع هنا يبحث عن زواج. لا تصفّح عشوائي ولا علاقات عابرة.'],
      ['حسابات موثّقة', 'تحقّق بصورة سيلفي حيّة بإيماءة عشوائية بعد رفع الصور، ثم مراجعة من فريقنا.'],
      ['خصوصيتك أولاً', 'خيار إخفاء صورك حتى التوافق، وحماية من لقطات الشاشة، وحذف حسابك متاح من داخل التطبيق.'],
    ],
    how: {
      title: 'كيف تعمل أُلْفَة',
      steps: [
        ['أنشئ ملفك', 'رقم هاتفك، ثم صورك ونبذة صادقة عنك وعمّا تبحث عنه.'],
        ['تحقّق بصورة سيلفي', 'صورة حيّة بإيماءة نطلبها منك؛ تُراجع وفق ثمانية معايير مكتوبة، وتُحذف بعد 30 يومًا من القرار.'],
        ['أجب عن استبيان التوافق', 'أسئلة عن القيم ونمط الحياة والتوقعات من الزواج، تُستخدم لاقتراح الأنسب لك.'],
        ['تواصل باحترام', 'محادثة بعد الإعجاب المتبادل، مع خيار إخفاء صورك حتى التوافق، وإمكانية استشارة مختص متى شئت.'],
      ],
    },
    safety: {
      title: 'الأمان ليس ميزة إضافية',
      items: [
        ['مراجعة بشرية', 'كل ملف وصورة يُراجعان قبل الظهور، ومراجِعة أنثى عند الطلب لصورة السيلفي.'],
        ['بلاغ وحظر بضغطة', 'يمكنك الإبلاغ عن أي حساب أو رسالة، وفريقنا يتابع البلاغات بأولوية.'],
        ['حماية المحادثات', 'منع لقطات الشاشة على Android وإخفاء المحتوى عند التسجيل على iOS — مع العلم أن أي نظام لا يمنع تصوير الشاشة بكاميرا أخرى.'],
        ['قواعد واضحة', 'حظر مؤقت أو دائم لمن يخالف الشروط، مع حق التظلّم.'],
      ],
    },
    experts: {
      title: 'مختصون في العلاقات والإرشاد الأسري',
      body: 'احجز جلسة مع أخصائي نفسي أو مستشار أسري موثّق. رسوم الجلسة تبقى محجوزة ولا تُحوَّل للمختص إلا بعد تأكيدك حدوث الجلسة وتقييمها — وإن لم تتم يُفتح نزاع تراجعه الإدارة.',
    },
    faq: {
      title: 'أسئلة شائعة',
      items: [
        ['هل التطبيق متاح الآن؟', 'ليس بعد. نعمل على إطلاقه في App Store وGoogle Play، وسنعلن هنا عند توفّره.'],
        ['لمن أُلْفَة؟', 'للبالغين (18 عامًا فأكثر) الباحثين بجدية عن الزواج.'],
        ['هل التحقق بالسيلفي يعني التحقق من الهوية؟', 'لا. التحقق يؤكد أن صاحب الحساب شخص حقيقي يطابق صوره، ولا يُغني عن الحذر والتحقق الشخصي قبل أي ارتباط.'],
        ['كيف أحذف حسابي؟', 'من الإعدادات داخل التطبيق ← الحساب ← حذف الحساب. تفاصيل ما يُحذف ومتى في سياسة الخصوصية.'],
      ],
    },
    footer: { rights: 'جميع الحقوق محفوظة.', terms: 'شروط الاستخدام', privacy: 'سياسة الخصوصية', pro: 'سياسة المختصين', lang: 'اللغة' },
    back: 'العودة للرئيسية',
  },
  en: {
    dir: 'ltr',
    name: 'OLFA',
    metaTitle: 'OLFA — Serious dating with marriage in mind',
    metaDesc: 'OLFA is a community for adults looking for a serious relationship with marriage in mind: selfie-verified profiles, privacy first, and sessions with qualified counselors.',
    nav: { how: 'How it works', safety: 'Safety', experts: 'Counselors', faq: 'FAQ', legal: 'Policies' },
    hero: {
      kicker: 'Serious dating · Marriage in mind',
      title: 'Meeting that begins with respect,\nand grows into belonging.',
      body: 'An app for adults looking for a life partner. Every profile is reviewed and selfie-verified before it appears, and conversations move at a calm pace that respects values and privacy.',
      status: 'The app is being prepared for launch on iOS and Android — it is not in the stores yet.',
    },
    pillars: [
      ['Clear intentions', 'Everyone here is looking for marriage. No endless swiping, no casual flings.'],
      ['Verified profiles', 'A live selfie with a random gesture after your photos, then a review by our team.'],
      ['Privacy first', 'You can blur your photos until a match, screenshots are blocked, and you can delete your account inside the app.'],
    ],
    how: {
      title: 'How OLFA works',
      steps: [
        ['Create your profile', 'Your phone number, then your photos and an honest bio about you and what you are looking for.'],
        ['Verify with a selfie', 'A live photo with a gesture we ask for, reviewed against eight written criteria and deleted 30 days after the decision.'],
        ['Answer the compatibility questions', 'Values, lifestyle and expectations of marriage — used to suggest the people who suit you best.'],
        ['Connect respectfully', 'Chat after a mutual like, with the option to blur your photos until a match, and a counselor to talk to whenever you wish.'],
      ],
    },
    safety: {
      title: 'Safety is not an add-on',
      items: [
        ['Human review', 'Every profile and photo is reviewed before it appears, by a female reviewer on request for the selfie.'],
        ['Report and block in one tap', 'Report any profile or message; our team handles reports with priority.'],
        ['Protected conversations', 'Screenshots are blocked on Android and content is hidden during screen recording on iOS — no system can stop someone photographing a screen with another camera.'],
        ['Clear rules', 'Temporary or permanent bans for breaking the Terms, with the right to appeal.'],
      ],
    },
    experts: {
      title: 'Relationship and family counselors',
      body: 'Book a session with a verified psychologist or family counselor. The fee is held and only paid to the counselor after you confirm the session took place and rate it — if it did not happen, a dispute opens for our team to review.',
    },
    faq: {
      title: 'Questions',
      items: [
        ['Is the app available now?', 'Not yet. We are working on releasing it on the App Store and Google Play and will announce it here when it is available.'],
        ['Who is OLFA for?', 'Adults (18+) who are seriously looking for marriage.'],
        ['Is the selfie check an ID check?', 'No. It confirms the account belongs to a real person who matches their photos; it does not replace your own care and checks before any commitment.'],
        ['How do I delete my account?', 'In the app: Settings → Account → Delete account. What is deleted and when is described in the Privacy Policy.'],
      ],
    },
    footer: { rights: 'All rights reserved.', terms: 'Terms of Use', privacy: 'Privacy Policy', pro: 'Professional Policy', lang: 'Language' },
    back: 'Back to home',
  },
  fr: {
    dir: 'ltr',
    name: 'OLFA',
    metaTitle: 'OLFA — Des rencontres sérieuses en vue du mariage',
    metaDesc: 'OLFA est une communauté d’adultes qui cherchent une relation sérieuse en vue du mariage : profils vérifiés par selfie, confidentialité d’abord et séances avec des conseillers qualifiés.',
    nav: { how: 'Fonctionnement', safety: 'Sécurité', experts: 'Conseillers', faq: 'FAQ', legal: 'Politiques' },
    hero: {
      kicker: 'Rencontres sérieuses · En vue du mariage',
      title: 'Une rencontre qui commence par le respect,\net grandit en complicité.',
      body: 'Une application pour les adultes qui cherchent un partenaire de vie. Chaque profil est examiné et vérifié par selfie avant d’apparaître, et les échanges avancent à un rythme serein, respectueux des valeurs et de la vie privée.',
      status: 'L’application est en préparation pour iOS et Android — elle n’est pas encore dans les stores.',
    },
    pillars: [
      ['Des intentions claires', 'Ici, tout le monde cherche le mariage. Pas de swipe sans fin, pas d’aventures.'],
      ['Des profils vérifiés', 'Un selfie en direct avec un geste aléatoire après vos photos, puis un examen par notre équipe.'],
      ['La confidentialité d’abord', 'Vous pouvez flouter vos photos jusqu’à un intérêt mutuel, les captures d’écran sont bloquées et vous pouvez supprimer votre compte dans l’application.'],
    ],
    how: {
      title: 'Comment fonctionne OLFA',
      steps: [
        ['Créez votre profil', 'Votre numéro de téléphone, puis vos photos et une présentation sincère de vous et de ce que vous cherchez.'],
        ['Vérifiez-vous par selfie', 'Une photo en direct avec un geste demandé, examinée selon huit critères écrits et supprimée 30 jours après la décision.'],
        ['Répondez au questionnaire', 'Valeurs, mode de vie et attentes du mariage — pour vous proposer les personnes qui vous correspondent.'],
        ['Échangez avec respect', 'Discussion après un intérêt mutuel, avec l’option de flouter vos photos jusqu’à un intérêt mutuel, et un conseiller à consulter quand vous le souhaitez.'],
      ],
    },
    safety: {
      title: 'La sécurité n’est pas une option',
      items: [
        ['Examen humain', 'Chaque profil et chaque photo sont examinés avant d’apparaître, par une examinatrice sur demande pour le selfie.'],
        ['Signaler et bloquer en un geste', 'Signalez un profil ou un message ; notre équipe traite les signalements en priorité.'],
        ['Conversations protégées', 'Captures bloquées sur Android et contenu masqué pendant l’enregistrement d’écran sur iOS — aucun système n’empêche de photographier un écran avec un autre appareil.'],
        ['Des règles claires', 'Suspension temporaire ou définitive en cas de manquement aux conditions, avec droit de recours.'],
      ],
    },
    experts: {
      title: 'Des conseillers conjugaux et familiaux',
      body: 'Réservez une séance avec un psychologue ou un conseiller familial vérifié. Les frais sont retenus et versés au conseiller seulement après que vous avez confirmé et évalué la séance — si elle n’a pas eu lieu, un litige est ouvert et examiné par notre équipe.',
    },
    faq: {
      title: 'Questions fréquentes',
      items: [
        ['L’application est-elle disponible ?', 'Pas encore. Nous préparons sa sortie sur l’App Store et Google Play et l’annoncerons ici.'],
        ['À qui s’adresse OLFA ?', 'Aux adultes (18 ans et plus) qui cherchent sérieusement à se marier.'],
        ['Le selfie est-il une vérification d’identité ?', 'Non. Il confirme que le compte appartient à une personne réelle qui correspond à ses photos ; il ne remplace pas votre prudence avant tout engagement.'],
        ['Comment supprimer mon compte ?', 'Dans l’application : Réglages → Compte → Supprimer le compte. Ce qui est supprimé et quand est décrit dans la Politique de confidentialité.'],
      ],
    },
    footer: { rights: 'Tous droits réservés.', terms: 'Conditions d’utilisation', privacy: 'Politique de confidentialité', pro: 'Politique professionnelle', lang: 'Langue' },
    back: 'Retour à l’accueil',
  },
};

/** legal.json keys per page and language */
export const LEGAL = {
  terms: { ar: '_termsAr', en: '_termsEn', fr: 'termsFr' },
  privacy: { ar: '_privacyAr', en: '_privacyEn', fr: 'privacyFr' },
  professional: { ar: '_proAr', en: '_proEn', fr: 'professionalPolicyFr' },
};
