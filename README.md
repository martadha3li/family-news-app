# أخبار العائلة

نسخة ويب أولية قابلة للتثبيت (PWA) مع Supabase مستقل.

## التشغيل
انشر المجلد الجذري على Cloudflare Pages أو GitHub Pages. فعّل Email Auth في Supabase. أنشئ أول مستخدم ثم عيّن دوره من لوحة Supabase SQL:

```sql
update public.profiles set role='admin' where id=(select id from auth.users where email='YOUR_EMAIL');
```

لا تُدخل مفاتيح service_role في ملفات الواجهة. يلزم اختبار التسجيل والصلاحيات والصور قبل دعوة الأعضاء. نسخة الويب الأولية لا تتضمن بعد أدوات إدارة الأدوار من الواجهة ولا إشعارات ولا تطبيقات المتاجر.
