import 'dart:math' as math;
import 'dart:typed_data';

class VectorMath {
  static Float32List l2Normalize(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    final out = Float32List(v.length);
    if (norm == 0) return out;
    for (var i = 0; i < v.length; i++) {
      out[i] = v[i] / norm;
    }
    return out;
  }

  static double dot(Float32List a, Float32List b) {
    final n = math.min(a.length, b.length);
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static double norm(Float32List a) => math.sqrt(dot(a, a));

  static Uint8List toBytes(Float32List v) =>
      Uint8List.fromList(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes));

  /// Copies into a fresh buffer so the 4-byte alignment requirement always holds.
  static Float32List fromBytes(Uint8List b) =>
      Uint8List.fromList(b).buffer.asFloat32List();
}
