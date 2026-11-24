import 'package:dental/data/secure_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the session goes to secure storage and is removed on sign-out (E38, E39)',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SecureSessionStorage();
      expect(await storage.hasAccessToken(), isFalse);

      await storage.persistSession('{"access_token":"synthetic"}');
      expect(await storage.accessToken(), '{"access_token":"synthetic"}');
      expect(await const FlutterSecureStorage().readAll(), isNotEmpty);

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    },
  );
}
