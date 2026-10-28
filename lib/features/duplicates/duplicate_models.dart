import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../../core/utils/vector_math.dart';

class MediaFingerprint {
  MediaFingerprint({
    required this.assetId,
    required this.modified,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.ext,
    required this.dhash,
    this.sha256,
    this.embedding,
  });

  final String assetId;
  final int modified;
  final int sizeBytes;
  final int width;
  final int height;
  final String ext;
  final int dhash;
  String? sha256;
  final Float32List? embedding;

  Map<String, Object?> toMap() => {
        'asset_id': assetId,
        'modified': modified,
        'size_bytes': sizeBytes,
        'width': width,
        'height': height,
        'ext': ext,
        'sha256': sha256,
        'dhash': dhash,
        'embedding': embedding == null ? null : VectorMath.toBytes(embedding!),
      };

  factory MediaFingerprint.fromMap(Map<String, Object?> m) {
    final blob = m['embedding'] as Uint8List?;
    return MediaFingerprint(
      assetId: m['asset_id'] as String,
      modified: m['modified'] as int,
      sizeBytes: m['size_bytes'] as int,
      width: m['width'] as int,
      height: m['height'] as int,
      ext: m['ext'] as String,
      sha256: m['sha256'] as String?,
      dhash: m['dhash'] as int,
      embedding: blob == null ? null : VectorMath.fromBytes(blob),
    );
  }
}

class DuplicateItem {
  DuplicateItem({required this.asset, required this.fp}) : quality = QualityScorer.score(fp);

  final AssetEntity asset;
  final MediaFingerprint fp;
  final double quality;

  String get description =>
      '${fp.width}x${fp.height} - ${(fp.width * fp.height / 1e6).toStringAsFixed(1)} MP';

  /// Higher quality first; tie-break on larger file, then older (likely the original).
  static int rank(DuplicateItem a, DuplicateItem b) {
    final q = b.quality.compareTo(a.quality);
    if (q != 0) return q;
    final s = b.fp.sizeBytes.compareTo(a.fp.sizeBytes);
    if (s != 0) return s;
    return a.asset.createDateTime.compareTo(b.asset.createDateTime);
  }
}

class DuplicateGroup {
  DuplicateGroup({required this.id, required this.items, required this.exact});

  final int id;
  final bool exact;

  /// Sorted best-first, so `items.first` is the recommended file to keep.
  final List<DuplicateItem> items;

  DuplicateItem get recommended => items.first;
}

/// Ranks files by "how much picture you actually have":
/// resolution first, then how lightly the file is compressed (bytes per pixel).
class QualityScorer {
  static double score(MediaFingerprint f) {
    final pixels = (f.width * f.height).toDouble();
    if (pixels <= 0) return 0;
    final bytesPerPixel = f.sizeBytes / pixels;
    // ~1.2 B/px is a visually clean JPEG; lossless formats are well above it.
    final compression = (bytesPerPixel / 1.2).clamp(0.2, 1.0);
    return (pixels / 1e6) * (0.5 + 0.5 * compression);
  }
}
