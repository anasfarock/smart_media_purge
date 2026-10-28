import 'package:flutter/foundation.dart';

import '../../core/app_services.dart';
import 'duplicate_models.dart';
import 'duplicate_service.dart';

enum ScanStatus { idle, scanning, done, error, permissionDenied }

class DuplicateController extends ChangeNotifier {
  DuplicateController(this._s) : _service = DuplicateService(_s);

  final AppServices _s;
  final DuplicateService _service;

  ScanStatus status = ScanStatus.idle;
  double progress = 0;
  String message = '';
  String? error;
  double sensitivity = 0.5;
  List<DuplicateGroup> groups = [];
  final Set<String> selected = {};

  bool get usingNeuralEmbeddings => _s.imageEmbedder.isReady;

  int get reclaimableBytes {
    var total = 0;
    for (final g in groups) {
      for (final i in g.items) {
        if (selected.contains(i.asset.id)) total += i.fp.sizeBytes;
      }
    }
    return total;
  }

  void setSensitivity(double v) {
    sensitivity = v;
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
      groups = await _service.scan(
        sensitivity: sensitivity,
        onProgress: (p, m) {
          progress = p;
          message = m;
          notifyListeners();
        },
      );
      // Pre-select everything except the recommended keeper in each group.
      selected
        ..clear()
        ..addAll(groups.expand((g) => g.items.skip(1).map((i) => i.asset.id)));
      status = ScanStatus.done;
    } catch (e) {
      error = e.toString();
      status = ScanStatus.error;
    }
    notifyListeners();
  }

  /// Toggles deletion for one file, but never lets a whole group be deleted.
  bool toggle(DuplicateGroup g, String assetId) {
    if (selected.contains(assetId)) {
      selected.remove(assetId);
    } else {
      final othersAllSelected = g.items
          .where((i) => i.asset.id != assetId)
          .every((i) => selected.contains(i.asset.id));
      if (othersAllSelected) return false;
      selected.add(assetId);
    }
    notifyListeners();
    return true;
  }

  Future<int> deleteSelected() async {
    final deleted = await _service.delete(selected.toList());
    final gone = deleted.toSet();
    for (final g in groups) {
      g.items.removeWhere((i) => gone.contains(i.asset.id));
    }
    groups.removeWhere((g) => g.items.length < 2);
    selected.removeAll(gone);
    notifyListeners();
    return deleted.length;
  }
}
