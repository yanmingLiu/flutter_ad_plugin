import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

import 'demo_components.dart';
import 'integration_templates.dart';
import 'utils/ad_lifecycle.dart';

// ─── 广告位 ─────────────────────────────────────────────────────
const openPlacement = PlacementType('open');
const homePlacement = PlacementType('home');
const behaviorPlacement = PlacementType('behavior');
const behavior2Placement = PlacementType('behavior2');
const playMiddlePlacement = PlacementType('play_middle');
const bottomBannerPlacement = PlacementType('bottom_banner');
const inlineBannerPlacement = PlacementType('article_inline_banner');

const coldStartPlacements = [
  behaviorPlacement,
  behavior2Placement,
  bottomBannerPlacement,
  inlineBannerPlacement,
];
const homeCacheIds = ['home_feed', 'home_following', 'home_profile'];

// ─── 全局插件实例 ──────────────────────────────────────────────
late final AdPlugin adPlugin;
late final Future<bool> coldStartOpenPreload;
final ValueNotifier<AdEvent?> latestAdEvent = ValueNotifier(null);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  adPlugin = AdPlugin(
    config: AdPluginConfig(
      configRepository: MyConfigRepository(),
      eventReporter: MyAdEventReporter(
        onEvent: (event) => latestAdEvent.value = event,
      ),
      placementPolicies: buildPlacementPolicies(),
      onAdNotReady: _onAdNotReady,
      verboseLogging: true,
      enableHealthMetrics: true,
      nativeAdCloseClickPercent: 0,
    ),
  );

  await adPlugin.init();

  // open 的预加载会并发处理 level_h 和 open，启动页等待该链路后再展示。
  coldStartOpenPreload = adPlugin.preload(
    openPlacement,
    eventName: 'cold_start',
  );

  // 其他广告位继续后台预加载，不阻塞冷启动开屏链路。
  unawaited(
    adPlugin.preloadPlacements(coldStartPlacements, eventName: 'cold_start'),
  );
  for (final cacheId in homeCacheIds) {
    unawaited(
      adPlugin.loadNative(
        homePlacement,
        eventName: 'cold_start',
        cacheId: cacheId,
      ),
    );
  }
  unawaited(adPlugin.preload(playMiddlePlacement, eventName: 'cold_start'));
  unawaited(
    adPlugin.loadNative(
      playMiddlePlacement,
      eventName: 'cold_start',
      cacheId: 'demo',
    ),
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
    setState(() => _status = '正在加载冷启动开屏广告...');
    await coldStartOpenPreload;
    if (!mounted) return;

    setState(() => _status = '正在展示冷启动开屏广告...');
    await adPlugin.show(
      openPlacement,
      context: context,
      eventName: 'open_cold',
    );

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const DemoHomePage()));
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

  // play_middle 双原生
  List<Object> _playMiddleAds = const [];
  bool _loadingPlayMiddle = false;

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

    // 冷启动已发起全量预加载，这里只把 Banner 缓存绑定到页面。
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
      context: context,
      eventName: eventName ?? p.name,
      closePassThroughPercent: 0,
    );
    setState(() {
      _showingFullscreen = false;
      _fsStatus = shown.shown ? '广告已关闭 ✓' : '无广告可展示 ✗';
    });
  }

  Future<void> _showFullscreenSequence() async {
    if (_showingFullscreen) return;
    setState(() {
      _showingFullscreen = true;
      _fsStatus = '正在连续展示全屏广告...';
    });
    final shown = await adPlugin.showSequence(
      behaviorPlacement,
      context: context,
      eventName: 'behavior_sequence_show',
      closePassThroughPercent: 0,
    );
    if (!mounted) return;
    setState(() {
      _showingFullscreen = false;
      _fsStatus = shown ? '连续广告已关闭 ✓' : '无广告可展示 ✗';
    });
  }

  // ── play_middle 双原生 ───────────────────────────────────

  Future<void> _loadPlayMiddle() async {
    if (_loadingPlayMiddle) return;
    setState(() => _loadingPlayMiddle = true);
    final loaded = await adPlugin.loadNative(
      playMiddlePlacement,
      eventName: 'play_middle_double_native_load',
      cacheId: 'demo',
    );
    final ads = adPlugin.getNativeAds(
      playMiddlePlacement,
      count: 2,
      eventName: 'play_middle_double_native_show',
      cacheId: 'demo',
    );
    if (!mounted) return;
    setState(() {
      _loadingPlayMiddle = false;
      _playMiddleAds = ads;
    });
    _toastMessage(loaded && ads.length == 2 ? '双原生两条素材均已就绪' : '双原生未完整加载，不展示');
  }

  void _disposePlayMiddle() {
    adPlugin.disposeNativeAd(playMiddlePlacement, cacheId: 'demo');
    setState(() => _playMiddleAds = const []);
  }

  // ── Banner 广告 ───────────────────────────────────────────

  Future<void> _initBannerAd() async {
    var ad = adPlugin.getBannerAd(bottomBannerPlacement);
    if (ad == null) {
      await adPlugin.loadBanner(bottomBannerPlacement, eventName: 'first_load');
      ad = adPlugin.getBannerAd(bottomBannerPlacement);
    }
    if (mounted) {
      setState(() {
        _bannerAd = ad;
        _bannerReady = ad != null;
      });
    }
  }

  void _disposeBanner() {
    setState(() {
      _bannerAd = null;
      _bannerReady = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adPlugin.disposeBannerAd(bottomBannerPlacement);
    });
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
              const AdRuleSummary(),
              const SizedBox(height: 16),
              ValueListenableBuilder<AdEvent?>(
                valueListenable: latestAdEvent,
                builder: (context, event, _) {
                  final isFailure = event?.eventType == AdEventType.showFail;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      isFailure
                          ? Icons.error_outline
                          : Icons.monitor_heart_outlined,
                      color: isFailure
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text('最近广告事件'),
                    subtitle: Text(
                      event == null
                          ? '等待事件'
                          : '${event.eventType?.name} · ${event.eventName}'
                                '${event.errorReason == null ? '' : ' · ${event.errorReason}'}',
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _sectionHeader('全屏广告', tt),
              _demoCard(
                '全屏广告',
                '统一入口：优先展示 level_h，无高价缓存时展示 behavior 缓存。',
                onPress: () => _showFullscreen(
                  behaviorPlacement,
                  eventName: 'behavior_show',
                ),
                label: '展示全屏广告',
                status: _fsStatus,
                loading: _showingFullscreen,
              ),
              const SizedBox(height: 8),
              _demoCard(
                '连续全屏广告',
                '按 behavior、behavior2 双轮策略展示，每轮都优先检查 level_h。',
                onPress: _showFullscreenSequence,
                label: '连续展示全屏广告',
                status: _fsStatus,
                loading: _showingFullscreen,
              ),
              const SizedBox(height: 8),
              Text(
                '无缓存时上报 no_cache 并异步补载；CD 时间内上报 in_cd。',
                style: tt.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('Home 多场景独立缓存', tt),
              const HomeCacheTabsDemo(),

              const SizedBox(height: 24),
              _sectionHeader('play_middle 瀑布流', tt),
              _demoCard(
                '双原生候选',
                'ad_id 和 ad_id2 必须同时加载成功；任意一条失败都不会展示半组广告。',
                onPress: _loadingPlayMiddle
                    ? null
                    : (_playMiddleAds.length == 2
                          ? _disposePlayMiddle
                          : _loadPlayMiddle),
                label: _playMiddleAds.length == 2 ? '销毁' : '加载双原生',
                status: _loadingPlayMiddle
                    ? '正在依次加载两条素材...'
                    : '完整缓存：${_playMiddleAds.length}/2',
                trailing: _playMiddleAds.length == 2
                    ? adPlugin.widgetFactory.dualNativeWidget(
                        _playMiddleAds,
                        height: 560,
                      )
                    : null,
              ),

              const SizedBox(height: 24),
              _sectionHeader('全局 Banner（$bottomBannerPlacement）', tt),
              _demoCard(
                '全局 Banner',
                '全局缓存，跨页面持久；可手动加载和销毁。',
                trailing: _bannerReady && _bannerAd != null
                    ? adPlugin.widgetFactory.bannerWidget(_bannerAd!)
                    : const Text(
                        'Banner 未就绪',
                        style: TextStyle(color: Colors.grey),
                      ),
                onPress: _bannerReady
                    ? _disposeBanner
                    : () async {
                        await _initBannerAd();
                        _toastMessage(
                          _bannerAd != null ? 'Banner 加载成功 ✓' : 'Banner 加载失败 ✗',
                        );
                      },
                label: _bannerReady ? '销毁' : '加载',
                status: _bannerReady ? '全局 Banner 已缓存' : '暂无缓存',
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
                status:
                    'initState → loadBanner → 展示 → dispose → disposeBannerAd',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (onPress != null)
                  loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (destructive
                            ? OutlinedButton(
                                onPressed: onPress,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: Text(label),
                              )
                            : FilledButton.tonal(
                                onPressed: onPress,
                                child: Text(label),
                              )),
              ],
            ),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            if (trailing != null) ...[
              const SizedBox(height: 8),
              Center(child: trailing),
            ],
            if (status != null) ...[
              const SizedBox(height: 4),
              Text(
                status,
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
}

class HomeCacheTabsDemo extends StatefulWidget {
  const HomeCacheTabsDemo({super.key});

  @override
  State<HomeCacheTabsDemo> createState() => _HomeCacheTabsDemoState();
}

class _HomeCacheTabsDemoState extends State<HomeCacheTabsDemo> {
  static const _cacheIds = homeCacheIds;
  static const _labels = ['推荐', '关注', '我的'];

  int _selected = 0;
  final List<bool> _mounted = [true, true, true];
  final List<int> _revisions = [0, 0, 0];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < _labels.length; i++)
              ButtonSegment(value: i, label: Text(_labels[i])),
          ],
          selected: {_selected},
          onSelectionChanged: (selection) {
            setState(() => _selected = selection.single);
          },
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: IndexedStack(
              index: _selected,
              children: [
                for (var i = 0; i < _cacheIds.length; i++)
                  _mounted[i]
                      ? _HomeNativeScene(
                          key: ValueKey('${_cacheIds[i]}_${_revisions[i]}'),
                          cacheId: _cacheIds[i],
                        )
                      : _DestroyedHomeScene(
                          cacheId: _cacheIds[i],
                          onRestore: () {
                            setState(() {
                              _revisions[i]++;
                              _mounted[i] = true;
                            });
                          },
                        ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _mounted[_selected]
              ? () => setState(() => _mounted[_selected] = false)
              : null,
          icon: const Icon(Icons.delete_outline),
          label: Text('仅销毁“${_labels[_selected]}”缓存'),
        ),
      ],
    );
  }
}

class _HomeNativeScene extends StatefulWidget {
  const _HomeNativeScene({super.key, required this.cacheId});

  final String cacheId;

  @override
  State<_HomeNativeScene> createState() => _HomeNativeSceneState();
}

class _HomeNativeSceneState extends State<_HomeNativeScene> {
  Object? _ad;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    adPlugin.disposeNativeAd(homePlacement, cacheId: widget.cacheId);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await adPlugin.loadNative(
      homePlacement,
      eventName: '${widget.cacheId}_load',
      cacheId: widget.cacheId,
    );
    if (!mounted) return;
    setState(() {
      _ad = adPlugin.getNativeAd(
        homePlacement,
        eventName: '${widget.cacheId}_show',
        cacheId: widget.cacheId,
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'cacheId: ${widget.cacheId}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            IconButton(
              tooltip: '重新加载',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading)
          const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_ad == null)
          const SizedBox(height: 96, child: Center(child: Text('当前场景加载失败')))
        else
          adPlugin.widgetFactory.nativeWidget(_ad!, height: 280),
      ],
    );
  }
}

class _DestroyedHomeScene extends StatelessWidget {
  const _DestroyedHomeScene({required this.cacheId, required this.onRestore});

  final String cacheId;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$cacheId 已销毁'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore),
            label: const Text('重新创建场景'),
          ),
        ],
      ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adPlugin.disposeBannerAd(inlineBannerPlacement);
    });
    super.dispose();
  }

  Future<void> _load() async {
    await adPlugin.loadBanner(inlineBannerPlacement, eventName: 'article');
    if (!mounted) return;
    setState(() {
      _ads = adPlugin.getBannerAds(
        inlineBannerPlacement,
        count: 2,
        eventName: 'article',
      );
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
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
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
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
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
