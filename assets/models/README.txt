Place your two TFLite models here (see the project README for what to download):

  image_embedder.tflite   -> float32 image feature extractor, input 224x224x3, output [1, N]
                             (e.g. MobileNetV3-Small feature vector)
  mobilefacenet.tflite    -> float32 MobileFaceNet, input 112x112x3, output [1, 192]

The app still runs without them: duplicates fall back to dHash only,
face clustering shows a "model missing" message.
