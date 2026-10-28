import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_media_purge/core/utils/perceptual_hash.dart';
import 'package:smart_media_purge/core/utils/vector_math.dart';
import 'package:smart_media_purge/features/faces/face_clusterer.dart';
import 'package:smart_media_purge/features/ocr/document_classifier.dart';
import 'package:smart_media_purge/features/ocr/ocr_models.dart';
import 'package:smart_media_purge/features/ocr/receipt_parser.dart';
import 'package:smart_media_purge/features/ocr/sensitive_detector.dart';

Float32List _v(List<double> x) => VectorMath.l2Normalize(x);

void main() {
  test('popcount / hamming', () {
    expect(PerceptualHash.popcount64(0), 0);
    expect(PerceptualHash.popcount64(-1), 64);
    expect(PerceptualHash.hamming(0xFF, 0x0F), 4);
  });

  test('vector bytes round trip', () {
    final v = _v([1, 2, 3, 4]);
    final back = VectorMath.fromBytes(VectorMath.toBytes(v));
    expect(back, v);
  });

  test('sensitive detector finds CNIC, valid card, email; ignores bad Luhn', () {
    const text = 'CNIC 35202-1234567-1 card 4111 1111 1111 1111 '
        'bad 1234 5678 9012 3456 mail a.b@example.com';
    final types = SensitiveDetector.scan(text).map((m) => m.type).toList();
    expect(types, containsAll([SensitiveType.cnic, SensitiveType.creditCard, SensitiveType.email]));
    expect(types.where((t) => t == SensitiveType.creditCard).length, 1);
  });

  test('classifier', () {
    expect(DocumentClassifier.classify('SuperMart\nSubtotal 10.00\nGST 1.00\nTotal 11.00\nThank you'),
        DocType.receipt);
    expect(DocumentClassifier.classify('Electricity bill\nAmount due 4,500\nDue date 10/11/2025'),
        DocType.bill);
    expect(DocumentClassifier.classify('National Identity Card\nDate of Birth 01.01.1990'),
        DocType.idCard);
  });

  test('receipt parser', () {
    final m = ReceiptParser.parse('SuperMart\nSubtotal 10.00\nTotal 11.50\n12/03/2025');
    expect(m.merchant, 'SuperMart');
    expect(m.amount, 11.5);
    expect(m.date, DateTime(2025, 3, 12));
  });

  test('face clusterer groups similar, separates different, keeps existing ids', () {
    final a1 = _v([1, 0, 0, 0]);
    final a2 = _v([0.95, 0.1, 0, 0]);
    final b1 = _v([0, 1, 0, 0]);
    final out = FaceClusterer().run([
      FaceVec(1, a1, 7), // already in cluster 7
      FaceVec(2, a2, null),
      FaceVec(3, b1, null),
    ]);
    expect(out.assignment[2], 7);
    expect(out.assignment[3], isNot(7));
    expect(out.assignment[3]! < 0, isTrue); // new cluster
  });
}
