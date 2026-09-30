import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class DualNativeAdView extends StatelessWidget {
  const DualNativeAdView({
    super.key,
    required this.ads,
    required this.itemBuilder,
    this.height = 600,
    this.direction = Axis.vertical,
    this.spacing = 0,
  });

  final List<Object> ads;
  final Widget Function(Object ad) itemBuilder;
  final double height;
  final Axis direction;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (ads.length < 2) return const SizedBox.shrink();

    final children = <Widget>[
      Expanded(child: itemBuilder(ads[0])),
      if (spacing > 0) SizedBox(width: spacing, height: spacing),
      Expanded(child: itemBuilder(ads[1])),
    ];
    return SizedBox(
      height: height,
      child: direction == Axis.horizontal
          ? Row(children: children)
          : Column(children: children),
    );
  }
}

class AdRuleSummary extends StatelessWidget {
  const AdRuleSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前规则', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('展示优先级：level_h -> 当前业务广告位'),
            Text('未配置业务广告位：回退 behavior / behavior2'),
            Text('冷却时间：ad_cd = 30 秒'),
            Text('普通加载：7 秒；激励加载：20 秒'),
            Text('无缓存：上报 no_cache 并异步补载'),
          ],
        ),
      ),
    );
  }
}

@Preview(name: '广告规则摘要', size: Size(390, 220))
Widget adRuleSummaryPreview() {
  return const MaterialApp(
    home: Scaffold(
      body: Padding(padding: EdgeInsets.all(16), child: AdRuleSummary()),
    ),
  );
}
