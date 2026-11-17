# تقرير المراجعة والتحصين الشامل — Link Scanner V6 1.21.16+40

**التاريخ:** 16 نوفمبر 2026  
**قاعدة العمل:** `Link_Scanner_V6_1.21.15+39_redirect_calibration_fix.zip`  
**الإصدار الناتج:** `1.21.16+40`

## الخلاصة التنفيذية

تم إجراء جولة تحصين إضافية على محرك تحليل الروابط، وتتبع التحويلات، واستخراج روابط الرسائل، وخدمة Chromium المعزولة، وسياسة الخروج الشبكي، واختبارات سكربت Android Gradle. تم تضمين التعديلات في مشروع واحد، مع إضافة حالات انحدار إلى الاختبارات ورفع إصدار التطبيق ورقم البناء معًا.

هذه ليست شهادة إصدار نهائي: أدوات Dart/Flutter وAndroid SDK غير متاحة في بيئة التحرير، لذلك لا يمكن تأكيد نجاح التحليل أو اختبارات Flutter أو بناء APK هنا. بوابة CI في GitHub هي خطوة الاعتماد النهائية.

## التعديلات

### 1. سياسة عناوين IP وIPv6
- `lib/services/net_guard.dart`: استمرار منع loopback وprivate وlink-local وmulticast والعناوين التوثيقية وصيغ IPv4 المضمّنة داخل IPv6. أضيف منع `3fff::/20` و`2001::/23` و`2001:db8::/32` وأي عنوان خارج `2000::/3`، كما تُمنع صيغة IPv4-compatible القديمة `::a.b.c.d` بالكامل بينما تظل صيغة mapped `::ffff:a.b.c.d` خاضعة لفحص IPv4 المضمّن.
- خدمة Chromium أكثر تحفظًا من NetGuard مع NAT64 و6to4: ترفض بادئات الترجمة/الانتقال بالكامل قبل الاتصال، بينما NetGuard المحلي يمكنه تقييم IPv4 العام المضمّن داخل الصيغ المدعومة.
- `sandbox_service/app/main.py`: أضيفت `3fff::/20` إلى قائمة الحظر، وأصبح قرار السماح يتطلب أن يكون العنوان global وغير reserved وغير multicast وغير unspecified. أضيف اختبار لمسار DNS يرفض صيغة IPv4-compatible القديمة.
- `sandbox_service/deploy/block-private-egress.sh`: أضيفت قواعد إسقاط `::/3` و`4000::/2` و`8000::/1` لمنع المساحات خارج Global Unicast، إلى جانب النطاقات الخاصة والتوثيقية والتحويلية الواقعة داخل المجال العام.
- **ملاحظة تشغيلية مهمة:** فحص DNS المسبق داخل خدمة Chromium ليس بديلًا عن جدار الخروج؛ لأن Chromium يقوم بحل DNS عند الاتصال أيضًا. يجب تشغيل سكربت `block-private-egress.sh` على مضيف Docker بعد إنشاء الحاوية، وإعادة تشغيله بعد إعادة إنشائها/تغير عنوانها. لا يدّعي هذا الإصدار إغلاق فجوة DNS rebinding من دون هذا الإجراء.

### 2. حلقات تحويل HTTP
- `lib/services/link_expander.dart`: تمت مقارنة طلبات HTTP بعد إزالة `#fragment`، لأن الجزء بعد `#` لا يُرسل إلى الخادم. تغيير fragment فقط لم يعد يُعامل على أنه hop جديد.
- `test/link_expander_test.dart`: أضيف اختبار بخادم محلي يثبت اكتشاف هذه الحلقة بعد طلب HEAD واحد فقط.
- لا يفتح الفحص المحلي الروابط ولا يتتبع تحويلات HTTP. تتبع التحويلات يبقى مسارًا منفصلًا يطلبه المستخدم صراحة.

### 3. استخراج الدومينات الدولية من الرسائل
- `lib/services/message_analyzer.dart`: أضيف التقاط أسماء النطاقات ذات الحروف Unicode، مثل الحروف السيريلية واللاتينية المشكّلة، حتى عندما لا يسبق الرابط بروتوكول.
- `test/message_analyzer_test.dart`: أضيف اختبار للدومينات `раypal.com` و`exämple.de` داخل نص رسالة عادي.
- فحص السمعة والاتصال لا يُفعلان لمجرد التقاط النص؛ تظل قواعد التحليل والحدود الحالية مطبقة.

### 4. أدوات مساعدة للمستخدم
- `lib/services/sender_analyzer.dart`: أضيف تحويل الأرقام الفارسية `۰۱۲۳۴۵۶۷۸۹` إلى ASCII إلى جانب الأرقام العربية الهندية، بحيث يتعرف فاحص المرسل على صيغ الأرقام المصرية المكتوبة بلوحات مفاتيح مختلفة.
- `test/sender_analyzer_test.dart`: أضيفت حالات للأرقام المحلية العربية/الفارسية، وصيغة `+20` الدولية، واسم المرسل، وعدم توافق رقم موبايل مع ادعاء بنك.
- `lib/services/url_cleaner.dart`: أزيل المفتاح العام `ref` من قائمة المعاملات التي تُحذف تلقائيًا؛ فقد يكون قيمة وظيفية مثل رقم إحالة أو طلب وليس متتبعًا بالضرورة. تبقى معاملات التتبع الدقيقة و`utm_*` قابلة للإزالة.
- `test/url_cleaner_test.dart`: أضيفت اختبارات الحفاظ على `ref` والاستعلامات الأخرى، وإزالة المفاتيح المشفّرة مثل `utm%5Fsource`، والإدخال غير الصالح.

### 5. خدمة Chromium المعزولة
- أزيل تعريف `test_resolver_times_out_closed` المكرر؛ وجود تعريفين بالاسم نفسه كان يجعل Python يستبدل الأول بالثاني أثناء تحميل الملف بدل جمعهما كاختبارين.
- أضيف اختبار نطاقات IPv6 المحجوزة/التوثيقية ونطاقات خارج Global Unicast، واختبار لصيغة IPv4-compatible القديمة.
- أضيف اختبار يتأكد من وجود قواعد الحظر المقابلة في سكربت جدار الخروج.

### 6. بناء Android وCI
- أضيف `android_overlay/test_patch_build_gradle.py` باختبارين: واحد لـKotlin DSL (`build.gradle.kts`) وآخر لـGroovy (`build.gradle`).
- الاختباران يتحققان من ترتيب `import` قبل `plugins {}`, ووضع تهيئة التوقيع بعد كتلة الإضافات، وminSdk، وقواعد ProGuard، وإضافة Tesseract/JitPack مرة واحدة، وعدم تكرار التعديلات عند التشغيل مرتين.
- أضيف تشغيل الاختبارات إلى `.github/workflows/main.yml` قبل تحليل Dart واختبارات Flutter وبناء APK.

### 7. إصدار التطبيق
- `pubspec.yaml`: `1.21.16+40`.
- `lib/core/app_info.dart`: `kAppVersion = 1.21.16` و`kAppBuild = 40`.
- يوجد اختبار Flutter قائم يتحقق من تطابق القيمتين مع `pubspec.yaml`، لكنه لم يُشغّل هنا بسبب غياب Flutter.

## نتائج الاختبارات التي نُفذت فعليًا

| الاختبار | النتيجة |
|---|---:|
| `sandbox_service/tests` | 30 passed |
| `tool/test_update_unicode_confusables.py` | 9 passed |
| `android_overlay/test_patch_build_gradle.py` | 2 passed |
| **الإجمالي** | **41 passed** |
| `python -m compileall -q sandbox_service android_overlay tool` | نجح |
| `bash -n` لسكربتات Shell الثلاثة | نجح |
| قراءة `.github/workflows/main.yml` باستخدام PyYAML | نجحت؛ تم العثور على وظيفتي `verify` و`build` |
| اكتشاف تكرار أسماء اختبارات Python العليا | لا توجد تعريفات مكررة بعد الإصلاح |

## ما لم يمكن التحقق منه هنا

لم تكن أوامر `dart` و`flutter` ولا Android SDK/Gradle متاحة في البيئة؛ لذلك لم تُشغّل:

- `dart format lib test tool`
- `flutter analyze --no-fatal-infos`
- `flutter test --reporter expanded`
- `dart run tool/benchmark_url_analyzer.dart`
- بناء APK Debug/Release أو اختبار تثبيت على جهاز Android.

وجود اختبارات مكتوبة لا يعني أنها نجحت. يجب تشغيل CI على هذا الإصدار، وإصلاح أي فشل يظهر قبل توزيع APK.

## الثوابت التي لم تتغير

- التحليل المحلي لا يفتح المواقع ولا يتصل بالإنترنت.
- الخدمات الخارجية/التحليل الديناميكي اختيارية، وفشلها لا يساوي نتيجة آمنة.
- لا اشتراك، ولا API مدفوع جديد، ولا مفتاح إلزامي جديد.
- لم يتم حذف شاشات أو أدوات أو قدرات من المشروع في هذه الجولة.

## ملفات التغيير الأساسية

- `lib/services/net_guard.dart`
- `lib/services/link_expander.dart`
- `lib/services/message_analyzer.dart`
- `lib/services/sender_analyzer.dart`
- `lib/services/url_cleaner.dart`
- `test/net_guard_test.dart`
- `test/link_expander_test.dart`
- `test/message_analyzer_test.dart`
- `test/sender_analyzer_test.dart`
- `test/url_cleaner_test.dart`
- `sandbox_service/app/main.py`
- `sandbox_service/tests/test_analysis.py`
- `sandbox_service/deploy/block-private-egress.sh`
- `android_overlay/test_patch_build_gradle.py`
- `.github/workflows/main.yml`
- `pubspec.yaml`
- `lib/core/app_info.dart`
- `CHANGELOG.md`
