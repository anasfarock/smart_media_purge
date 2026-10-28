import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/app_services.dart';
import '../duplicates/duplicate_controller.dart' show ScanStatus;
import 'document_classifier.dart';
import 'ocr_models.dart';
import 'ocr_repository.dart';
import 'ocr_service.dart';
import 'receipt_parser.dart';
import 'sensitive_detector.dart';
import 'tax_organizer.dart';

enum OcrScope { likelyDocuments, everything }

class OcrController extends ChangeNotifier {
  OcrController(this._s) : _repo = OcrRepository(_s.db.db);

  final AppServices _s;
  final OcrRepository _repo;
  final _ocr = OcrService();
  final _tax = TaxOrganizer();

  ScanStatus status = ScanStatus.idle;
  double progress = 0;
  String message = '';
  String query = '';
  DocType? filter;
  OcrScope scope = OcrScope.likelyDocuments;
  List<DocumentRecord> results = [];
  Map<DocType, int> counts = {};
  Timer? _debounce;

  static const _maxPerRun = 400;
  static const _docFolders = [
    'screenshot', 'document', 'download', 'scan', 'camscanner', 'receipt', 'whatsapp',
  ];

  Future<void> refresh() async {
    results = await _repo.search(query: query, type: filter);
    counts = await _repo.counts();
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  void setFilter(DocType? t) {
    filter = t;
    refresh();
  }

  void setScope(OcrScope s) {
    scope = s;
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
    notifyListeners();
    try {
      final assets = await _s.media.loadImages();
      final known = await _repo.indexedModified();
      final todo = assets.where((a) {
        if (known[a.id] == (a.modifiedDateSecond ?? 0)) return false;
        if (scope == OcrScope.everything) return true;
        final path = (a.relativePath ?? '').toLowerCase();
        return _docFolders.any(path.contains);
      }).take(_maxPerRun).toList();

      for (var i = 0; i < todo.length; i++) {
        final a = todo[i];
        progress = i / todo.length;
        message = 'Reading ${i + 1} of ${todo.length}';
        notifyListeners();

        final file = await a.originFile;
        if (file == null) continue;
        String body = '';
        var type = DocType.other;
        ParsedMetadata meta = const ParsedMetadata();
        var sensitive = 0;
        try {
          final r = await _ocr.recognize(file);
          body = r.text.trim();
          if (body.length >= 15) {
            type = DocumentClassifier.classify(body, lineHeightCv: r.lineHeightCv);
            meta = ReceiptParser.parse(body);
            sensitive = SensitiveDetector.scan(body).length;
          } else {
            body = ''; // not a text document; stored empty so we don't re-scan it
          }
        } catch (_) {
          continue;
        }
        await _repo.upsert(DocumentRecord(
          assetId: a.id,
          modified: a.modifiedDateSecond ?? 0,
          type: type,
          body: body,
          merchant: meta.merchant,
          amount: meta.amount,
          date: meta.date,
          sensitiveCount: sensitive,
        ));
      }
      status = ScanStatus.done;
      await refresh();
    } catch (_) {
      status = ScanStatus.error;
    }
    notifyListeners();
  }

  Future<TaxExportResult> buildTaxFolders() async =>
      _tax.export(await _repo.taxDocuments());

  @override
  void dispose() {
    _debounce?.cancel();
    _ocr.dispose();
    super.dispose();
  }
}
