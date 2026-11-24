import 'package:flutter/services.dart';
import 'package:flutter_ad_topon/flutter_ad_topon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secmtp_sdk/at_index.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'TopOn finishes splash on didClose and reports event networks',
    () async {
      final hub = TopOnEventHub()..install();
      addTearDown(hub.dispose);
      final messenger = binding.defaultBinaryMessenger;
      const channel = AnythinkSdk.channel;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getSplashValidAds') {
          return '[{"network_name":"Pangle","publisher_revenue":0.01}]';
        }
        return 'success';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      Future<void> emit(String event, [String? network]) async {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            MethodCall('SplashCall', {
              'callbackName': event,
              'placementID': 'splash',
              'extraDic': {if (network != null) 'network_name': network},
            }),
          ),
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      final adapter = TopOnFullscreenAdapter(type: AdType.open, eventHub: hub);
      final load = adapter.load(
        placement: const PlacementType('open'),
        unit: const AdUnitConfig(
          source: AdSource.topon,
          weight: 1,
          type: AdType.open,
          id: 'splash',
        ),
        timeout: const Duration(seconds: 1),
        eventName: 'test',
      );
      await emit('splashDidFinishLoading');
      final loaded = await load;
      expect(loaded.network, 'Pangle');

      final callbacks = <AdRawCallback>[];
      var closed = 0;
      final result = adapter.show(
        placement: const PlacementType('open'),
        eventName: 'test',
        ad: loaded.ad!,
        onClosed: () => closed++,
        onCallback: callbacks.add,
      );

      await emit('splashDidShowSuccess', 'AdMob');
      await emit('splashWillClose', 'AdMob');
      expect(closed, 0);
      expect(callbacks.whereType<AdClosedCallback>(), isEmpty);
      await emit('splashDidClose');

      expect((await result).shown, isTrue);
      expect(closed, 1);
      expect(callbacks.whereType<AdShowedCallback>().single.network, 'AdMob');
      expect(callbacks.whereType<AdClosedCallback>().single.network, 'Pangle');
    },
  );
}
