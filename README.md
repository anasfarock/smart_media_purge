# Smart Media Purge and Storage Optimizer (Flutter)

Android app with three on-device modules. No network permission is declared and no
data leaves the phone.

| Module | Where | How |
|---|---|---|
| Visual Duplicate Detection | `lib/features/duplicates` | MobileNet-style TFLite embeddings + 64-bit dHash pre-filter, SHA-256 for byte-identical files, quality scorer (resolution + bytes/pixel) picks the keeper |
| OCR Document Parsing | `lib/features/ocr` | ML Kit on-device text recognition, keyword classifier (receipt/bill/ID) + handwriting heuristic, regex/Luhn sensitive-data detector, SQLite FTS4 offline search, tax-ready folder export |
| Face Clustering | `lib/features/faces` | ML Kit face detection + MobileFaceNet TFLite embeddings, incremental cosine clustering, hide / passcode-lock via PBKDF2 hash in Keystore-backed secure storage + biometrics |

## 1. Create the Flutter shell and drop this code in

```bash
flutter create --org com.example --project-name smart_media_purge --platforms android smart_media_purge
cd smart_media_purge
# copy lib/, test/, assets/, pubspec.yaml, analysis_options.yaml from this archive over the generated ones
flutter pub get          # if versions conflict: flutter pub upgrade --major-versions
```

## 2. Android configuration

`android/app/build.gradle(.kts)`
```kotlin
defaultConfig { minSdk = 26 }                       // tflite_flutter needs 26+
android { androidResources { noCompress += "tflite" } }   // Groovy: aaptOptions { noCompress 'tflite' }
```

`android/app/src/main/AndroidManifest.xml` (inside `<manifest>`; do NOT add INTERNET)
```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```
For deleting photos on Android 10 also add `android:requestLegacyExternalStorage="true"` on `<application>`
(Android 11+ shows the system delete-confirmation sheet automatically).

`MainActivity.kt` must extend `FlutterFragmentActivity` (required by `local_auth`):
```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity : FlutterFragmentActivity()
```

Android 14+: if the user grants only "selected photos", the scan only sees those.
The app asks for full access; the screens offer an "Open settings" button if denied.

## 3. Models (not bundled - you must add them)

Put two **float32** `.tflite` files in `assets/models/`:

* `image_embedder.tflite` - image feature extractor, input `224x224x3` in [0,1], output `[1, N]`
  (e.g. a MobileNetV3-Small *feature vector* model).
* `mobilefacenet.tflite` - MobileFaceNet, input `112x112x3` normalised `(x-127.5)/128`, output `[1, 192]`.

If your model uses a different input range, change the `EmbedNorm` in `lib/core/app_services.dart`.
Without the models the app still runs: duplicates fall back to dHash only, and the People screen
shows a "model missing" banner.

## 4. Run

```bash
flutter run --release     # release = no debug INTERNET permission, realistic speed
flutter test              # unit tests for hashing, parsers, detector, clusterer
```

## Design notes and known limits

* **Lighting/contrast robustness**: dHash only compares neighbouring pixels, so any monotonic brightness/contrast change leaves it unchanged; the embedding handles the rest. The dHash is also used as a cheap candidate filter before the embedding comparison.
* **Exact duplicates**: files are bucketed by byte size, and only collisions get a streamed SHA-256, so most photos are never fully read.
* **Scaling**: the similarity pass is O(n^2) on 64-bit hashes (fine for several thousand photos). For 50k+ images replace it with LSH / a vector index.
* **Everything runs on the main isolate with yields.** For big libraries move `_fingerprint` and face embedding into a background isolate (create the TFLite interpreter inside it) or WorkManager.
* **Clustering thresholds** (`strictness` slider, default 0.55) must be tuned for the face model you pick. Faces are cropped, not landmark-aligned - alignment will improve accuracy.
* **Handwriting**: ML Kit Latin OCR is weak on handwriting; the classifier only flags it from layout irregularity. Swap in a digital-ink or custom model if needed.
* **Privacy filters hide people inside this app only.** The photos themselves remain in the system gallery. A true vault would move/encrypt the files.
* **Tax folders** are copied into app-private storage (`tax_ready/<year>/<Receipts|Bills>/` + `summary.csv`). Export/share them with `share_plus` or the Storage Access Framework if users need them in a file manager.
* Written without access to a Flutter SDK, so run `flutter analyze` first and expect small API drift fixes (package versions move fast).
