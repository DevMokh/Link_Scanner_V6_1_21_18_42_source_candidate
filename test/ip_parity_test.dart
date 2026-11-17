import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/services/advanced_scanner.dart';
import 'package:cobra_shield/services/net_guard.dart';
import 'package:cobra_shield/services/url_normalizer.dart';

/// تطابق تصنيف عناوين IP بين المحلل المحلي ([UrlNormalizer]) وحارس الشبكة ([NetGuard]).
///
/// القاعدة: أي عنوان يمنعه NetGuard لازم المحلل يصنّفه "مش عام" (private / loopback /
/// linklocal / reserved / documentation / unspecified)، والعكس. وإلا ممكن عنوان يتحسب
/// "IP عام مباشر" (نقاط خطورة) بينما الفحص المتقدم شايفه داخلي، أو العكس.
void main() {
  const publicKind = 'public';

  group('تطابق IPv6', () {
    // عناوين لازم تتمنع (وتتصنّف غير عامة).
    const nonPublic = <String>[
      '::',
      '::1',
      '0:0:0:0:0:0:0:1',
      '::808:808', // IPv4-compatible القديمة: تُمنع بالكامل حتى لو الـ IPv4 المضمّن عام
      '::2',
      '::c0a8:101',
      '::ffff:127.0.0.1',
      '::ffff:c0a8:101',
      '::ffff:0:808:808', // IPv4-translated: خارج 2000::/3
      '64:ff9b::7f00:1',
      '64:ff9b:1::1',
      '64:ff9b:2::1', // داخل 64:ff9b::/32 لكن مش /96
      '2001:0::1',
      '2001:20::1',
      '2001:100::1',
      '2001:db8::1',
      '3fff::1',
      '3fff:fff::1',
      '4000::1',
      '8000::1',
      'e000::1',
      '2002:7f00:1::',
      '2002:c0a8:101::',
      '100::1',
      'fe80::1',
      'fec0::1',
      'fd00::1',
      'ff02::1',
    ];
    // عناوين عامة لازم تعدّي في الاتنين.
    const publicAddresses = <String>[
      '::ffff:8.8.8.8',
      '64:ff9b::808:808',
      '2002:808:808::',
      '2001:200::1',
      '2001:4860:4860::8888',
      '2606:4700:4700::1111',
      '2a00:1450:4001::200e',
      '3fff:1000::1',
    ];

    for (final text in nonPublic) {
      test('غير عام في الاتنين: $text', () {
        final info = UrlNormalizer.parseIpv6(text);
        expect(info, isNotNull, reason: text);
        expect(info!.kind, isNot(publicKind), reason: text);
        expect(NetGuard.isBlockedAddress(InternetAddress(text)), isTrue,
            reason: text);
      });
    }

    for (final text in publicAddresses) {
      test('عام في الاتنين: $text', () {
        final info = UrlNormalizer.parseIpv6(text);
        expect(info, isNotNull, reason: text);
        expect(info!.kind, publicKind, reason: text);
        expect(NetGuard.isBlockedAddress(InternetAddress(text)), isFalse,
            reason: text);
      });
    }

    test('التصنيفات المحددة للعناوين الجديدة', () {
      expect(UrlNormalizer.parseIpv6('3fff::1')!.kind, 'documentation');
      expect(UrlNormalizer.parseIpv6('2001:20::1')!.kind, 'reserved');
      expect(UrlNormalizer.parseIpv6('4000::1')!.kind, 'reserved');
      expect(UrlNormalizer.parseIpv6('::808:808')!.kind, 'reserved');
      expect(UrlNormalizer.parseIpv6('64:ff9b:2::1')!.kind, 'reserved');
      // IPv4-compatible بعنوان داخلي بيحتفظ بنوعه.
      expect(UrlNormalizer.parseIpv6('::c0a8:101')!.kind, 'private');
    });

    test('التخطي الوقائي بيشمل العناوين الجديدة قبل أي اتصال', () {
      for (final host in <String>['3fff::1', '4000::1', '::808:808', '2001:20::1']) {
        expect(
          AdvancedScanner.protectiveSkipReason('http://[$host]/login', host),
          isNotNull,
          reason: host,
        );
      }
      expect(
        AdvancedScanner.protectiveSkipReason(
            'http://[2606:4700:4700::1111]/', '2606:4700:4700::1111'),
        isNull,
      );
    });
  });

  group('تطابق IPv4', () {
    const nonPublic = <String>[
      '0.0.0.0',
      '10.0.0.1',
      '100.64.0.0',
      '100.127.255.255',
      '127.0.0.1',
      '169.254.1.1',
      '172.16.0.0',
      '172.31.255.255',
      '192.0.0.5',
      '192.0.2.7',
      '192.88.99.1',
      '192.168.0.1',
      '198.18.0.1',
      '198.19.255.255',
      '198.51.100.9',
      '203.0.113.9',
      '224.0.0.1',
      '255.255.255.255',
    ];
    const publicAddresses = <String>[
      '8.8.8.8',
      '100.63.255.255',
      '100.128.0.0',
      '172.15.255.255',
      '172.32.0.0',
      '192.0.3.1',
      '192.88.100.1',
      '198.17.255.255',
      '198.20.0.0',
      '198.51.101.1',
      '203.0.114.1',
      '223.255.255.255',
    ];

    for (final text in nonPublic) {
      test('غير عام في الاتنين: $text', () {
        final info = UrlNormalizer.parseIpv4(text);
        expect(info, isNotNull, reason: text);
        expect(info!.kind, isNot(publicKind), reason: text);
        expect(NetGuard.isBlockedAddress(InternetAddress(text)), isTrue,
            reason: text);
      });
    }

    for (final text in publicAddresses) {
      test('عام في الاتنين: $text', () {
        final info = UrlNormalizer.parseIpv4(text);
        expect(info, isNotNull, reason: text);
        expect(info!.kind, publicKind, reason: text);
        expect(NetGuard.isBlockedAddress(InternetAddress(text)), isFalse,
            reason: text);
      });
    }
  });
}
