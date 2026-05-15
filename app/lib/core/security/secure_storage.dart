// Thin wrapper around flutter_secure_storage with sensible defaults
// per platform.
//
//  Android: AES + EncryptedSharedPreferences (StrongBox where available)
//  iOS / macOS: Keychain, first-unlock-this-device-only
//  Windows: DPAPI via flutter_secure_storage_windows
//  Linux: libsecret
//  Web: encrypted IndexedDB (not for PII — only ephemeral tokens)

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();
  static final SecureStore I = SecureStore._();

  static const _opts = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<String?> read(String key) => _opts.read(key: key);
  Future<void> write(String key, String value) =>
      _opts.write(key: key, value: value);
  Future<void> delete(String key) => _opts.delete(key: key);
  Future<void> wipe() => _opts.deleteAll();
}
