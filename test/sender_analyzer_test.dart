import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/sender_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SenderAnalyzer', () {
    test('يصنّف رقم الموبايل المصري العادي', () {
      final result = SenderAnalyzer.analyze('01012345678', SenderClaim.none);
      expect(result.type, SenderType.mobile);
      expect(result.normalized, '01012345678');
    });

    test('يوحّد الأرقام العربية والفارسية إلى أرقام ASCII', () {
      final arabic = SenderAnalyzer.analyze('٠١٠١٢٣٤٥٦٧٨', SenderClaim.none);
      final persian = SenderAnalyzer.analyze('۰۱۰۱۲۳۴۵۶۷۸', SenderClaim.none);
      expect(arabic.type, SenderType.mobile);
      expect(persian.type, SenderType.mobile);
      expect(arabic.normalized, '01012345678');
      expect(persian.normalized, '01012345678');
    });

    test('يحوّل رقم مصر الدولي إلى الصيغة المحلية عند التعرف عليه', () {
      final result = SenderAnalyzer.analyze('+20 1012345678', SenderClaim.none);
      expect(result.type, SenderType.mobile);
      expect(result.normalized, '01012345678');
    });

    test('اسم المرسل يظل غير موثّق ولا يُعامل كدليل رسمي', () {
      final result = SenderAnalyzer.analyze('BankName', SenderClaim.bank);
      expect(result.type, SenderType.named);
      expect(result.result.findings.any((f) => f.points == 5), isTrue);
    });

    test('رقم موبايل يدّعي أنه بنك يُظهر عدم التوافق كمؤشر فقط', () {
      final result = SenderAnalyzer.analyze('01012345678', SenderClaim.bank);
      expect(result.type, SenderType.mobile);
      expect(result.result.score, 45);
      expect(result.result.findings.any((f) => f.severity == Severity.danger), isTrue);
    });
  });
}
