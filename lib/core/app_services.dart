import 'db/app_database.dart';
import 'services/media_service.dart';
import 'services/tflite_embedder.dart';
import '../features/faces/privacy_vault.dart';

/// Tiny service container created once at start-up.
class AppServices {
  AppServices({
    required this.db,
    required this.media,
    required this.imageEmbedder,
    required this.faceEmbedder,
    required this.vault,
  });

  final AppDatabase db;
  final MediaService media;
  final TfliteEmbedder imageEmbedder;
  final TfliteEmbedder faceEmbedder;
  final PrivacyVault vault;

  static Future<AppServices> create() async {
    final db = await AppDatabase.open();
    final imageEmbedder = TfliteEmbedder(
      assetPath: 'assets/models/image_embedder.tflite',
      inputSize: 224,
      normalization: EmbedNorm.zeroToOne,
    );
    final faceEmbedder = TfliteEmbedder(
      assetPath: 'assets/models/mobilefacenet.tflite',
      inputSize: 112,
      normalization: EmbedNorm.signed128,
    );
    await Future.wait([imageEmbedder.load(), faceEmbedder.load()]);
    return AppServices(
      db: db,
      media: MediaService(),
      imageEmbedder: imageEmbedder,
      faceEmbedder: faceEmbedder,
      vault: PrivacyVault(),
    );
  }
}
