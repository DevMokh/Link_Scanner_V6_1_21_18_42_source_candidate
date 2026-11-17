import 'package:cobra_shield/services/url_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UrlCleaner', () {
    test('يحذف معاملات التتبع المعروفة ويحافظ على بقية الاستعلام والمسار', () {
      final result = UrlCleaner.clean(
        'https://example.com/path?utm_source=mail&fbclid=abc&keep=a%2Fb#section',
      );
      expect(result.valid, isTrue);
      expect(result.removed, containsAll(<String>['utm_source', 'fbclid']));
      expect(
        result.cleaned,
        'https://example.com/path?keep=a%2Fb#section',
      );
    });

    test('لا يحذف المعامل العام ref لأنه قد يحمل معنى وظيفيًا', () {
      final result = UrlCleaner.clean(
        'https://example.com/item?ref=order-123&utm_campaign=spring',
      );
      expect(result.valid, isTrue);
      expect(result.removed, <String>['utm_campaign']);
      expect(result.cleaned, 'https://example.com/item?ref=order-123');
    });

    test('يتعرف على اسم معامل تتبع مرمّز قبل إزالته', () {
      final result = UrlCleaner.clean(
        'https://example.com/?utm%5Fsource=mail&safe=1',
      );
      expect(result.removed, <String>['utm_source']);
      expect(result.cleaned, 'https://example.com/?safe=1');
    });

    test('يرفض النص الذي لا يحتوي مضيفًا', () {
      final result = UrlCleaner.clean('not a url');
      expect(result.valid, isFalse);
      expect(result.cleaned, 'not a url');
      expect(result.removed, isEmpty);
    });

    test('يرفض مضيفًا من كلمة واحدة حتى لو أضيفت له https تلقائيًا', () {
      for (final input in <String>['not-a-url', 'router/login', 'example']) {
        final result = UrlCleaner.clean(input);
        expect(result.valid, isFalse, reason: input);
        expect(result.cleaned, input, reason: input);
        expect(result.removed, isEmpty, reason: input);
      }
    });

    test('يرفض المسافات داخل العنوان ولا يعدّل النص غير الصالح', () {
      const input = 'https://example.com/a path?utm_source=mail';
      final result = UrlCleaner.clean(input);
      expect(result.valid, isFalse);
      expect(result.cleaned, input);
      expect(result.removed, isEmpty);
    });

    test('لا يعيد كتابة رابط مموّه أو يزيل أدلته', () {
      const input = 'hxxps[:]//example[.]com/?utm_source=mail';
      final result = UrlCleaner.clean(input);
      expect(result.valid, isFalse);
      expect(result.cleaned, input);
      expect(result.removed, isEmpty);
    });

    test('يقبل دومينًا معروفًا بدون scheme ويحافظ على شكل الخرج', () {
      final result = UrlCleaner.clean('example.com/path?utm_source=mail&keep=1');
      expect(result.valid, isTrue);
      expect(result.removed, <String>['utm_source']);
      expect(result.cleaned, 'example.com/path?keep=1');
    });
  });
}
