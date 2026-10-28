import 'package:flutter/foundation.dart';

import '../../core/app_services.dart';
import '../duplicates/duplicate_controller.dart' show ScanStatus;
import 'face_models.dart';
import 'face_service.dart';

class FaceController extends ChangeNotifier {
  FaceController(this._s) : _service = FaceService(_s);

  final AppServices _s;
  final FaceService _service;

  ScanStatus status = ScanStatus.idle;
  double progress = 0;
  String message = '';
  String? error;
  double strictness = 0.55;
  List<PersonCluster> clusters = [];

  bool get modelReady => _s.faceEmbedder.isReady;
  List<PersonCluster> get visible => clusters.where((c) => !c.hidden).toList();
  List<PersonCluster> get hidden => clusters.where((c) => c.hidden).toList();

  Future<void> load() async {
    clusters = await _service.repo.clusters();
    notifyListeners();
  }

  void setStrictness(double v) {
    strictness = v;
    notifyListeners();
  }

  Future<void> scan() async {
    if (!await _s.media.ensurePermission()) {
      status = ScanStatus.permissionDenied;
      notifyListeners();
      return;
    }
    status = ScanStatus.scanning;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      await _service.scan(
        threshold: strictness,
        onProgress: (p, m) {
          progress = p;
          message = m;
          notifyListeners();
        },
      );
      status = ScanStatus.done;
      await load();
    } catch (e) {
      error = e.toString();
      status = ScanStatus.error;
    }
    notifyListeners();
  }

  Future<void> rename(int id, String name) async {
    await _service.repo.update(id, {'name': name.trim()});
    await load();
  }

  Future<void> setHidden(int id, bool v) async {
    await _service.repo.update(id, {'hidden': v ? 1 : 0});
    await load();
  }

  Future<void> setLocked(int id, bool v) async {
    await _service.repo.update(id, {'locked': v ? 1 : 0});
    await load();
  }

  Future<List<String>> assetIds(int clusterId) => _service.repo.assetIdsOf(clusterId);
  Future<Map<String, int>> folders(int clusterId) => _service.repo.foldersOf(clusterId);
}
