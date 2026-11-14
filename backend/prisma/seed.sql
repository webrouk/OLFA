-- Reference data (idempotent). Not demo users: plans, entitlements, interests,
-- roles/permissions and system settings that the platform needs to run.

INSERT INTO subscription_plans (code, name_ar, name_en, sort_order) VALUES
  ('FREE', 'مجاني', 'Free', 0), ('PLUS', 'Plus', 'Plus', 1), ('PREMIUM', 'Premium', 'Premium', 2)
ON CONFLICT (code) DO NOTHING;

WITH v(code, key, value) AS (VALUES
  ('FREE','daily_likes','10'), ('FREE','daily_messages','1'), ('FREE','daily_undos','0'),
  ('FREE','advanced_filters','false'), ('FREE','see_who_liked_you','false'), ('FREE','incognito','false'), ('FREE','priority_visibility','false'),
  ('PLUS','daily_likes','100'), ('PLUS','daily_messages','5'), ('PLUS','daily_undos','3'),
  ('PLUS','advanced_filters','true'), ('PLUS','see_who_liked_you','true'), ('PLUS','incognito','false'), ('PLUS','priority_visibility','false'),
  ('PREMIUM','daily_likes','200'), ('PREMIUM','daily_messages','10'), ('PREMIUM','daily_undos','10'),
  ('PREMIUM','advanced_filters','true'), ('PREMIUM','see_who_liked_you','true'), ('PREMIUM','incognito','true'), ('PREMIUM','priority_visibility','true')
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
  ('chat.attachmentsEnabled', 'false', 'Allow attachments in chat')
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
  ('support.manage','Handle tickets and FAQ'), ('notifications.send','Send broadcast notifications'), ('audit.read','Read audit logs')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON
  r.key = 'super_admin'
  OR (r.key = 'admin' AND p.key <> 'admins.manage')
  OR (r.key = 'moderator' AND p.key IN ('users.read','verification.review','reports.manage','chat.moderate'))
  OR (r.key = 'support' AND p.key IN ('users.read','support.manage'))
  OR (r.key = 'finance' AND p.key IN ('users.read','payments.read','payments.refund','plans.manage'))
  OR (r.key = 'viewer' AND p.key IN ('users.read','payments.read','audit.read'))
ON CONFLICT DO NOTHING;
