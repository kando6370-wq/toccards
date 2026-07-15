import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/api/api_environment.dart';

void main() {
  test(
    'API defaults to production because release builds must work when no dart define is supplied',
    () {
      expect(kandoApiBaseUrl, 'https://api.tcgcard.fun/api/v1');
    },
  );
}
