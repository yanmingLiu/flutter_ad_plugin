import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

import 'integration_templates.dart';
import 'utils/ad_lifecycle.dart';
import 'utils/facebook_util.dart';

const openPlacement = PlacementType('open');
const homePlacement = PlacementType('home');
const messagePlacement = PlacementType('message');
const playMiddlePlacement = PlacementType('play_middle');
const levelHPlacement = PlacementType('level_h');
const coldStartBackgroundPreloadPlacements = [
  homePlacement,
  messagePlacement,
  playMiddlePlacement,
  levelHPlacement,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化广告引擎
  await FlutterAdPlugin.init(
    configRepository: MyConfigRepository(),
    eventReporter: MyAdEventReporter(),
  );

  // 初始化业务侧工具（如 Facebook SDK）
  try {
    await FacebookSDKUtil.initializeFacebookSDK(
      appId: 'YOUR_FB_APP_ID',
      clientToken: 'YOUR_FB_CLIENT_TOKEN',
    );
  } catch (e) {
    debugPrint('FB Init Error: $e');
  }

  runApp(const FlutterAdPluginApp());
}

class FlutterAdPluginApp extends StatelessWidget {
  const FlutterAdPluginApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Ad Plugin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146C5C)),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        useMaterial3: true,
      ),
      home: const LaunchGatePage(),
    );
  }
}

class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({super.key});

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  @override
  void initState() {
    super.initState();
    _enterApp();
  }

  Future<void> _enterApp() async {
    unawaited(
      FlutterAdPlugin.preloadPlacements(
        coldStartBackgroundPreloadPlacements,
        eventName: 'open_cold',
      ),
    );

    // 冷启动开屏广告
    await FlutterAdPlugin.show(openPlacement, eventName: 'open_cold');

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdDemoHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class AdDemoHomePage extends StatefulWidget {
  const AdDemoHomePage({super.key});

  @override
  State<AdDemoHomePage> createState() => _AdDemoHomePageState();
}

class _AdDemoHomePageState extends State<AdDemoHomePage> {
  Object? _nativeAd;
  List<Object> _nativeAds = const [];
  String _status = 'Ready';
  late final AdLifecycle _lifecycle;

  @override
  void initState() {
    super.initState();
    _initNativeAd();

    _lifecycle = AdLifecycle(
      onForeground: () {
        _showFullscreen(openPlacement);
      },
    );
    _lifecycle.start();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _initNativeAd() async {
    const eventName = 'home_show';
    // 优先尝试获取已加载的
    var ad = FlutterAdPlugin.getNativeAd(homePlacement, eventName: eventName);
    if (ad == null) {
      setState(() => _status = 'Waiting for native ad...');
      // 如果还没加载好，则发起加载并等待（引擎已优化，此处会挂载到 init 时的预加载任务上）
      await FlutterAdPlugin.loadNative(homePlacement, eventName: 'first_load');
      ad = FlutterAdPlugin.getNativeAd(homePlacement, eventName: eventName);
    }

    if (mounted) {
      final ads = FlutterAdPlugin.getNativeAds(
        homePlacement,
        eventName: eventName,
      );
      setState(() {
        _nativeAd = ad;
        _nativeAds = ads;
        _status = ad == null ? 'Native ad load failed' : 'Native ad ready';
      });
    }
  }

  Future<void> _showFullscreen(PlacementType placement) async {
    final eventName = placement == openPlacement ? 'open_hot' : placement.name;
    setState(() => _status = 'Showing ${placement.name}...');
    final shown = await FlutterAdPlugin.show(placement, eventName: eventName);
    setState(() => _status = shown ? 'Ad closed' : 'No ad was shown');
  }

  Future<void> _reloadNative() async {
    const loadEventName = 'manual_load';
    const showEventName = 'home_show';
    setState(() => _status = 'Loading native ad...');
    await FlutterAdPlugin.loadNative(homePlacement, eventName: loadEventName);
    setState(() {
      _nativeAd = FlutterAdPlugin.getNativeAd(
        homePlacement,
        eventName: showEventName,
      );
      _nativeAds = FlutterAdPlugin.getNativeAds(
        homePlacement,
        eventName: showEventName,
      );
      _status = _nativeAd == null ? 'Native ad unavailable' : 'Native ad ready';
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Ad Plugin Demo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Ad Module Integration', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'This demo showcases the extracted ad orchestration layer using Google Mobile Ads test units.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _showFullscreen(openPlacement),
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Open Ad'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showFullscreen(messagePlacement),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Interstitial'),
                ),
                OutlinedButton.icon(
                  onPressed: _reloadNative,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload Native'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Status: $_status', style: textTheme.labelLarge),
            const SizedBox(height: 16),
            if (_nativeAds.length >= 2) ...[
              Text('Dual native ad', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DualNativeAdView(ads: _nativeAds, height: 560),
              ),
            ] else if (_nativeAd == null)
              const _EmptyNativeAd()
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NativeAdView(ad: _nativeAd!, height: 280),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNativeAd extends StatelessWidget {
  const _EmptyNativeAd();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Native ad cache is empty'),
    );
  }
}
