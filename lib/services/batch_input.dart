import 'public_suffix.dart';

/// نتيجة تقسيم نص الفحص المجمّع.
class BatchParse {
  const BatchParse({
    required this.links,
    required this.unrecognized,
    required this.overflow,
    this.duplicates = 0,
  });

  /// الروابط اللي هتتفحص (بحد أقصى [BatchInput.defaultMax]).
  final List<String> links;

  /// نصوص شكلها مسار/رابط (فيها / أو \) لكن مش قابلة للتعرف كرابط. بتتعرض للمستخدم
  /// بدل ما تتسقّط بصمت.
  final List<String> unrecognized;

  /// عدد الروابط الزايدة عن الحد.
  final int overflow;

  /// عدد النصوص المكررة (بصرف النظر عن حالة الحروف) اللي اندمجت مع نص سابق.
  final int duplicates;
}

/// تقسيم نص الفحص المجمّع لروابط. اتفصل عن الواجهة عشان يتختبر لوحده.
///
/// المبدأ: ما نسقّطش رابط مموّه بصمت. قبل كده أي نص فيه @ من غير http كان بيتتجاهل
/// (لتفادي الإيميلات)، فكان أخطر الروابط (hxxp:\\www.google.com@0x7f000001/...) بيختفي
/// من التقرير. دلوقتي الإيميل الحقيقي بس هو اللي بيتتجاهل.
class BatchInput {
  BatchInput._();

  static const int defaultMax = 100;

  static final RegExp _split = RegExp('[\\s,;،؛]+');
  static final RegExp _lead = RegExp('^[(\\[{«"\']+');

  /// بادئة بروتوكول بأي شكل: http:// hxxp:\\ https:/ hxxps://
  static final RegExp _schemeLike =
      RegExp(r'^[a-z]{2,10}(?::|\\)[/\\]{1,3}', caseSensitive: false);

  /// مضيف رقمي بدون نقط (0x7f000001 أو 3232235777) متبوع بمسار أو منفذ.
  static final RegExp _hexHost =
      RegExp(r'^0x[0-9a-f]{6,8}(?:[/:?#\\]|$)', caseSensitive: false);
  static final RegExp _decimalHost = RegExp(r'^\d{8,10}[/:?#\\]');

  static final RegExp _emailShape =
      RegExp(r'^[^\s@/:\\?#]+@[^\s@/:\\?#]+\.[a-z]{2,}$', caseSensitive: false);

  /// إيميل حقيقي (ahmed@gmail.com). لو الجزء قبل @ مكتوب كاسم موقع (paypal.com@evil.com)
  /// فده رابط مموّه مش إيميل.
  static bool isEmail(String tok) {
    if (!_emailShape.hasMatch(tok)) return false;
    final local = tok.substring(0, tok.indexOf('@')).toLowerCase();
    final dot = local.lastIndexOf('.');
    if (dot > 0 &&
        PublicSuffixList.instance.isKnownTld(local.substring(dot + 1))) {
      return false;
    }
    return true;
  }

  /// علامات ترقيم بتتشال من آخر النص دايمًا.
  static const String _alwaysTrail = '.,;:!?»"\'';

  static int _count(String text, int end, String ch) {
    var n = 0;
    for (var i = 0; i < end; i++) {
      if (text[i] == ch) n++;
    }
    return n;
  }

  /// بيشيل علامات الترقيم الزايدة من آخر الرابط. الأقواس اللي بتقفل `) ] }` بتتشال بس
  /// لو أكتر من اللي اتفتحت جوّا النص، عشان روابط زي `.../Python_(language)` ما تتقطعش.
  static String _stripTrailing(String tok) {
    var end = tok.length;
    while (end > 0) {
      final ch = tok[end - 1];
      if (_alwaysTrail.contains(ch)) {
        end--;
        continue;
      }
      final open = ch == ')'
          ? '('
          : ch == ']'
              ? '['
              : ch == '}'
                  ? '{'
                  : null;
      if (open != null && _count(tok, end, ch) > _count(tok, end, open)) {
        end--;
        continue;
      }
      break;
    }
    return tok.substring(0, end);
  }

  static bool looksLikeLink(String tok) {
    final low = tok.toLowerCase();
    if (low.startsWith('http://') ||
        low.startsWith('https://') ||
        low.startsWith('www.')) {
      return true;
    }
    if (_schemeLike.hasMatch(low) ||
        _hexHost.hasMatch(low) ||
        _decimalHost.hasMatch(low)) {
      return true;
    }
    if (tok.contains('@') && isEmail(tok)) return false;
    return tok.contains('.');
  }

  static BatchParse parse(String text, {int max = defaultMax}) {
    final seen = <String>{};
    final all = <String>[];
    final unrecognized = <String>[];
    var duplicates = 0;
    for (var tok in text.split(_split)) {
      tok = _stripTrailing(tok.replaceAll(_lead, ''));
      if (tok.length < 4) continue;
      final low = tok.toLowerCase();
      if (looksLikeLink(tok)) {
        if (seen.add(low)) {
          all.add(tok);
        } else {
          duplicates++;
        }
      } else if (tok.contains('/') || tok.contains('\\')) {
        if (seen.add(low)) {
          unrecognized.add(tok);
        } else {
          duplicates++;
        }
      }
    }
    final overflow = all.length > max ? all.length - max : 0;
    return BatchParse(
      links: all.take(max).toList(),
      unrecognized: unrecognized,
      overflow: overflow,
      duplicates: duplicates,
    );
  }
}
