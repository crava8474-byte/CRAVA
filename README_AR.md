# CRAVA V8 — النسخة النهائية الحالية

## الجديد في V8
- Taste DNA مطوّر بأربع محاور: Chocolate، Fruity، Sweetness، Adventure.
- لقب ذوق شخصي يتغير تلقائيًا حسب تقييمات العميل.
- إحصائيات متقدمة داخل الحساب.
- 20 Badge موزعة على Bronze / Silver / Gold / Diamond / Legendary.
- CRAVA Journey لعرض رحلة العميل وإنجازاته زمنيًا.
- Flavor Passport للرولات الأربع: Chocolate، Strawberry، Custard، Lotus.
- Digital Shelf، Levels، XP، Leaderboard، Claim System، ولوحة إدارة مخفية.
- تحسينات حركية وتصميمية خفيفة تحافظ على فخامة الموقع.

## التشغيل من التاب أو الهاتف
1. أنشئ مشروع Supabase.
2. افتح SQL Editor ثم New Query.
3. افتح ملف `supabase_setup_v8.sql` وانسخ محتواه كاملًا إلى المحرر.
4. اضغط Run مرة واحدة فقط.
5. صدّر نتيجة أرقام البوكسات وClaim Codes إلى CSV فورًا واحفظها بأمان.
6. من Project Settings > API انسخ Project URL وanon public key إلى `config.js`.
7. ارفع الملفات إلى استضافة HTTPS.
8. أنشئ حسابك من الموقع، ثم نفّذ أمر تحويل حسابك إلى Admin الموجود آخر ملف SQL.

## لوحة الإدارة
الرابط المخفي:
`vault-7f3c9a.html`

الحماية ليست معتمدة على إخفاء الرابط فقط؛ التحقق يتم داخل Supabase بواسطة is_admin وRLS.
