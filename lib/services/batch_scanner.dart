import 'package:flutter/foundation.dart' show compute;

import '../core/models.dart';
import 'url_analyzer.dart';

/// تحليل رابط واحد بشكل آمن: أي استثناء غير متوقع بيتحوّل لنتيجة "فشل التحليل"
/// (مش "آمن" ومش "مشبوه")، فرابط تالف وسط الدفعة ما يوقّفش باقي الروابط ولا يضيع.
ScanResult _analyzeOne(String url, ScanResult Function(String) analyzer) {
  try {
    return analyzer(url);
  } catch (_) {
    return ScanResult.failed(
      kind: ScanKind.url,
      detail:
          'حصل خطأ غير متوقع أثناء فحص هذا الرابط، فما نقدرش نحكم عليه. اعتبره غير مفحوص وتعامل بحذر.',
      title: url,
    );
  }
}

/// تحليل مجموعة روابط على نفس الـ isolate، بنفس ترتيب المدخلات وبعدد النتائج نفسه
/// دايمًا (عنصر لكل رابط). [analyzer] بيتغيّر في الاختبارات بس.
List<ScanResult> analyzeUrlsSafely(
  List<String> urls, {
  ScanResult Function(String) analyzer = UrlAnalyzer.analyze,
}) =>
    urls.map((url) => _analyzeOne(url, analyzer)).toList(growable: false);

/// ينفّذ تحليل مجموعة روابط في isolate منفصل حتى لا تتوقف الرسوم والتفاعلات
/// أثناء فحص القوائم الكبيرة. لا يوجد اتصال بالإنترنت في هذا المسار.
List<ScanResult> _scanUrlsWorker(List<String> urls) => analyzeUrlsSafely(urls);

/// نسخة خلفية من التحليل المجمّع. النتيجة بنفس ترتيب المدخلات.
///
/// لو تعذّر تشغيل الـ isolate (ذاكرة/منصة)، بنكمّل التحليل على الـ isolate الحالي بدل
/// ما تضيع الدفعة كلها.
Future<List<ScanResult>> scanUrlsInBackground(List<String> urls) async {
  if (urls.isEmpty) return const <ScanResult>[];
  try {
    return await compute<List<String>, List<ScanResult>>(
      _scanUrlsWorker,
      List<String>.of(urls, growable: false),
      debugLabel: 'link-scanner-batch-analysis',
    );
  } catch (_) {
    return analyzeUrlsSafely(urls);
  }
}
