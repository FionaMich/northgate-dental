import 'package:dental/data/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a code email that cannot be sent gets a plain message, not "That did not work"', () {
    final error = SupabaseAccountRepository.authErrorForTest(
      const AuthException('Error sending confirmation email', statusCode: '500', code: 'unexpected_failure'),
    );
    expect(error.message, emailSendError);
  });
}
