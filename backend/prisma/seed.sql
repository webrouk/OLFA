-- Reference data (idempotent). Not demo users: plans, entitlements, interests,
-- roles/permissions and system settings that the platform needs to run.

INSERT INTO subscription_plans (code, name_ar, name_en, sort_order) VALUES
  ('FREE', 'مجاني', 'Free', 0), ('PLUS', 'Plus', 'Plus', 1), ('PREMIUM', 'Premium', 'Premium', 2)
ON CONFLICT (code) DO NOTHING;

WITH v(code, key, value) AS (VALUES
  ('FREE','daily_likes','10'), ('FREE','daily_messages','1'), ('FREE','daily_undos','0'),
  ('FREE','advanced_filters','false'), ('FREE','see_who_liked_you','false'), ('FREE','incognito','false'), ('FREE','priority_visibility','false'), ('FREE','search_outside_country','false'), ('FREE','visible_conversations','5'), ('FREE','monthly_compliments','3'),
  ('PLUS','daily_likes','100'), ('PLUS','daily_messages','5'), ('PLUS','daily_undos','3'),
  ('PLUS','advanced_filters','true'), ('PLUS','see_who_liked_you','true'), ('PLUS','incognito','false'), ('PLUS','priority_visibility','false'), ('PLUS','search_outside_country','true'), ('PLUS','visible_conversations','10'), ('PLUS','monthly_compliments','10'),
  ('PREMIUM','daily_likes','200'), ('PREMIUM','daily_messages','10'), ('PREMIUM','daily_undos','10'),
  ('PREMIUM','advanced_filters','true'), ('PREMIUM','see_who_liked_you','true'), ('PREMIUM','incognito','true'), ('PREMIUM','priority_visibility','true'), ('PREMIUM','search_outside_country','true'), ('PREMIUM','visible_conversations','-1'), ('PREMIUM','monthly_compliments','20')
)
INSERT INTO feature_entitlements (plan_id, feature_key, value)
SELECT p.id, v.key, v.value::jsonb FROM v JOIN subscription_plans p ON p.code = v.code::plan_code
ON CONFLICT (plan_id, feature_key) DO NOTHING;

INSERT INTO interests (key, name_ar, name_en, category, is_basic) VALUES
  ('reading','القراءة','Reading','culture',true), ('travel','السفر','Travel','lifestyle',true),
  ('cooking','الطبخ','Cooking','lifestyle',true), ('fitness','الرياضة','Fitness','health',true),
  ('nature','الطبيعة','Nature','lifestyle',true), ('volunteering','العمل التطوعي','Volunteering','community',false),
  ('technology','التقنية','Technology','work',false), ('languages','اللغات','Languages','culture',false),
  ('arts','الفنون','Arts','culture',false), ('photography','التصوير','Photography','culture',false),
  ('family','الأسرة','Family time','lifestyle',false), ('hiking','المشي','Hiking','health',false)
ON CONFLICT (key) DO NOTHING;

INSERT INTO system_settings (key, value, description) VALUES
  ('matching.weights', '{"version":1,"interests":30,"timeline":20,"location":15,"lifestyle":15,"education":10,"preferenceFit":10}', 'Compatibility weights (0–100 each)'),
  ('matching.passResurfaceDays', '30', 'Days before a passed profile may be shown again (0 = never)'),
  ('matching.shownCooldownHours', '24', 'Do not re-show a profile that was shown but not acted on within this window'),
  ('matching.oppositeGenderOnly', 'true', 'Marriage platform: show the opposite gender only'),
  ('profile.minPhotos', '2', 'Minimum approved photos for discovery'),
  ('profile.minAge', '18', 'Minimum age'),
  ('profile.reReviewOnNameOrPhotoChange', 'true', 'Send the profile back to review on name/photo change'),
  ('otp.ttlSeconds', '300', 'OTP validity'),
  ('otp.resendCooldownSeconds', '45', 'Minimum gap between OTP requests for one phone'),
  ('otp.maxVerifyAttempts', '5', 'Wrong attempts before the challenge locks'),
  ('chat.continuationDailyLimit', '200', 'Max messages per user per conversation per day (anti-spam)'),
  ('chat.messagesConsumeCredit', '"start_only"', 'start_only = credits only start conversations; every_message = each message consumes'),
  ('chat.attachmentsEnabled', 'false', 'Allow attachments in chat'),
  ('matching.defaultSort', '"nearest"', 'nearest = closest first, then own country; best = highest compatibility first'),
  ('consultations.paymentWindowMinutes', '30', 'Unpaid bookings expire after this many minutes'),
  ('consultations.platformFeePercent', '15', 'Platform commission on each consultation'),
  ('consultations.chatRetentionDays', '30', 'Consultation chats are deleted for both sides this many days after the consultation ends or after the last message, whichever is later'),
  ('consultations.chatWarnBeforeDays', '3', 'Notify both sides this many days before a consultation chat is deleted'),
  ('consultations.durations', '[30,45,60,90]', 'Durations counselors may offer (minutes)'),
  ('chat.inboxRetentionDays', '15', 'Inactive conversations in Messages are deleted after N days'),
  ('chat.inboxWarnAfterDays', '10', 'Warn after N days of inactivity in Messages'),
  ('chat.archiveRetentionDays', '30', 'Archived conversations are deleted after N days'),
  ('chat.archiveWarnBeforeDays', '7', 'Warn N days before an archived conversation is deleted'),
  ('chat.unmatchedRetentionDays', '30', 'Unmatched conversations are deleted after N days without a re-match')
ON CONFLICT (key) DO NOTHING;

INSERT INTO roles (key, name) VALUES
  ('super_admin','Super admin'), ('admin','Admin'), ('moderator','Content moderator'),
  ('support','Support agent'), ('finance','Finance'), ('viewer','Read-only')
ON CONFLICT (key) DO NOTHING;

INSERT INTO permissions (key, description) VALUES
  ('users.read','View users'), ('users.manage','Suspend / restrict / reactivate users'),
  ('verification.review','Approve or reject profiles and photos'), ('reports.manage','Handle reports'),
  ('chat.moderate','View reported messages'), ('plans.manage','Edit plans and quotas'),
  ('payments.read','View payments'), ('payments.refund','Issue refunds'),
  ('settings.manage','Edit system settings and matching weights'), ('admins.manage','Manage admin accounts and roles'),
  ('support.manage','Handle tickets and FAQ'), ('notifications.send','Send broadcast notifications'), ('audit.read','Read audit logs'),
  ('counselors.review','Approve, reject or suspend counselors'), ('consultations.manage','View consultations and resolve disputes'),
  ('payouts.manage','Process counselor withdrawals'), ('integrity.manage','Review integrity cases and ban accounts')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON
  r.key = 'super_admin'
  OR (r.key = 'admin' AND p.key <> 'admins.manage')
  OR (r.key = 'moderator' AND p.key IN ('users.read','verification.review','reports.manage','chat.moderate','counselors.review','integrity.manage'))
  OR (r.key = 'support' AND p.key IN ('users.read','support.manage','consultations.manage'))
  OR (r.key = 'finance' AND p.key IN ('users.read','payments.read','payments.refund','plans.manage','payouts.manage'))
  OR (r.key = 'viewer' AND p.key IN ('users.read','payments.read','audit.read'))
ON CONFLICT DO NOTHING;

-- Native ads in Discovery: Free plan only (a trigger refuses true on paid plans).
INSERT INTO feature_entitlements (plan_id, feature_key, value)
SELECT p.id, 'show_ads', (p.code = 'FREE')::text::jsonb FROM subscription_plans p
ON CONFLICT (plan_id, feature_key) DO NOTHING;

-- Voice notes per conversation (-1 = unlimited).
INSERT INTO feature_entitlements (plan_id, feature_key, value)
SELECT p.id, v.k, v.val::jsonb FROM subscription_plans p
JOIN (VALUES ('FREE','voice_notes_per_conversation','10'), ('PLUS','voice_notes_per_conversation','30'), ('PREMIUM','voice_notes_per_conversation','-1')) v(code, k, val) ON v.code = p.code::text
ON CONFLICT (plan_id, feature_key) DO NOTHING;

-- Store products (App Store subscription group "OLFA": Premium = level 1, Plus = level 2;
-- Play subscriptions with one monthly base plan each). Product ids must match
-- App Store Connect / Play Console and mobile/lib/features/subscriptions/data/store_products.dart.
INSERT INTO plan_products (plan_id, provider, product_id, duration_days)
SELECT p.id, v.provider::payment_provider, v.product_id, 30
FROM (VALUES ('PLUS','APPLE','olfa.plus.monthly'), ('PREMIUM','APPLE','olfa.premium.monthly'),
             ('PLUS','GOOGLE','olfa_plus'), ('PREMIUM','GOOGLE','olfa_premium')) v(code, provider, product_id)
JOIN subscription_plans p ON p.code = v.code::plan_code
ON CONFLICT (provider, product_id) DO NOTHING;

-- ───────────── Help: frequently asked questions (ar / en / fr) — only when none exist yet ─────────────
INSERT INTO faq_entries (category, sort_order, question, answer)
SELECT v.category::ticket_category, v.sort_order, v.q::jsonb, v.a::jsonb FROM (VALUES
 ('ACCOUNT', 1,
  '{"ar":"لماذا أحتاج إلى التحقق من رقم هاتفي؟","en":"Why do I need to verify my phone number?","fr":"Pourquoi dois-je vérifier mon numéro de téléphone ?"}',
  '{"ar":"التحقق برمز يُرسل إلى هاتفك يضمن أن كل حساب يعود لشخص حقيقي ويحمي المجتمع من الحسابات الوهمية. لا نعرض رقمك لأي مستخدم.","en":"A code sent to your phone makes sure every account belongs to a real person and keeps fake accounts out. Your number is never shown to other members.","fr":"Un code envoyé sur votre téléphone garantit que chaque compte appartient à une personne réelle. Votre numéro n’est jamais montré aux autres membres."}'),
 ('ACCOUNT', 2,
  '{"ar":"ما الفرق بين تجميد الحساب وحذفه؟","en":"What is the difference between freezing and deleting my account?","fr":"Quelle différence entre geler et supprimer mon compte ?"}',
  '{"ar":"التجميد يخفي ملفك مؤقتاً ويمكنك إعادة تفعيله في أي وقت. الحذف يزيل حسابك وبياناتك نهائياً بعد مهلة الاسترجاع الموضحة في الإعدادات.","en":"Freezing hides your profile for now and you can reactivate any time. Deleting removes your account and data for good after the recovery period shown in Settings.","fr":"Le gel masque votre profil temporairement ; vous pouvez le réactiver à tout moment. La suppression efface définitivement votre compte après le délai indiqué dans les Réglages."}'),
 ('ACCOUNT', 3,
  '{"ar":"لماذا يظهر لي أن حسابي مغلق؟","en":"Why does it say my account is closed?","fr":"Pourquoi mon compte apparaît-il comme fermé ?"}',
  '{"ar":"تُغلق الحسابات التي تخالف سياسة المجتمع إما لمدة محددة (وتُفتح تلقائياً عند انتهائها) أو نهائياً. يظهر لك السبب والمدة على شاشة الحساب المغلق، ويمكنك التواصل مع الدعم.","en":"Accounts that break the community policy are closed either for a set period (they reopen by themselves when it ends) or permanently. The closed-account screen shows the reason and the period, and you can contact support.","fr":"Les comptes qui enfreignent la charte sont fermés pour une durée déterminée (réouverture automatique ensuite) ou définitivement. L’écran indique le motif et la durée ; vous pouvez contacter le support."}'),
 ('VERIFICATION', 1,
  '{"ar":"كيف تحمي ألفة صوري الشخصية؟","en":"How does OLFA protect my photos?","fr":"Comment OLFA protège-t-elle mes photos ?"}',
  '{"ar":"تُراجع الصور قبل ظهورها، ويمنع التطبيق لقطات الشاشة وتسجيلها على أندرويد، ويخفي المحتوى عند التسجيل أو في قائمة التطبيقات على iOS. لا يمكن لأي تطبيق منع تصوير الشاشة بكاميرا أخرى، لذا شارك ما ترتاح له فقط.","en":"Photos are reviewed before they appear. On Android the app blocks screenshots and screen recording; on iOS it hides content while the screen is recorded and in the app switcher. No app can stop someone photographing the screen with another camera, so share only what you are comfortable with.","fr":"Les photos sont vérifiées avant publication. Sur Android, l’app bloque captures et enregistrements d’écran ; sur iOS, elle masque le contenu pendant un enregistrement et dans le sélecteur d’apps. Aucune app ne peut empêcher de photographier l’écran avec un autre appareil : ne partagez que ce qui vous convient."}'),
 ('VERIFICATION', 2,
  '{"ar":"لماذا يُطلب مني سيلفي عند التسجيل؟","en":"Why do I need to take a selfie when I sign up?","fr":"Pourquoi dois-je prendre un selfie à l’inscription ?"}',
  '{"ar":"بعد رفع صورك نطلب سيلفي مباشرة مع إشارة يد عشوائية ليتأكد فريق التحقق أن الصور لك وأنك شخص حقيقي. السيلفي خاصة ولا تظهر في ملفك، وتُحذف بعد القرار. يمكنك طلب أن تراجعها موظفة.","en":"After your photos we ask for a live selfie with a random hand gesture, so the verification team can confirm the photos are you and that you are a real person. The selfie is private, never shown on your profile, and deleted after the decision. You can ask that a woman from the team reviews it.","fr":"Après vos photos, nous demandons un selfie en direct avec un geste aléatoire, afin que l’équipe confirme que les photos sont bien vous et que vous êtes une vraie personne. Le selfie est privé, n’apparaît jamais sur votre profil et est supprimé après la décision. Vous pouvez demander qu’une femme de l’équipe le vérifie."}'),
 ('PAYMENT', 1,
  '{"ar":"متى يحصل المستشار على أجر الاستشارة؟","en":"When does the counselor get paid for a consultation?","fr":"Quand le conseiller est-il payé ?"}',
  '{"ar":"يُحتجز المبلغ عند الدفع، ولا يُحوَّل إلى محفظة المستشار إلا بعد أن تؤكد أن الجلسة تمت وتقيّم المستشار. إن لم تتم الجلسة اختر «لم تتم» وسيراجع الدعم الحالة ويعيد المبلغ عند الاقتضاء.","en":"The fee is held when you pay and only goes to the counselor’s wallet after you confirm the session took place and rate the counselor. If it did not happen, choose “It didn’t happen” and support will review it and refund you where appropriate.","fr":"Le montant est retenu au paiement et n’est versé au conseiller qu’après votre confirmation que la séance a eu lieu et votre note. Si elle n’a pas eu lieu, choisissez « Elle n’a pas eu lieu » : le support examinera et remboursera si nécessaire."}'),
 ('PAYMENT', 2,
  '{"ar":"كيف أستعيد اشتراكي على جهاز جديد؟","en":"How do I restore my subscription on a new phone?","fr":"Comment restaurer mon abonnement sur un nouveau téléphone ?"}',
  '{"ar":"سجّل الدخول بنفس رقم الهاتف ثم افتح «الاشتراكات» واضغط «استعادة المشتريات». يُدار الاشتراك وإلغاؤه من متجر التطبيقات.","en":"Sign in with the same phone number, open Subscriptions and tap “Restore purchases”. Billing and cancellation are managed by the app store.","fr":"Connectez-vous avec le même numéro, ouvrez Abonnements et touchez « Restaurer les achats ». La facturation et la résiliation se gèrent dans le store."}'),
 ('TECHNICAL', 1,
  '{"ar":"لا تصلني الإشعارات، ماذا أفعل؟","en":"I am not getting notifications — what can I do?","fr":"Je ne reçois pas les notifications, que faire ?"}',
  '{"ar":"تأكد من السماح بإشعارات ألفة في إعدادات الهاتف ومن تفعيلها في «الإشعارات» داخل التطبيق، ثم أعد فتح التطبيق.","en":"Make sure OLFA notifications are allowed in your phone settings and switched on under Notifications in the app, then reopen the app.","fr":"Vérifiez que les notifications d’OLFA sont autorisées dans les réglages du téléphone et activées dans l’app, puis rouvrez l’app."}'),
 ('OTHER', 1,
  '{"ar":"كيف أتواصل مع الدعم؟","en":"How do I contact support?","fr":"Comment contacter le support ?"}',
  '{"ar":"من «المساعدة والدعم» اضغط «طلب جديد»، اكتب رسالتك وأرفق صورة أو ملف PDF إن لزم. تصلك ردود الفريق في نفس الصفحة وبإشعار.","en":"In Help & Support tap “New request”, write your message and attach an image or a PDF if needed. Replies arrive on the same page and as a notification.","fr":"Dans Aide et support, touchez « Nouvelle demande », écrivez votre message et joignez une image ou un PDF si besoin. Les réponses arrivent sur la même page et par notification."}')
) AS v(category, sort_order, q, a)
WHERE NOT EXISTS (SELECT 1 FROM faq_entries);
