# تقرير إصلاح CI — Link Scanner V6 1.21.14+38

## سبب الفشل في لقطة GitHub Actions

خطوة `Analyze Dart code` فشلت في `test/batch_report_summary_test.dart` برسائل من نوع `undefined_getter` للحقول:
`completed`, `partial`, `unscanned`, `invalidInput`, و`analysisFailed`.

السبب الجذري كان في `lib/services/batch_report_summary.dart`: المُنشئ استخدم initializing formals بصيغة `this.field`، لكن الكلاس لم يعرّف حقول الأعضاء المقابلة. أضيفت تعريفات `final int` للحقول الستة: `recognized`, `completed`, `partial`, `unscanned`, `invalidInput`, و`analysisFailed`.

## ما تغيّر

- إضافة حقول الأعضاء الستة إلى `BatchReportSummary` دون تغيير منطق العدّ.
- إبقاء الفئات متمايزة: المكتمل، الجزئي، المدخل غير الصالح، وفشل التحليل.
- مزامنة الإصدار إلى `1.21.14+38` في `pubspec.yaml` و`lib/core/app_info.dart`.
- تحديث سجل التغييرات.

## ما تم التحقق منه محليًا

- وجود تعريف لكل حقل يستخدمه المُنشئ والاختبار وواجهة التقرير.
- اتساق رقم الإصدار ورقم البناء بين ملفات الإصدار.
- صحة قراءة YAML.
- سلامة بنية ملف ZIP بعد إنشائه.

## ما لم يتم التحقق منه

بيئة التحرير لا تحتوي على Flutter أو Dart، لذلك لم يتم تشغيل `dart format` أو `flutter analyze` أو `flutter test` أو بناء APK. هذه النسخة إصلاح مصدر مرشح، وليست تصريحًا بأن CI نجح. يجب رفعها وتشغيل workflow من جديد.

## توضيح رسالة الإلغاء

الرسالة `Canceling since a higher priority waiting request ... exists` ناتجة عن إعداد `concurrency` في GitHub Actions الذي يلغي التشغيل الأقدم عند وجود تشغيل أحدث على نفس الفرع. وهي منفصلة عن أخطاء Dart المذكورة أعلاه.
