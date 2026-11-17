import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/batch_input.dart';
import 'package:cobra_shield/services/batch_report_summary.dart';
import 'package:cobra_shield/services/batch_scanner.dart';
import 'package:cobra_shield/services/invisible_chars.dart';

// ---------------------------------------------------------------------------
// أدوات الاختبار
// ---------------------------------------------------------------------------

ScanResult scored(
  int score, {
  bool partial = false,
  List<Finding> findings = const <Finding>[],
}) =>
    ScanResult(
      kind: ScanKind.url,
      score: score,
      findings: findings,
      partial: partial,
    );

ScanResult invalidResult(String input) => ScanResult.invalid(
      kind: ScanKind.url,
      issueCode: 'invalid_port',
      detail: 'رقم المنفذ غير صالح',
      title: input,
    );

/// محلل مزيّف حتمي: بيحدد الحالة من كلمة جوه الرابط (من غير أي شبكة).
/// boom بترمي استثناء عمدًا عشان نختبر عزل الأخطاء داخل الدفعة.
ScanResult fakeAnalyzer(String url) {
  if (url.contains('boom')) throw StateError('boom');
  if (url.contains('badport')) return invalidResult(url);
  if (url.contains('high')) return scored(80);
  if (url.contains('mid')) return scored(30);
  if (url.contains('low')) return scored(10);
  if (url.contains('partial')) return scored(5, partial: true);
  return scored(0);
}

class BatchRun {
  BatchRun(this.parsed, this.results, this.summary, this.report);

  final BatchParse parsed;
  final List<ScanResult> results;
  final BatchReportSummary summary;
  final String report;

  /// عدد أسطر العناصر في التقرير (رابط اتفحص أو نص غير متعرَّف عليه).
  int get itemLines => report
      .split('\n')
      .where((line) => RegExp(r'^(\d+/100 - |غير مفحوص \()').hasMatch(line))
      .length;
}

BatchRun runBatch(
  String text, {
  int max = BatchInput.defaultMax,
  ScanResult Function(String)? analyzer,
}) {
  final parsed = BatchInput.parse(text, max: max);
  final results = analyzer == null
      ? analyzeUrlsSafely(parsed.links)
      : analyzeUrlsSafely(parsed.links, analyzer: analyzer);
  final summary = BatchReportSummary.fromResults(
    results,
    unrecognized: parsed.unrecognized.length,
    overflow: parsed.overflow,
    duplicates: parsed.duplicates,
  );
  final report = buildBatchReport(
    rows: <BatchReportRow>[
      for (var i = 0; i < parsed.links.length; i++)
        BatchReportRow(parsed.links[i], results[i]),
    ],
    unrecognized: parsed.unrecognized,
    overflow: parsed.overflow,
    duplicates: parsed.duplicates,
    maxLinks: max,
  );
  return BatchRun(parsed, results, summary, report);
}

/// معادلة المحاسبة: كل مدخل بيتحسب مرة واحدة بالظبط، ومفيش مدخل بيضيع.
void expectAccounting(BatchRun run, {required int inputTokens, String? reason}) {
  final s = run.summary;
  expect(s.isConsistent, isTrue, reason: reason);
  expect(
    s.recognized,
    s.completed + s.partial + s.invalidInput + s.analysisFailed,
    reason: reason,
  );
  expect(s.unscanned, s.invalidInput + s.analysisFailed, reason: reason);
  expect(
    s.scored,
    s.highRisk + s.mediumRisk + s.lowSignals + s.zeroScore,
    reason: reason,
  );
  expect(
    s.totalAccounted,
    s.recognized + s.unrecognized + s.overflow + s.duplicates,
    reason: reason,
  );
  expect(s.totalAccounted, inputTokens, reason: reason);
  // كل رابط دخل الفحص له نتيجة واحدة بنفس الترتيب.
  expect(run.results.length, run.parsed.links.length, reason: reason);
  // وكل سطر في التقرير بيقابل مدخل دخل الفحص أو نص غير متعرَّف عليه.
  expect(run.itemLines, s.recognized + s.unrecognized, reason: reason);
}

/// الرابط رقم i في الدفعات الكبيرة: بيتنوّع بين كل الحالات (7 حالات متكررة).
const List<String> _kinds = <String>[
  'high',
  'mid',
  'low',
  'partial',
  'zero',
  'badport',
  'boom',
];

String linkFor(int i) => 'https://${_kinds[i % _kinds.length]}$i.example.com/';

String bulkText(int n) =>
    List<String>.generate(n, linkFor, growable: false).join('\n');

void main() {
  group('BatchReportSummary: الحالات المتنافية', () {
    test('summary counts are disjoint: completed, partial, invalid, failed', () {
      final results = <ScanResult>[
        scored(5),
        scored(15, partial: true),
        invalidResult('https://example.invalid:99999/'),
        ScanResult.failed(
          kind: ScanKind.url,
          detail: 'unexpected error',
          title: 'https://example.invalid/',
        ),
      ];

      final summary = BatchReportSummary.fromResults(results);
      expect(summary.recognized, 4);
      expect(summary.completed, 1);
      expect(summary.partial, 1);
      expect(summary.unscanned, 2);
      expect(summary.invalidInput, 1);
      expect(summary.analysisFailed, 1);
      expect(summary.isConsistent, isTrue);
    });
  });

  group('Batch Summary: 12 حالة مطلوبة + معادلة المحاسبة', () {
    test('1) كل الروابط اتحللت بالكامل', () {
      final results = <ScanResult>[scored(0), scored(10), scored(30), scored(80)];
      final s = BatchReportSummary.fromResults(results);
      expect(s.recognized, 4);
      expect(s.completed, 4);
      expect(s.partial, 0);
      expect(s.unscanned, 0);
      expect(s.zeroScore, 1);
      expect(s.lowSignals, 1);
      expect(s.mediumRisk, 1);
      expect(s.highRisk, 1);
      expect(s.totalAccounted, 4);
      expect(s.isConsistent, isTrue);
    });

    test('2) تحليل جزئي: بيتعدّ جزئي مش مكتمل، وعنوانه مش "لا مؤشرات"', () {
      final low = scored(5, partial: true);
      final zero = scored(0, partial: true);
      final s = BatchReportSummary.fromResults(<ScanResult>[low, zero]);
      expect(s.partial, 2);
      expect(s.completed, 0);
      expect(s.unscanned, 0);
      expect(s.isConsistent, isTrue);
      // الدرجة المنخفضة + فحص ناقص: العنوان "فحص جزئي" مش "مؤشرات محدودة" ولا "لا مؤشرات".
      for (final r in <ScanResult>[low, zero]) {
        expect(BatchReportLabels.headline(r), Verdict.partialScan.label);
        expect(BatchReportLabels.headline(r), isNot('مؤشرات محدودة'));
        expect(BatchReportLabels.headline(r), isNot('لا مؤشرات واضحة'));
      }
    });

    test('3) رابط غير صالح هيكليًا (منفذ 99999): غير مفحوص، مش درجة 0 ولا آمن', () {
      final run = runBatch('http://a.com:99999');
      expect(run.results.single.state, ScanState.invalidInput);
      expect(run.results.single.hasScore, isFalse);
      expect(run.summary.invalidInput, 1);
      expect(run.summary.unscanned, 1);
      expect(run.summary.zeroScore, 0);
      expect(run.summary.completed, 0);
      expect(run.report, contains('غير مفحوص (invalid_port'));
      expect(run.report.contains('0/100'), isFalse);
      expectAccounting(run, inputTokens: 1);
    });

    test('4) مدخلات ما اتفحصتش: غير متعرَّف عليها + زايدة عن الحد + مكررة', () {
      // 5 مدخلات: ok1 / ok2 / foo/bar / OK1 (مكرر) / foo/bar (مكرر).
      final run = runBatch(
        'https://ok1.example.com/ https://ok2.example.com/ foo/bar '
        'https://OK1.example.com/ foo/bar',
        max: 1,
        analyzer: fakeAnalyzer,
      );
      expect(run.parsed.links, <String>['https://ok1.example.com/']);
      expect(run.parsed.unrecognized, <String>['foo/bar']);
      expect(run.summary.recognized, 1);
      expect(run.summary.unrecognized, 1);
      expect(run.summary.overflow, 1);
      expect(run.summary.duplicates, 2);
      expect(run.report, contains('غير مفحوص (لم يُتعرّف عليه كرابط) - foo/bar'));
      expect(run.report, contains('تم تجاهل 1 رابطًا'));
      expectAccounting(run, inputTokens: 5);
    });

    test('5) فشل أثناء التحليل: حالة منفصلة (غير مفحوص)، مش آمن ومش جزئي', () {
      final run = runBatch('https://boom1.example.com/', analyzer: fakeAnalyzer);
      final r = run.results.single;
      expect(r.state, ScanState.failed);
      expect(r.hasScore, isFalse);
      expect(BatchReportLabels.headline(r), Verdict.analysisFailed.label);
      expect(run.summary.analysisFailed, 1);
      expect(run.summary.unscanned, 1);
      expect(run.summary.partial, 0);
      expect(run.summary.zeroScore, 0);
      expect(run.report, contains('غير مفحوص (failed'));
      expect(run.report.contains('0/100'), isFalse);
      expectAccounting(run, inputTokens: 1);
    });

    test('6) نص مش رابط: بيتجاهل عمدًا، ومفيش نتيجة "آمن" لحاجة ما اتفحصتش', () {
      final run = runBatch('hello world مرحبا بكم 12345 abc', analyzer: fakeAnalyzer);
      expect(run.parsed.links, isEmpty);
      expect(run.parsed.unrecognized, isEmpty);
      expect(run.results, isEmpty);
      expect(run.summary.recognized, 0);
      expect(run.summary.zeroScore, 0);
      expect(run.summary.totalAccounted, 0);
      expectAccounting(run, inputTokens: 0);
    });

    test('7) دفعة فاضية', () {
      final run = runBatch('', analyzer: fakeAnalyzer);
      expect(run.results, isEmpty);
      final s = run.summary;
      expect(
        <int>[
          s.recognized,
          s.completed,
          s.partial,
          s.unscanned,
          s.invalidInput,
          s.analysisFailed,
          s.highRisk,
          s.mediumRisk,
          s.lowSignals,
          s.zeroScore,
          s.unrecognized,
          s.overflow,
          s.duplicates,
        ],
        everyElement(0),
      );
      expect(s.isConsistent, isTrue);
      expect(run.report, contains('إجمالي المدخلات المحسوبة: 0'));
      expectAccounting(run, inputTokens: 0);
    });

    test('8) 40 رابط: مفيش قص، ولا رابط بيضيع، والتوزيع مظبوط', () {
      const n = 40;
      final run = runBatch(bulkText(n), analyzer: fakeAnalyzer);
      expect(run.parsed.links.length, n);
      expect(run.parsed.overflow, 0);
      expect(run.report, contains('الحد الأقصى لهذه الدفعة: 100 رابط'));
      final counts = <String, int>{
        for (final k in _kinds) k: List<int>.generate(n, (i) => i).where((i) => i % _kinds.length == _kinds.indexOf(k)).length,
      };
      final s = run.summary;
      expect(s.highRisk, counts['high']);
      expect(s.mediumRisk, counts['mid']);
      expect(s.lowSignals, counts['low']! + counts['partial']!);
      expect(s.zeroScore, counts['zero']);
      expect(s.partial, counts['partial']);
      expect(s.invalidInput, counts['badport']);
      expect(s.analysisFailed, counts['boom']);
      expect(s.completed, counts['high']! + counts['mid']! + counts['low']! + counts['zero']!);
      expectAccounting(run, inputTokens: n);
    });

    test('9) 100 رابط بالظبط: كلهم اتفحصوا ومفيش زيادة', () {
      const n = 100;
      final run = runBatch(bulkText(n), analyzer: fakeAnalyzer);
      expect(BatchInput.defaultMax, 100);
      expect(run.parsed.links.length, n);
      expect(run.summary.overflow, 0);
      expect(run.summary.recognized, n);
      expectAccounting(run, inputTokens: n);
    });

    test('10) أكتر من 100 (105 و1000): الزيادة بتتعدّ وما بتتفحصش، والمجموع بيتطابق', () {
      for (final n in <int>[105, 1000]) {
        final run = runBatch(bulkText(n), analyzer: fakeAnalyzer);
        expect(run.parsed.links.length, 100, reason: '$n');
        expect(run.summary.recognized, 100, reason: '$n');
        expect(run.summary.overflow, n - 100, reason: '$n');
        expect(run.results.length, 100, reason: '$n');
        expect(run.report, contains('تم تجاهل ${n - 100} رابطًا'), reason: '$n');
        expectAccounting(run, inputTokens: n, reason: '$n');
      }
    });

    test('11) خطأ في منتصف الدفعة ما يوقّفش الباقي ولا يغيّر الترتيب', () {
      final links = <String>[
        'https://high1.example.com/',
        'https://mid2.example.com/',
        'https://boom3.example.com/',
        'https://low4.example.com/',
        'https://zero5.example.com/',
        'https://high6.example.com/',
      ];
      final results = analyzeUrlsSafely(links, analyzer: fakeAnalyzer);
      expect(results.length, links.length);
      expect(results.map((r) => r.state).toList(), <ScanState>[
        ScanState.completed,
        ScanState.completed,
        ScanState.failed,
        ScanState.completed,
        ScanState.completed,
        ScanState.completed,
      ]);
      expect(results.map((r) => r.hasScore ? r.score : -1).toList(),
          <int>[80, 30, -1, 10, 0, 80]);
      final run = runBatch(links.join(' '), analyzer: fakeAnalyzer);
      expect(run.summary.analysisFailed, 1);
      expect(run.summary.completed, 5);
      expectAccounting(run, inputTokens: links.length);
    });

    test('12) مفيش رابط بيضيع من التقرير المنسوخ (والحروف الخفية بتتكتب أكواد)', () {
      final run = runBatch(
        'https://pay​pal.example.com/login https://high1.example.com/ '
        'http://badport.example.com:99999/ https://boom.example.com/ foo/bar',
        analyzer: fakeAnalyzer,
      );
      expect(run.parsed.links.length, 4);
      expect(run.parsed.unrecognized, <String>['foo/bar']);
      for (final link in run.parsed.links) {
        expect(run.report, contains(InvisibleChars.escapeForDisplay(link)),
            reason: link);
      }
      expect(run.report, contains('pay⟦U+200B (ZWSP)⟧pal.example.com'));
      expect(run.report.contains('​'), isFalse);
      expect(run.report, contains('foo/bar'));
      expectAccounting(run, inputTokens: 5);
    });

    test('المحلل الحقيقي (UrlAnalyzer) على 40 و100 رابط: مفيش رابط بيضيع', () {
      for (final n in <int>[40, 100]) {
        final text = List<String>.generate(
          n,
          (i) => 'https://site$i.example.com/path$i',
        ).join('\n');
        final run = runBatch(text);
        expect(run.results.length, n, reason: '$n');
        expectAccounting(run, inputTokens: n, reason: '$n');
        // مفيش رابط "غير مفحوص" لازم يظهر بدرجة، وبالعكس.
        for (final r in run.results) {
          expect(r.hasScore, r.state == ScanState.completed);
        }
      }
    });
  });

  group('BatchReportSummary.reportLines', () {
    test('بيعرض كل الأعداد ومعادلة المجموع', () {
      final s = BatchReportSummary.fromResults(
        <ScanResult>[scored(0), scored(50), invalidResult('x')],
        unrecognized: 2,
        overflow: 3,
        duplicates: 4,
      );
      final text = s.reportLines(maxLinks: 100).join('\n');
      expect(text, contains('الحد الأقصى لهذه الدفعة: 100 رابط'));
      expect(text, contains('إجمالي المدخلات المحسوبة: 12 = روابط دخلت الفحص 3'));
      expect(text, contains('نصوص لم يُتعرّف عليها كرابط 2'));
      expect(text, contains('روابط زائدة عن الحد 3'));
      expect(text, contains('مكررة 4'));
      expect(text, contains('توزيع الدرجات: خطير 1'));
      expect(text, contains('لم تُفحص: 1'));
    });
  });

  group('BatchReportLabels.headline', () {
    test('low non-zero scores are not described as no indicators', () {
      final result = scored(
        15,
        findings: const <Finding>[
          Finding(
            code: 'nested_url',
            severity: Severity.warn,
            title: 'رابط داخل رابط',
            detail: 'عنوان آخر مضمن',
            points: 15,
          ),
        ],
      );
      expect(BatchReportLabels.headline(result), 'مؤشرات محدودة');
    });

    test('zero-score informational findings are labeled as informational', () {
      final result = scored(
        0,
        findings: const <Finding>[
          Finding(
            code: 'reserved_test_domain',
            severity: Severity.info,
            title: 'نطاق اختباري',
            detail: 'نطاق محجوز',
          ),
        ],
      );
      expect(BatchReportLabels.headline(result), 'ملاحظات معلوماتية فقط');
    });

    test('zero-score result without findings keeps the neutral headline', () {
      expect(BatchReportLabels.headline(scored(0)), 'لا مؤشرات واضحة');
    });

    test('suspicious / dangerous results keep their own headline', () {
      expect(BatchReportLabels.headline(scored(80)), scored(80).headline);
      expect(BatchReportLabels.headline(scored(30)), scored(30).headline);
    });
  });
}
