import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

import 'integration_templates.dart';
import 'utils/ad_lifecycle.dart';

// ─── 广告位 ─────────────────────────────────────────────────────
const openPlacement = PlacementType('open');
const homePlacement = PlacementType('home');
const messagePlacement = PlacementType('message');
const playMiddlePlacement = PlacementType('play_middle');
const levelHPlacement = PlacementType('level_h');
const behaviorPlacement = PlacementType('behavior');
const bottomBannerPlacement = PlacementType('bottom_banner');
const inlineBannerPlacement = PlacementType('article_inline_banner');

const coldStartPlacements = [
  homePlacement,
  messagePlacement,
  playMiddlePlacement,
  levelHPlacement,
  bottomBannerPlacement,
];

// ─── 全局插件实例 ──────────────────────────────────────────────
late final AdPlugin adPlugin;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  adPlugin = AdPlugin(
    config: AdPluginConfig(
      configRepository: MyConfigRepository(),
      eventReporter: MyAdEventReporter(),
      placementPolicies: buildPlacementPolicies(),
      onAdNotReady: _onAdNotReady,
      verboseLogging: true,
      enableHealthMetrics: true,
      nativeAdCloseClickPercent: 0,
    ),
  );

  await adPlugin.init();

  // 冷启动后台预加载：开屏播放时不阻塞
  unawaited(
    adPlugin.preloadPlacements(coldStartPlacements, eventName: 'open_cold'),
  );

  runApp(const AdPluginDemoApp());
}

void _onAdNotReady(AdNotReadyEvent event) {
  debugPrint('⚠️ [demo] 广告未就绪: ${event.message}');
}

/// Demo 应用入口
class AdPluginDemoApp extends StatelessWidget {
  const AdPluginDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '广告插件演示',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146C5C)),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
        useMaterial3: true,
      ),
      home: const LaunchGatePage(),
    );
  }
}

// ─── 冷启动开屏页 ──────────────────────────────────────────────
class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({super.key});

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  String _status = '正在初始化...';

  @override
  void initState() {
    super.initState();
    _enterApp();
  }

  Future<void> _enterApp() async {
    setState(() => _status = '正在展示冷启动开屏广告...');
    await adPlugin.show(openPlacement, eventName: 'open_cold');

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DemoHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

// ─── 主演示页 ──────────────────────────────────────────────────
class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  String _toast = '';
  Timer? _toastTimer;
  late final AdLifecycle _lifecycle;

  // 原生广告
  Object? _nativeAd;
  List<Object> _nativeAds = const [];

  // Banner 广告
  Object? _bannerAd;
  bool _bannerReady = false;

  // 全屏广告
  bool _showingFullscreen = false;
  String _fsStatus = '–';

  @override
  void initState() {
    super.initState();

    // 热启动开屏：回到前台自动展示
    _lifecycle = AdLifecycle(
      onForeground: () => _showFullscreen(openPlacement, eventName: 'open_hot'),
    );
    _lifecycle.start();

    // 预加载原生和 Banner
    unawaited(_initNativeAd());
    unawaited(_initBannerAd());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  // ── 工具方法 ──────────────────────────────────────────────

  void _toastMessage(String msg) {
    setState(() => _toast = msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = '');
    });
  }

  Future<void> _showFullscreen(PlacementType p, {String? eventName}) async {
    if (_showingFullscreen) return;
    setState(() {
      _showingFullscreen = true;
      _fsStatus = '正在展示 ${p.name}...';
    });
    final shown = await adPlugin.show(
      p,
      eventName: eventName ?? p.name,
      closePassThroughPercent: 0,
    );
    setState(() {
      _showingFullscreen = false;
      _fsStatus = shown ? '广告已关闭 ✓' : '无广告可展示 ✗';
    });
  }

  // ── 原生广告 ──────────────────────────────────────────────

  Future<void> _initNativeAd() async {
    const eventName = 'home_show';
    var ad = adPlugin.getNativeAd(homePlacement, eventName: eventName);
    if (ad == null) {
      await adPlugin.loadNative(homePlacement, eventName: 'first_load');
      ad = adPlugin.getNativeAd(homePlacement, eventName: eventName);
    }
    final ads = adPlugin.getNativeAds(homePlacement, count: 2, eventName: eventName);
    if (mounted) setState(() { _nativeAd = ad; _nativeAds = ads; });
  }

  Future<void> _reloadNative() async {
    _toastMessage('正在加载原生广告...');
    await adPlugin.loadNative(homePlacement, eventName: 'manual_load');
    final ad = adPlugin.getNativeAd(homePlacement, eventName: 'home_show');
    final ads = adPlugin.getNativeAds(homePlacement, count: 2, eventName: 'home_show');
    if (mounted) {
      setState(() { _nativeAd = ad; _nativeAds = ads; });
      _toastMessage(ad != null ? '原生广告加载成功 ✓' : '加载失败 ✗');
    }
  }

  void _disposeNative() {
    adPlugin.disposeNativeAd(homePlacement);
    setState(() { _nativeAd = null; _nativeAds = []; });
    _toastMessage('原生广告缓存已清除');
  }

  // ── Banner 广告 ───────────────────────────────────────────

  Future<void> _initBannerAd() async {
    var ad = adPlugin.getBannerAd(bottomBannerPlacement);
    if (ad == null) {
      await adPlugin.loadBanner(bottomBannerPlacement, eventName: 'first_load');
      ad = adPlugin.getBannerAd(bottomBannerPlacement);
    }
    if (mounted) setState(() { _bannerAd = ad; _bannerReady = ad != null; });
  }

  void _disposeBanner() {
    adPlugin.disposeBannerAd(bottomBannerPlacement);
    setState(() { _bannerAd = null; _bannerReady = false; });
    _toastMessage('全局 Banner 已销毁');
  }

  // ── 健康度 ───────────────────────────────────────────────

  String _healthSummary() {
    final m = adPlugin.healthMetrics;
    if (m == null) return '健康度指标未启用';

    final buf = StringBuffer();
    for (final s in m.allSnapshots()) {
      buf.writeln(
        '${s.placement.name}: '
        '填充率=${(s.fillRate * 100).toStringAsFixed(0)}% '
        '平均延迟=${s.avgLoadLatency.inMilliseconds}ms '
        '展示率=${(s.showRate * 100).toStringAsFixed(0)}% '
        '加载=${s.loadSuccesses}/${s.loadAttempts}',
      );
    }
    if (buf.isEmpty) return '暂无数据';
    return buf.toString();
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('广告插件演示'),
        actions: [
          IconButton(
            tooltip: '健康度指标',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () => _toastMessage(_healthSummary()),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _sectionHeader('全屏广告', tt),
              _demoCard(
                '开屏广告（冷启动回放）',
                '模拟冷启动时展示开屏广告，展示 loading 过渡。',
                onPress: () => _showFullscreen(openPlacement, eventName: 'open_cold_replay'),
                label: '展示开屏',
                status: _fsStatus,
                loading: _showingFullscreen,
              ),
              _demoCard(
                '开屏广告（热启动回放）',
                '模拟 App 回到前台时触发。也可切后台再切回来测试。',
                onPress: () => _showFullscreen(openPlacement, eventName: 'open_hot_replay'),
                label: '展示热开屏',
                status: _fsStatus,
                loading: _showingFullscreen,
              ),
              _demoCard(
                '插屏广告',
                'message 广告位：开启高价位替换 + toast 提示。',
                onPress: () => _showFullscreen(messagePlacement),
                label: '展示插屏',
              ),
              _demoCard(
                '激励广告（公共兜底）',
                '"behavior2" 通过 common_placements 兜底为激励视频。',
                onPress: () => _showFullscreen(behaviorPlacement, eventName: 'behavior'),
                label: '展示激励视频',
              ),
              _demoCard(
                '连续展示（showSequence）',
                '同一广告位缓存两个广告时逐个弹出；仅一个时自动补货再弹。',
                onPress: () async {
                  if (_showingFullscreen) return;
                  setState(() { _showingFullscreen = true; _fsStatus = 'showSequence 进行中...'; });
                  final ok = await adPlugin.showSequence(
                    playMiddlePlacement,
                    eventName: 'play_middle_demo',
                    closePassThroughPercent: 0,
                  );
                  setState(() { _showingFullscreen = false; _fsStatus = ok ? 'showSequence 完成 ✓' : 'showSequence 失败 ✗'; });
                },
                label: '连续展示',
              ),
              _demoCard(
                '高价位替换（level_h）',
                'level_h 广告位优先使用高价位缓存，提高 eCPM。',
                onPress: () => _showFullscreen(levelHPlacement),
                label: '展示 Level-H',
              ),
              const SizedBox(height: 8),
              Text(
                '插屏/激励/showSequence 依赖预加载的缓存广告。'
                '缓存为空 + waitForLoadOnShow=true 时插件会即时加载后再展示。',
                style: tt.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),

              const SizedBox(height: 24),
              _sectionHeader('原生广告（$homePlacement）', tt),
              _inlineNativeCards(),

              const SizedBox(height: 24),
              _sectionHeader('全局 Banner（$bottomBannerPlacement）', tt),
              _demoCard(
                '全局 Banner',
                '自动预加载 + 每 30 分钟自动刷新 + 跨页面持久。',
                trailing: _bannerReady && _bannerAd != null
                    ? adPlugin.widgetFactory.bannerWidget(_bannerAd!)
                    : const Text('Banner 未就绪', style: TextStyle(color: Colors.grey)),
                onPress: _bannerReady
                    ? _disposeBanner
                    : () async {
                        await _initBannerAd();
                        _toastMessage(_bannerAd != null ? 'Banner 加载成功 ✓' : 'Banner 加载失败 ✗');
                      },
                label: _bannerReady ? '销毁' : '加载',
                status: '全局 Banner：每 30 分钟自动刷新',
              ),

              const SizedBox(height: 24),
              _sectionHeader('内联 Banner（$inlineBannerPlacement）', tt),
              _demoCard(
                '内联 Banner（手动生命周期）',
                'initState 加载，dispose 销毁。不自动预加载，不自动刷新。打开独立页面演示。',
                onPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const InlineBannerDemoPage(),
                  ),
                ),
                label: '打开内联 Banner 页面',
                status: 'initState → loadBanner → 展示 → dispose → disposeBannerAd',
              ),

              const SizedBox(height: 24),
              _sectionHeader('广告位策略配置', tt),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'open：同广告位 CD + 全局 CD 均启用\n'
                  'message：preferHighValue=true，showNotReadyToast=true',
                  style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('插件生命周期', tt),
              _demoCard(
                '销毁插件',
                '释放所有定时器、缓存和进行中的加载。销毁后需重启 App 才能再次使用。',
                onPress: () async {
                  await adPlugin.dispose();
                  _toastMessage('插件已销毁。请重启 App 再次使用。');
                },
                label: '销毁',
                destructive: true,
              ),

              const SizedBox(height: 40),
            ],
          ),

          // Toast 提示条
          if (_toast.isNotEmpty)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.inverseSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _toast,
                    style: tt.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: tt.titleMedium),
    );
  }

  Widget _demoCard(
    String title,
    String description, {
    VoidCallback? onPress,
    String label = '执行',
    String? status,
    bool loading = false,
    bool destructive = false,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.labelLarge),
                ),
                if (onPress != null)
                  loading
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (destructive
                          ? OutlinedButton(
                              onPressed: onPress,
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              child: Text(label),
                            )
                          : FilledButton.tonal(
                              onPressed: onPress,
                              child: Text(label),
                            )
                        ),
              ],
            ),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            if (trailing != null) ...[
              const SizedBox(height: 8),
              Center(child: trailing),
            ],
            if (status != null) ...[
              const SizedBox(height: 4),
              Text(status,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inlineNativeCards() {
    return Column(
      children: [
        _demoCard(
          '加载 / 刷新原生广告',
          '手动触发 preloadNative。缓存有广告后可点刷新重新加载。',
          onPress: () => _nativeAd == null
              ? _initNativeAd()
              : _reloadNative(),
          label: _nativeAd == null ? '加载' : '刷新',
          status: _nativeAd != null
              ? '缓存池: ${_nativeAds.length} 个广告'
              : '暂无原生广告缓存',
        ),
        _demoCard(
          '销毁原生广告缓存',
          '取消自动刷新定时器，清空所有已缓存的原生广告。',
          onPress: _nativeAd != null ? _disposeNative : null,
          label: '销毁',
          destructive: true,
        ),
        // 双原生优先，单个时才展示单原生（避免同一 AdWidget 重复渲染）
        if (_nativeAds.length >= 2) ...[
          const SizedBox(height: 4),
          Text('双原生广告', style: Theme.of(context).textTheme.labelMedium),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: adPlugin.widgetFactory.dualNativeWidget(
              _nativeAds.take(2).toList(),
              height: 560,
            ),
          ),
        ] else if (_nativeAd != null) ...[
          const SizedBox(height: 4),
          Text('单原生广告', style: Theme.of(context).textTheme.labelMedium),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: adPlugin.widgetFactory.nativeWidget(_nativeAd!, height: 280),
          ),
        ],
      ],
    );
  }
}

// ─── 内联 Banner 演示页 ────────────────────────────────────────
class InlineBannerDemoPage extends StatefulWidget {
  const InlineBannerDemoPage({super.key});

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
    adPlugin.disposeBannerAd(inlineBannerPlacement);
    super.dispose();
  }

  Future<void> _load() async {
    await adPlugin.loadBanner(inlineBannerPlacement, eventName: 'article');
    if (!mounted) return;
    setState(() {
      _ads = adPlugin.getBannerAds(inlineBannerPlacement, count: 2, eventName: 'article');
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('内联 Banner 演示')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('内联 Banner（banner_mode: inline）', style: tt.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'initState 时调用 loadBanner 加载，dispose 时调用 disposeBannerAd 销毁。\n'
            '不会被自动预加载，也不会自动刷新。',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('生命周期：', style: tt.titleSmall),
          Text(
            'initState → loadBanner → 渲染 AdWidget\n'
            'dispose  → disposeBannerAd',
            style: tt.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_ads.isEmpty)
            Center(
              child: Container(
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Banner 加载失败'),
              ),
            )
          else ...[
            Text('已缓存 ${_ads.length} 个 Banner', style: tt.labelMedium),
            const SizedBox(height: 12),
            for (var i = 0; i < _ads.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Banner #${i + 1}', style: tt.labelMedium),
                    const SizedBox(height: 4),
                    Center(child: adPlugin.widgetFactory.bannerWidget(_ads[i])),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
