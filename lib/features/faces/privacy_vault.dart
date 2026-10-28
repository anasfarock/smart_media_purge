import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class _KdfArgs {
  const _KdfArgs(this.password, this.salt, this.iterations);
  final String password;
  final Uint8List salt;
  final int iterations;
}

/// PBKDF2-HMAC-SHA256 (single 32-byte block). Runs in a background isolate.
Uint8List _pbkdf2(_KdfArgs a) {
  final hmac = Hmac(sha256, utf8.encode(a.password));
  var u = hmac.convert([...a.salt, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < a.iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return Uint8List.fromList(t);
}

/// Guards hidden / locked person clusters. The passcode is stored only as a salted
/// PBKDF2 hash inside the Android Keystore-backed secure storage.
class PrivacyVault extends ChangeNotifier {
  static const _kSalt = 'vault_salt';
  static const _kHash = 'vault_hash';
  static const _iterations = 60000;

  final _storage = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  bool _unlocked = false;
  bool get unlocked => _unlocked;

  Future<bool> hasPasscode() async => (await _storage.read(key: _kHash)) != null;

  Future<void> setPasscode(String pass) async {
    final rnd = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final hash = await compute(_pbkdf2, _KdfArgs(pass, salt, _iterations));
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kHash, value: base64Encode(hash));
    _unlocked = true;
    notifyListeners();
  }

  Future<bool> verifyPasscode(String pass) async {
    final salt = await _storage.read(key: _kSalt);
    final stored = await _storage.read(key: _kHash);
    if (salt == null || stored == null) return false;
    final hash = await compute(_pbkdf2, _KdfArgs(pass, base64Decode(salt), _iterations));
    final expected = base64Decode(stored);
    var diff = hash.length ^ expected.length;
    for (var i = 0; i < min(hash.length, expected.length); i++) {
      diff |= hash[i] ^ expected[i];
    }
    final ok = diff == 0;
    if (ok) {
      _unlocked = true;
      notifyListeners();
    }
    return ok;
  }

  /// Fingerprint / face / device PIN via the system prompt.
  Future<bool> tryBiometric() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock private people',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok) {
        _unlocked = true;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }
}
