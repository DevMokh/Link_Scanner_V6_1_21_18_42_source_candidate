import '../core/models.dart';
import 'invisible_chars.dart';

/// إحصاءات التقرير المجمّع. الحالات متنافية حتى لا يُحسب الفحص الجزئي
/// كفحص مكتمل، ولا يُحسب فشل التحليل كفحص جزئي.
///
/// معادلات المحاسبة (كل مدخل بيتحسب مرة واحدة بس):
///  - `recognized = completed + partial + invalidInput + analysisFailed`
///    (الروابط اللي دخلت التحليل فعلًا).
///  - `unscanned = invalidInput + analysisFailed` (مفيش درجة خطر ليها).
///  - الروابط اللي عندها درجة (`completed + partial`) بتتقسم برضه حسب مستوى الخطر:
///    `highRisk + mediumRisk + lowSignals + zeroScore = completed + partial`.
///  - `totalAccounted = recognized + unrecognized + overflow + duplicates`
///    (كل نص شكله رابط أو مسار: اتفحص، أو اتعرض كغير متعرَّف عليه، أو زاد عن الحد، أو
///    مكرر واتدمج). كلمات عادية وقطع أقصر من 4 حروف مش مدخلات وبتتجاهل عمدًا.
class BatchReportSummary {
  const BatchReportSummary({
    required this.recognized,
    required this.completed,
    required this.partial,
    required this.unscanned,
    required this.invalidInput,
    required this.analysisFailed,
    this.highRisk = 0,
    this.mediumRisk = 0,
    this.lowSignals = 0,
    this.zeroScore = 0,
    this.unrecognized = 0,
    this.overflow = 0,
    this.duplicates = 0,
  });

  /// عدد الروابط اللي دخلت التحليل (الروابط اللي اتعرّف عليها الـ parser وفي حدود الدفعة).
  final int recognized;

  /// Fully completed local analyses (partial results are counted separately).
  final int completed;

  /// Analyses that returned a score but were marked partial.
  final int partial;

  /// Inputs that did not receive a usable score (invalid or analysis failure).
  final int unscanned;

  /// Inputs rejected by URL validation before scoring.
  final int invalidInput;

  /// Inputs for which analysis failed unexpectedly.
  final int analysisFailed;

  /// درجة >= [kBandHigh].
  final int highRisk;

  /// درجة من [kBandMedium] لحد أقل من [kBandHigh].
  final int mediumRisk;

  /// درجة من 1 لحد أقل من [kBandMedium]: مؤشرات محدودة (مش "بلا مؤشرات").
  final int lowSignals;

  /// درجة صفر: مفيش نقاط خطورة محتسبة (مش ضمان أمان).
  final int zeroScore;

  /// نصوص شكلها مسار/رابط لكن ما اتعرّفش عليها كرابط (ما اتفحصتش).
  final int unrecognized;

  /// روابط اتعرّف عليها لكن زادت عن حد الدفعة فما اتفحصتش.
  final int overflow;

  /// نصوص مكررة اندمجت مع نص سابق.
  final int duplicates;

  /// مجموع كل المدخلات اللي اتحسبت (اتفحصت + غير متعرَّف عليها + زايدة + مكررة).
  int get totalAccounted => recognized + unrecognized + overflow + duplicates;

  /// الروابط اللي طلع ليها درجة خطر (مكتملة أو جزئية).
  int get scored => completed + partial;

  /// المعادلات فوق متحققة (بتتستخدم في الاختبارات وعشان أي خلل في العدّ يبان).
  bool get isConsistent =>
      recognized == completed + partial + invalidInput + analysisFailed &&
      unscanned == invalidInput + analysisFailed &&
      scored == highRisk + mediumRisk + lowSignals + zeroScore;

  factory BatchReportSummary.fromResults(
    Iterable<ScanResult> results, {
    int unrecognized = 0,
    int overflow = 0,
    int duplicates = 0,
  }) {
    var recognized = 0;
    var completed = 0;
    var partial = 0;
    var invalidInput = 0;
    var analysisFailed = 0;
    var highRisk = 0;
    var mediumRisk = 0;
    var lowSignals = 0;
    var zeroScore = 0;

    for (final result in results) {
      recognized++;
      switch (result.state) {
        case ScanState.completed:
          if (result.partial) {
            partial++;
          } else {
            completed++;
          }
          final score = result.effectiveScore;
          if (score >= kBandHigh) {
            highRisk++;
          } else if (score >= kBandMedium) {
            mediumRisk++;
          } else if (score > 0) {
            lowSignals++;
          } else {
            zeroScore++;
          }
          break;
        case ScanState.invalidInput:
          invalidInput++;
          break;
        case ScanState.failed:
          analysisFailed++;
          break;
      }
    }

    return BatchReportSummary(
      recognized: recognized,
      completed: completed,
      partial: partial,
      unscanned: invalidInput + analysisFailed,
      invalidInput: invalidInput,
      analysisFailed: analysisFailed,
      highRisk: highRisk,
      mediumRisk: mediumRisk,
      lowSignals: lowSignals,
      zeroScore: zeroScore,
      unrecognized: unrecognized,
      overflow: overflow,
      duplicates: duplicates,
    );
  }

  /// أسطر ملخص التقرير المنسوخ (نص عادي). [maxLinks] = حد الدفعة.
  List<String> reportLines({required int maxLinks}) => <String>[
        'الحد الأقصى لهذه الدفعة: $maxLinks رابط',
        'إجمالي المدخلات المحسوبة: $totalAccounted = روابط دخلت الفحص $recognized'
            ' + نصوص لم يُتعرّف عليها كرابط $unrecognized'
            ' + روابط زائدة عن الحد $overflow + مكررة $duplicates',
        'تم التعرف على: $recognized | اكتمل تحليلها: $completed'
            ' | تحليل جزئي: $partial | لم تُفحص: $unscanned',
        'مدخلات غير صالحة: $invalidInput | فشل التحليل: $analysisFailed',
        'توزيع الدرجات: خطير $highRisk | مشبوه $mediumRisk'
            ' | مؤشرات محدودة $lowSignals | بلا نقاط خطورة $zeroScore',
        'نصوص لم يتم التعرف عليها كرابط: $unrecognized',
        'روابط زائدة عن الحد ولم تُفحص: $overflow',
      ];
}

/// عنوان واضح للدرجة المنخفضة في التقرير المجمّع:
/// الدرجة الأقل من 20 قد تحتوي على إشارة ضعيفة، فلا نصفها بأنها بلا مؤشرات.
class BatchReportLabels {
  BatchReportLabels._();

  static String headline(ScanResult result) {
    if (!result.hasScore) return result.headline;

    // العنوان المحايد "لا مؤشرات واضحة" هو الوحيد اللي ممكن يضلل. باقي الأحكام
    // (مشبوه / خطير / فحص جزئي / محتوى غير كافٍ) بتقول أكتر وبتفضل زي ما هي.
    if (result.verdict != Verdict.noIndicators) return result.headline;

    final score = result.effectiveScore;
    if (score > 0) return 'مؤشرات محدودة';

    if (result.findings.any((finding) => finding.severity != Severity.good)) {
      return 'ملاحظات معلوماتية فقط';
    }

    return result.headline;
  }
}

/// صف واحد في التقرير المجمّع: النص اللي اتفحص ونتيجته.
class BatchReportRow {
  const BatchReportRow(this.input, this.result);

  final String input;
  final ScanResult result;
}

/// بيبني نص التقرير المنسوخ للفحص المجمّع. دالة صافية (من غير واجهة) عشان تتختبر:
/// كل رابط دخل الفحص بياخد سطر، وكل نص غير متعرَّف عليه بياخد سطر، والزيادة عن الحد
/// بتتذكر بالعدد. الحروف الخفية بتتكتب كأكواد صريحة (⟦U+200B (ZWSP)⟧).
String buildBatchReport({
  required List<BatchReportRow> rows,
  required List<String> unrecognized,
  required int overflow,
  required int duplicates,
  required int maxLinks,
}) {
  final stats = BatchReportSummary.fromResults(
    rows.map((row) => row.result),
    unrecognized: unrecognized.length,
    overflow: overflow,
    duplicates: duplicates,
  );
  final b = StringBuffer()
    ..writeln('تقرير فحص مجمّع - كاشف الروابط')
    ..writeln(
        'نوع الفحص: تحليل محلي دون إنترنت. لا يتتبع تحويلات HTTP ولا يفتح المواقع.')
    ..writeln(
        'درجة 0 تعني عدم وجود نقاط خطورة محتسبة، وليست ضمانًا بأن الرابط آمن؛ وقد تظهر ملاحظات معلوماتية بلا نقاط.');
  for (final line in stats.reportLines(maxLinks: maxLinks)) {
    b.writeln(line);
  }
  b.writeln();

  for (final r in rows) {
    // الحروف الخفية بتتكتب كأكواد صريحة عشان رابط مموّه ما يظهرش ككلمة عادية.
    final visibleInput = InvisibleChars.escapeForDisplay(r.input);
    if (r.result.hasScore) {
      b.writeln(
        '${r.result.effectiveScore}/100 - ${BatchReportLabels.headline(r.result)} - $visibleInput',
      );
    } else {
      final code =
          r.result.issueCode.isEmpty ? r.result.state.name : r.result.issueCode;
      b.writeln('غير مفحوص ($code: ${r.result.headline}) - $visibleInput');
    }

    final indicators = r.result.findings
        .where((finding) => finding.severity != Severity.good)
        .toList(growable: false);
    for (final finding in indicators) {
      final code = finding.code.isEmpty ? finding.title : finding.code;
      final weight = finding.points > 0 ? ' (+${finding.points})' : '';
      b.writeln('  المؤشر: $code$weight - ${finding.title}');
      if (finding.detail.isNotEmpty) {
        b.writeln(
          '    التفسير: ${InvisibleChars.escapeForDisplay(finding.detail)}',
        );
      }
    }
  }

  for (final u in unrecognized) {
    b.writeln(
      'غير مفحوص (لم يُتعرّف عليه كرابط) - '
      '${InvisibleChars.escapeForDisplay(u)}',
    );
  }
  if (overflow > 0) {
    b.writeln(
      'تنبيه: تم تجاهل $overflow رابطًا لأنها تجاوزت الحد الأقصى '
      '($maxLinks)، ولم تدخل في الفحص.',
    );
  }
  return b.toString();
}
