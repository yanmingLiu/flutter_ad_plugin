import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

import 'integration_templates.dart';
import 'utils/ad_lifecycle.dart';

const openPlacement = PlacementType('open');
const homePlacement = PlacementType('home');
const bannerPlacement = PlacementType('bottom_banner');
const inlineBannerPlacement = PlacementType('article_inline_banner');
const messagePlacement = PlacementType('message');
const playMiddlePlacement = PlacementType('play_middle');
const levelHPlacement = PlacementType('level_h');
const coldStartBackgroundPreloadPlacements = [
  homePlacement,
  messagePlacement,
  playMiddlePlacement,
  levelHPlacement,
  bannerPlacement,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化广告引擎
  await FlutterAdPlugin.init(
    configRepository: MyConfigRepository(),
    eventReporter: MyAdEventReporter(),
    placementPolicies: buildPlacementPolicies(),
    nativeAdCloseClickPercent: 15,
    // 全屏原生广告样式示例：自定义关闭按钮位置
    fullScreenNativeStyle: const AdFullScreenNativeStyle(
      closeButtonPosition: AdCloseButtonPosition.topRight,
      closeButtonMargin: EdgeInsets.only(top: 50, right: 18),
    ),
  );

  FlutterAdPlugin.verboseLogging = true;

  // 初始化业务侧工具（如 Facebook SDK）
  // try {
  //   await FacebookSDKUtil.initializeFacebookSDK(
  //     appId: 'YOUR_FB_APP_ID',
  //     clientToken: 'YOUR_FB_CLIENT_TOKEN',
  //   );
  // } catch (e) {
  //   debugPrint('FB Init Error: $e');
  // }

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
    await FlutterAdPlugin.show(
      openPlacement,
      context: context,
      eventName: 'open_cold',
      closePassThroughPercent: 15,
    );

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
  Object? _bannerAd;
  String _status = 'Ready';
  late final AdLifecycle _lifecycle;

  @override
  void initState() {
    super.initState();
    _initNativeAd();
    _initBannerAd();

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

  Future<void> _initBannerAd() async {
    var ad = FlutterAdPlugin.getBannerAd(bannerPlacement);
    if (ad == null) {
      await FlutterAdPlugin.loadBanner(
        bannerPlacement,
        eventName: 'first_load',
      );
      ad = FlutterAdPlugin.getBannerAd(bannerPlacement);
    }
    if (mounted && ad != null) {
      setState(() => _bannerAd = ad);
    }
  }

  Future<void> _showFullscreen(PlacementType placement) async {
    final eventName = placement == openPlacement ? 'open_hot' : placement.name;
    setState(() => _status = 'Showing ${placement.name}...');
    final shown = await FlutterAdPlugin.show(
      placement,
      context: context,
      eventName: eventName,
      closePassThroughPercent: 15,
    );
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
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InlineBannerDemoPage(
                        placement: inlineBannerPlacement,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.view_agenda),
                  label: const Text('Inline Banner'),
                ),
          const SizedBox(height: 32),
          Text(
            '← Press back to trigger disposeBannerAd()',
            style: textTheme.labelMedium!.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
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
            const SizedBox(height: 16),
            // 模式 1：全局 Banner — 自动预加载 + 自动刷新 + 跨页面持久
            if (_bannerAd != null) ...[
              Text('Global Banner (mode: global)', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Auto-preloaded by preloadPlacements, auto-refreshes per '
                'refresh_minutes, and persists across page navigation.',
                style: textTheme.bodySmall!
                    .copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 8),
              Center(child: FlutterAdPlugin.bannerAdWidget(ad: _bannerAd!)),
            ],
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

/// Demo page for an inline banner ad.
///
/// Loads the banner on mount and disposes it on unmount, illustrating
/// the manual lifecycle pattern for `banner_mode: "inline"`.
///
/// 内联 Banner 演示页面。挂载时加载、卸载时销毁，演示手动生命周期模式。
class InlineBannerDemoPage extends StatefulWidget {
  const InlineBannerDemoPage({super.key, required this.placement});
  final PlacementType placement;

  @override
  State<InlineBannerDemoPage> createState() => _InlineBannerDemoPageState();
}

class _InlineBannerDemoPageState extends State<InlineBannerDemoPage> {
  List<Object> _ads = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    FlutterAdPlugin.disposeBannerAd(widget.placement);
    super.dispose();
  }

  Future<void> _load() async {
    await FlutterAdPlugin.loadBanner(widget.placement, eventName: 'article');
    if (!mounted) return;
    setState(() {
      _ads = FlutterAdPlugin.getBannerAds(
        widget.placement,
        count: 2,
        eventName: 'article',
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('Inline Banner: ${widget.placement.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Inline Banner Demo (mode: inline)', style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'This banner is manually loaded on mount (initState) and '
            'disposed on unmount (dispose). It uses banner_mode: "inline" '
            'in the JSON config.\n\n'
            'Unlike the global banner, this one is NOT auto-preloaded '
            'and does NOT auto-refresh.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Lifecycle', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'initState → loadBanner() → display AdWidget\n'
            'dispose  → disposeBannerAd()',
            style: textTheme.bodySmall!.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_ads.isEmpty)
            Container(
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Banner load failed'),
            )
          else ...[
            Text(
              'Cache: ${_ads.length} banner(s) loaded',
              style: textTheme.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _ads.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Banner #${i + 1}', style: textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Center(child: FlutterAdPlugin.bannerAdWidget(ad: _ads[i])),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
