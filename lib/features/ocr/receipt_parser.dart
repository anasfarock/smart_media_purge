/// Pulls structured metadata (merchant, total, date) out of raw OCR text.
class ParsedMetadata {
  const ParsedMetadata({this.merchant, this.amount, this.date});
  final String? merchant;
  final double? amount;
  final DateTime? date;
}

class ReceiptParser {
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static ParsedMetadata parse(String text) => ParsedMetadata(
        merchant: _merchant(text),
        amount: _amount(text),
        date: _date(text),
      );

  static String? _merchant(String text) {
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (RegExp(r'[A-Za-z]{3,}').hasMatch(line) && line.length <= 40) return line;
    }
    return null;
  }

  static final _num = RegExp(r'\d[\d,]*(?:\.\d{1,2})?');

  static double? _amount(String text) {
    final lines = text.split('\n');
    const keys = [
      'grand total', 'amount due', 'total due', 'net payable',
      'balance due', 'total amount', 'total',
    ];
    for (final key in keys) {
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].toLowerCase();
        if (!l.contains(key) || l.contains('subtotal') || l.contains('sub total')) continue;
        for (final candidate in [lines[i], if (i + 1 < lines.length) lines[i + 1]]) {
          final nums = _num.allMatches(candidate).toList();
          if (nums.isNotEmpty) {
            final v = double.tryParse(nums.last.group(0)!.replaceAll(',', ''));
            if (v != null) return v;
          }
        }
      }
    }
    // Fallback: the largest decimal number on the page.
    double? best;
    for (final m in RegExp(r'\d[\d,]*\.\d{2}').allMatches(text)) {
      final v = double.tryParse(m.group(0)!.replaceAll(',', ''));
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  static DateTime? _date(String text) {
    final now = DateTime.now();
    bool ok(DateTime d) => d.year >= 2000 && d.year <= now.year + 1;

    final iso = RegExp(r'(?<!\d)(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)').firstMatch(text);
    if (iso != null) {
      final d = _safe(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
      if (d != null && ok(d)) return d;
    }

    final dmy = RegExp(r'(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})(?!\d)').firstMatch(text);
    if (dmy != null) {
      var a = int.parse(dmy.group(1)!);
      var b = int.parse(dmy.group(2)!);
      var y = int.parse(dmy.group(3)!);
      if (y < 100) y += 2000;
      // Day-first unless the second number can only be a day.
      final d = (b > 12 && a <= 12) ? _safe(y, a, b) : _safe(y, b, a);
      if (d != null && ok(d)) return d;
    }

    final named = RegExp(
      r'(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) {
      final d = _safe(int.parse(named.group(3)!),
          _months[named.group(2)!.toLowerCase()]!, int.parse(named.group(1)!));
      if (d != null && ok(d)) return d;
    }
    return null;
  }

  static DateTime? _safe(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }
}
