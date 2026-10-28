import 'package:image/image.dart' as img;

/// 64-bit difference hash. Because it only compares neighbouring pixels it is
/// invariant to any monotonic brightness/contrast change, which makes it a good
/// cheap pre-filter (and a fallback) for lighting variations.
class PerceptualHash {
  static int dHash(img.Image src) {
    final small = img.copyResize(
      src,
      width: 9,
      height: 8,
      interpolation: img.Interpolation.average,
    );
    var hash = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final l = small.getPixel(x, y).luminance;
        final r = small.getPixel(x + 1, y).luminance;
        hash = (hash << 1) | (l < r ? 1 : 0);
      }
    }
    return hash;
  }

  static int popcount64(int x) {
    x = x - ((x >>> 1) & 0x5555555555555555);
    x = (x & 0x3333333333333333) + ((x >>> 2) & 0x3333333333333333);
    x = (x + (x >>> 4)) & 0x0f0f0f0f0f0f0f0f;
    return ((x * 0x0101010101010101) >>> 56) & 0xff;
  }

  static int hamming(int a, int b) => popcount64(a ^ b);
}
