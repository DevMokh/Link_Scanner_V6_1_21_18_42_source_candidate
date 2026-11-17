import 'url_normalizer.dart';
import 'url_validator.dart';

class CleanResult {
  const CleanResult(this.cleaned, this.removed, this.valid);

  final String cleaned;
  final List<String> removed;
  final bool valid;
}

/// ينظّف الرابط من متتبعات الإعلانات (utm_ و fbclid و gclid ...) بدون أي اتصال.
class UrlCleaner {
  UrlCleaner._();

  static const Set<String> _exact = <String>{
    'fbclid', 'gclid', 'dclid', 'gbraid', 'wbraid', 'msclkid', 'yclid',
    'igshid', 'igsh', 'mc_cid', 'mc_eid', '_ga', '_gl', 'ref_src',
    'ref_url', 'si', 'spm', 'vero_id', 'mkt_tok', 'twclid', 'ttclid',
    's_cid', 'cmpid', 'trk', 'oly_enc_id', 'oly_anon_id',
  };

  static final RegExp _scheme =
      RegExp(r'^[a-z][a-z0-9+.\-]*://', caseSensitive: false);

  static bool _isTracking(String key) {
    final k = key.toLowerCase();
    return k.startsWith('utm_') || _exact.contains(k);
  }

  static CleanResult clean(String input) {
    final raw = input.trim();
    final hasScheme = _scheme.hasMatch(raw);
    // Do not let Uri.tryParse alone decide whether arbitrary text is a URL:
    // it accepts some malformed authorities after a synthetic https:// prefix.
    // Use the same structural validator as the scanner before changing the URL.
    if (raw.isEmpty || RegExp(r'\s').hasMatch(raw)) {
      return CleanResult(raw, const <String>[], false);
    }
    final normalized = UrlNormalizer.normalize(raw);
    final validation = UrlValidator.check(raw, normalized);
    // Defanged or structurally deceptive URLs must remain untouched so the
    // cleaner never rewrites evidence or changes which host a user sees.
    if (!validation.ok ||
        normalized.defanged ||
        normalized.hostDelimiterTrick ||
        normalized.separatorLookalike ||
        normalized.hostEncoded) {
      return CleanResult(raw, const <String>[], false);
    }
    final u = Uri.tryParse(hasScheme ? raw : 'https://$raw');
    if (u == null || u.host.isEmpty) {
      return CleanResult(raw, const <String>[], false);
    }

    final kept = <String>[];
    final removed = <String>[];
    for (final part in u.query.split('&')) {
      if (part.isEmpty) continue;
      final key = part.split('=').first;
      String decoded;
      try {
        decoded = Uri.decodeQueryComponent(key);
      } catch (_) {
        decoded = key;
      }
      if (_isTracking(decoded)) {
        removed.add(decoded);
      } else {
        kept.add(part);
      }
    }

    final sb = StringBuffer();
    if (hasScheme) {
      sb.write(u.scheme);
      sb.write('://');
    }
    if (u.userInfo.isNotEmpty) {
      sb.write(u.userInfo);
      sb.write('@');
    }
    sb.write(u.host);
    if (u.hasPort) sb.write(':${u.port}');
    sb.write(u.path);
    if (kept.isNotEmpty) sb.write('?${kept.join('&')}');
    if (u.fragment.isNotEmpty) sb.write('#${u.fragment}');
    return CleanResult(sb.toString(), removed, true);
  }
}
