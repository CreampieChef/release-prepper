import 'package:release_prepper/feature/settings/secret_store.dart';

/// The plugin is a method channel, so it cannot be used in a test. This is the
/// fake the tests that read the Integration values use: a store that cannot be
/// reached throws, which is what the plugin does when no Secret Service is
/// running.
class FakeSecretStore implements SecretStore {
  FakeSecretStore({required this.available});

  final bool available;

  final Map<String, String> values = {};

  @override
  Future<Map<String, String>> readAll() async {
    if (!available) {
      throw Exception('the credential store is not reachable');
    }

    return Map.of(values);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!available) {
      throw Exception('the credential store is not reachable');
    }

    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (!available) {
      throw Exception('the credential store is not reachable');
    }

    values.remove(key);
  }
}
