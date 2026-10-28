import 'ocr_models.dart';

/// Regex + checksum based detector for personal identifiers in OCR text.
class SensitiveDetector {
  static final _rules = <SensitiveType, RegExp>{
    // Pakistani CNIC: 12345-1234567-1
    SensitiveType.cnic: RegExp(r'(?<!\d)\d{5}-\d{7}-\d(?!\d)'),
    SensitiveType.ssn: RegExp(r'(?<!\d)\d{3}-\d{2}-\d{4}(?!\d)'),
    SensitiveType.creditCard: RegExp(r'(?<!\d)(?:\d[ -]?){13,19}(?!\d)'),
    SensitiveType.iban: RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b'),
    SensitiveType.email:
        RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
    SensitiveType.phone: RegExp(
        r'(?<!\d)(?:(?:\+\d{1,3}|0)[ -]?\d{2,4}[ -]?\d{6,8}|\(?\d{3}\)?[ -]\d{3}-\d{4})(?!\d)'),
    SensitiveType.passport: RegExp(r'\b[A-Z]{1,2}\d{7}\b'),
  };

  static List<SensitiveMatch> scan(String text) {
    final found = <SensitiveMatch>[];
    _rules.forEach((type, re) {
      for (final m in re.allMatches(text)) {
        if (type == SensitiveType.creditCard) {
          final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
          if (digits.length < 13 || digits.length > 19 || !luhn(digits)) continue;
        }
        found.add(SensitiveMatch(type, m.start, m.end));
      }
    });
    // Resolve overlaps: earliest start wins, then the longest span.
    found.sort((a, b) {
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : (b.end - b.start).compareTo(a.end - a.start);
    });
    final result = <SensitiveMatch>[];
    var lastEnd = -1;
    for (final m in found) {
      if (m.start >= lastEnd) {
        result.add(m);
        lastEnd = m.end;
      }
    }
    return result;
  }

  static bool luhn(String digits) {
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (alt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      alt = !alt;
    }
    return sum % 10 == 0;
  }
}
