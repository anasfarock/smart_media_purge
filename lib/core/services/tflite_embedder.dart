import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/vector_math.dart';

enum EmbedNorm { zeroToOne, minusOneToOne, signed128 }

/// Thin wrapper around a float32 TFLite model that maps an image to an
/// L2-normalised embedding. Expects NHWC input and a [1, N] output.
class TfliteEmbedder {
  TfliteEmbedder({
    required this.assetPath,
    required this.inputSize,
    required this.normalization,
  });

  final String assetPath;
  final int inputSize;
  final EmbedNorm normalization;

  Interpreter? _interpreter;
  int _outDim = 0;

  bool get isReady => _interpreter != null;
  int get dimension => _outDim;

  Future<void> load() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      final interp = await Interpreter.fromAsset(assetPath, options: options);
      _outDim = interp.getOutputTensor(0).shape.last;
      _interpreter = interp;
    } catch (e) {
      debugPrint('TFLite model "$assetPath" not loaded: $e');
      _interpreter = null;
    }
  }

  double _norm(num v) {
    switch (normalization) {
      case EmbedNorm.zeroToOne:
        return v / 255.0;
      case EmbedNorm.minusOneToOne:
        return v / 127.5 - 1.0;
      case EmbedNorm.signed128:
        return (v - 127.5) / 128.0;
    }
  }

  Float32List? embed(img.Image image) {
    final interp = _interpreter;
    if (interp == null) return null;
    final resized = img.copyResize(
      image,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );
    final input = Float32List(inputSize * inputSize * 3);
    var i = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final px = resized.getPixel(x, y);
        input[i++] = _norm(px.r);
        input[i++] = _norm(px.g);
        input[i++] = _norm(px.b);
      }
    }
    final output = [List<double>.filled(_outDim, 0.0)];
    interp.run(input.reshape([1, inputSize, inputSize, 3]), output);
    return VectorMath.l2Normalize(output[0]);
  }

  void dispose() => _interpreter?.close();
}
