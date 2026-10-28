import 'ocr_models.dart';

/// Lightweight on-device classifier: keyword scoring + a layout heuristic
/// for handwriting. Swap in a TFLite text classifier later without touching callers.
class DocumentClassifier {
  static const _receipt = [
    'receipt', 'subtotal', 'sub total', 'total', 'change due', 'cash', 'qty',
    'thank you', 'gst', 'vat', 'sales tax', 'tax invoice', 'pos', 'item',
  ];
  static const _bill = [
    'amount due', 'due date', 'bill', 'invoice', 'account no', 'account number',
    'billing period', 'units consumed', 'statement', 'electricity', 'utility',
    'payable', 'meter', 'customer id', 'consumer no',
  ];
  static const _id = [
    'identity card', 'national identity', 'cnic', 'passport', 'date of birth',
    'dob', 'date of issue', 'date of expiry', 'father', 'driver licen',
    'nationality', 'id no', 'islamic republic',
  ];

  static int _hits(String t, List<String> words) =>
      words.where((w) => t.contains(w)).length;

  /// [lineHeightCv] = coefficient of variation of OCR line heights
  /// (printed text is uniform, handwriting is not).
  static DocType classify(String text, {double lineHeightCv = 0}) {
    final t = text.toLowerCase();
    final id = _hits(t, _id);
    final bill = _hits(t, _bill);
    final receipt = _hits(t, _receipt);

    if (id >= 2) return DocType.idCard;
    if (bill >= 2 && bill >= receipt - 1) return DocType.bill;
    if (receipt >= 2) return DocType.receipt;
    if (bill >= 1 && RegExp(r'\d').hasMatch(t)) return DocType.bill;
    if (lineHeightCv > 0.45 && text.trim().length > 20) return DocType.handwritten;
    return DocType.other;
  }
}
