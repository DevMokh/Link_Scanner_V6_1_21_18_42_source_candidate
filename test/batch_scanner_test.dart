import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/batch_scanner.dart';
import 'package:cobra_shield/services/url_analyzer.dart';

void main() {
  test('background batch scan preserves order and local analyzer results', () async {
    const urls = <String>[
      'https://www.google.com/',
      'https://paypa1.com/signin',
      'javascript:alert(1)',
      'https://example.com/path',
    ];

    final actual = await scanUrlsInBackground(urls);
    expect(actual, hasLength(urls.length));

    for (var i = 0; i < urls.length; i++) {
      final expected = UrlAnalyzer.analyze(urls[i]);
      expect(actual[i].score, expected.score, reason: urls[i]);
      expect(actual[i].state, expected.state, reason: urls[i]);
      expect(
        actual[i].findings.map((finding) => finding.code).toList(),
        expected.findings.map((finding) => finding.code).toList(),
        reason: urls[i],
      );
    }
  });

  group('analyzeUrlsSafely', () {
    ScanResult flaky(String url) {
      if (url.contains('boom')) throw StateError('boom');
      return ScanResult(kind: ScanKind.url, score: 7, findings: const <Finding>[]);
    }

    test('استثناء في رابط واحد ما يوقّفش الباقي ولا يغيّر العدد أو الترتيب', () {
      const urls = <String>[
        'https://a.example.com/',
        'https://boom.example.com/',
        'https://c.example.com/',
      ];
      final results = analyzeUrlsSafely(urls, analyzer: flaky);
      expect(results, hasLength(3));
      expect(results[0].state, ScanState.completed);
      expect(results[1].state, ScanState.failed);
      expect(results[1].hasScore, isFalse);
      expect(results[1].title, 'https://boom.example.com/');
      expect(results[2].state, ScanState.completed);
      expect(results[2].score, 7);
    });

    test('قائمة فاضية = نتائج فاضية', () async {
      expect(analyzeUrlsSafely(const <String>[]), isEmpty);
      expect(await scanUrlsInBackground(const <String>[]), isEmpty);
    });

    test('100 رابط في الخلفية: نفس العدد ونفس الترتيب ونفس الدرجات', () async {
      final urls = List<String>.generate(
        100,
        (i) => 'https://site$i.example.com/path$i',
      );
      final actual = await scanUrlsInBackground(urls);
      expect(actual, hasLength(100));
      for (var i = 0; i < urls.length; i++) {
        final expected = UrlAnalyzer.analyze(urls[i]);
        expect(actual[i].score, expected.score, reason: urls[i]);
        expect(actual[i].state, expected.state, reason: urls[i]);
      }
    });
  });
}
