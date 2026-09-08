import 'package:flutter_ad_plugin/src/utils/cancellation_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancellationToken', () {
    test('notifies active listeners once', () {
      final token = CancellationToken();
      var calls = 0;
      token.addListener(() => calls++);

      token.cancel();
      token.cancel();

      expect(calls, 1);
    });

    test('removed listener is not retained or notified', () {
      final token = CancellationToken();
      var calls = 0;
      final remove = token.addListener(() => calls++);

      remove();
      token.cancel();

      expect(calls, 0);
    });

    test('listener added after cancellation runs immediately', () {
      final token = CancellationToken()..cancel();
      var calls = 0;

      token.addListener(() => calls++);

      expect(calls, 1);
    });
  });
}
