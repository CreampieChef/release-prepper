import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The OS credential store: Keychain on macOS, Credential Manager on Windows,
/// the Secret Service on Linux.
///
/// It is an interface because the plugin is a method channel and cannot be
/// exercised in a widget test, so the settings feature needs a fake. The store
/// builds no dependency of its own (rule 4): the plugin instance comes from the
/// composition root.
abstract class SecretStore {
  /// The values the store holds, keyed by the service name.
  ///
  /// Throws when the store cannot be reached: no Secret Service is running on
  /// Linux, the Keychain is locked or not permitted on macOS, the credential
  /// store is not accessible on Windows.
  Future<Map<String, String>> readAll();

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class PluginSecretStore implements SecretStore {
  PluginSecretStore({required this.storage});

  final FlutterSecureStorage storage;

  @override
  Future<Map<String, String>> readAll() => storage.readAll();

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}
