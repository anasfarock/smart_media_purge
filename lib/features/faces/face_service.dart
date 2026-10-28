import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/app_services.dart';
import '../../core/utils/vector_math.dart';
import '../duplicates/duplicate_service.dart' show ProgressCallback;
import 'face_clusterer.dart';
import 'face_models.dart';
import 'face_repository.dart';

class FaceModelMissing implements Exception {
  @override
  String toString() =>
      'Face model not found. Add assets/models/mobilefacenet.tflite (see README).';
}

class FaceService {
  FaceService(this._s) : repo = FaceRepository(_s.db.db);

  final AppServices _s;
  final FaceRepository repo;

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.08,
    ),
  );

  static const _detectSize = ThumbnailSize(1024, 1024);

  Future<void> scan({double threshold = 0.55, ProgressCallback? onProgress}) async {
    if (!_s.faceEmbedder.isReady) throw FaceModelMissing();

    final assets = await _s.media.loadImages();
    final done = await repo.scannedAssetIds();
    final todo = assets.where((a) => !done.contains(a.id)).toList();
    final cache = await getTemporaryDirectory();

    for (var i = 0; i < todo.length; i++) {
      onProgress?.call(0.9 * i / math.max(todo.length, 1),
          'Finding faces ${i + 1} of ${todo.length}');
      try {
        await _processAsset(todo[i], cache);
      } catch (_) {
        await repo.saveFaces(todo[i].id, const []); // don't retry broken files forever
      }
    }

    onProgress?.call(0.95, 'Grouping people');
    final out = FaceClusterer(threshold: threshold).run(await repo.allVectors());
    await repo.applyClustering(out);
    onProgress?.call(1, 'Done');
  }

  Future<void> _processAsset(AssetEntity asset, Directory cache) async {
    final bytes = await asset.thumbnailDataWithSize(_detectSize, quality: 90);
    if (bytes == null) {
      await repo.saveFaces(asset.id, const []);
      return;
    }
    // ML Kit reads from a file path; keep the temp copy only for the call.
    final tmp = File(p.join(cache.path, 'face_${asset.id.hashCode}.jpg'));
    await tmp.writeAsBytes(bytes, flush: true);
    List<Face> faces;
    try {
      faces = await _detector.processImage(InputImage.fromFilePath(tmp.path));
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }

    final decoded = img.decodeImage(bytes);
    final rows = <FaceRow>[];
    if (decoded != null) {
      final album = asset.relativePath ?? 'Unknown';
      for (final f in faces) {
        final r = f.boundingBox;
        final yaw = f.headEulerAngleY;
        if (r.width < 64 || r.height < 64) continue; // too small to embed reliably
        if (yaw != null && yaw.abs() > 40) continue; // strong profile
        final crop = _cropFace(decoded, r);
        final emb = _s.faceEmbedder.embed(crop);
        if (emb == null) continue;
        rows.add(FaceRow(
          assetId: asset.id,
          album: album,
          area: (r.width * r.height) / (decoded.width * decoded.height),
          embedding: VectorMath.toBytes(emb),
          thumb: Uint8List.fromList(
              img.encodeJpg(img.copyResize(crop, width: 96, height: 96), quality: 80)),
        ));
      }
    }
    await repo.saveFaces(asset.id, rows);
  }

  /// Square crop with 30% margin. (No landmark alignment yet - see README.)
  img.Image _cropFace(img.Image src, Rect r) {
    final side = math.max(r.width, r.height) * 1.3;
    final x = (r.center.dx - side / 2).round().clamp(0, src.width - 1).toInt();
    final y = (r.center.dy - side / 2).round().clamp(0, src.height - 1).toInt();
    final w = math.min(side.round(), src.width - x);
    final h = math.min(side.round(), src.height - y);
    final crop = img.copyCrop(src, x: x, y: y, width: w, height: h);
    return img.copyResize(crop, width: 112, height: 112);
  }

  Future<void> dispose() => _detector.close();
}
