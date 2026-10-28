import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'features/duplicates/duplicate_controller.dart';
import 'features/faces/face_controller.dart';
import 'features/faces/privacy_vault.dart';
import 'features/ocr/ocr_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  runApp(
    MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider<PrivacyVault>.value(value: services.vault),
        ChangeNotifierProvider(create: (_) => DuplicateController(services)),
        ChangeNotifierProvider(create: (_) => OcrController(services)),
        ChangeNotifierProvider(create: (_) => FaceController(services)),
      ],
      child: const SmartMediaPurgeApp(),
    ),
  );
}
