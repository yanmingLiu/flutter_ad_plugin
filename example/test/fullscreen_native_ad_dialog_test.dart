import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:flutter_ad_plugin_example/fullscreen_native_ad_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders fullscreen native chrome and closes', (tester) async {
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FullscreenNativeAdDialog(
                      placement: const PlacementType('fullscreen_native'),
                      eventName: 'fullscreen_native',
                      ad: Object(),
                      clickTracker: null,
                      closePassThroughPercent: 0,
                      onClosed: () {
                        closed = true;
                      },
                      adWidget: const ColoredBox(color: Colors.black),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(FullscreenNativeAdDialog.advertisementLabelKey),
      findsOneWidget,
    );
    expect(find.byKey(FullscreenNativeAdDialog.closeButtonKey), findsOneWidget);

    await tester.tap(find.byKey(FullscreenNativeAdDialog.closeButtonKey));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(
      find.byKey(FullscreenNativeAdDialog.advertisementLabelKey),
      findsNothing,
    );
  });
}
