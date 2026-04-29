import 'package:flutter/material.dart';
import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'integration_templates.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterAdPlugin.init(
    configRepository: MyConfigRepository(),
    eventReporter: MyAdEventReporter(),
  );
  await FlutterAdPlugin.preloadByKey('open');
  await FlutterAdPlugin.loadNativeByKey('home');
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
    await FlutterAdPlugin.showByKey('open');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdDemoHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class AdDemoHomePage extends StatefulWidget {
  const AdDemoHomePage({super.key});

  @override
  State<AdDemoHomePage> createState() => _AdDemoHomePageState();
}

class _AdDemoHomePageState extends State<AdDemoHomePage> {
  NativeAd? _nativeAd;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _nativeAd = FlutterAdPlugin.getNativeAdByKey('home');
  }

  Future<void> _showFullscreen(PlacementType placement) async {
    setState(() => _status = 'Showing $placement...');
    final shown = await FlutterAdPlugin.showByKey(placement);
    setState(() => _status = shown ? 'Ad closed' : 'No ad was shown');
  }

  Future<void> _reloadNative() async {
    setState(() => _status = 'Loading native ad...');
    await FlutterAdPlugin.loadNativeByKey('home');
    setState(() {
      _nativeAd = FlutterAdPlugin.getNativeAdByKey('home');
      _status = _nativeAd == null ? 'Native ad unavailable' : 'Native ad ready';
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter Ad Plugin')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Ad module extraction', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'This demo uses Google Mobile Ads test units and the extracted Flutter ad orchestration layer.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _showFullscreen(Placements.open),
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Open'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showFullscreen(Placements.message),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Message'),
                ),
                OutlinedButton.icon(
                  onPressed: _reloadNative,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Native'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_status, style: textTheme.labelLarge),
            const SizedBox(height: 16),
            if (_nativeAd == null)
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
