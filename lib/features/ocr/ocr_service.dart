import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  const OcrResult(this.text, this.lineHeightCv);
  final String text;
  final double lineHeightCv;
}

/// ML Kit's text recognizer runs fully on-device (Latin model is bundled).
class OcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> recognize(File file) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(file.path));
    final heights = <double>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        heights.add(line.boundingBox.height);
      }
    }
    return OcrResult(result.text, _cv(heights));
  }

  static double _cv(List<double> v) {
    if (v.length < 3) return 0;
    final mean = v.reduce((a, b) => a + b) / v.length;
    if (mean == 0) return 0;
    final variance = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / v.length;
    return math.sqrt(variance) / mean;
  }

  Future<void> dispose() => _recognizer.close();
}
