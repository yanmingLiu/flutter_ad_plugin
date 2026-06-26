import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_config.dart';
import '../core/ad_models.dart';
import '../utils/ad_logger.dart';

class FullScreenNativeAdView extends StatefulWidget {
  const FullScreenNativeAdView({
    super.key,
    required this.ad,
    required this.closePassThroughPercent,
    required this.hasClicked,
    required this.addClickListener,
    required this.removeClickListener,
    required this.style,
  });

  /// Shows a fullscreen native ad dialog.
  ///
  /// [style] controls the overlay appearance (background, close button,
  /// top label, animation). Passed from [AdFullScreenNativeStyle] configured
  /// globally via [FlutterAdPlugin.init].
  ///
  /// [closePassThroughPercent] is the percentage chance that the first tap
  /// on the close button area passes through to the ad underneath. Set to 0
  /// to always show the close button immediately.
  ///
  /// [onClosed] is called once when the dialog is dismissed.
  ///
  /// [style] 控制遮罩层外观（背景、关闭按钮、顶部标签、动画），
  /// 来自 [FlutterAdPlugin.init] 的全局配置。
  ///
  /// [closePassThroughPercent] 是关闭按钮区域首次点击穿透到广告的概率（0-100）。
  ///
  /// [onClosed] 在对话框关闭时回调一次。
  static Future<AdShowResult> show({
    BuildContext? context,
    required NativeAd ad,
    required int closePassThroughPercent,
    required bool Function() hasClicked,
    required void Function(VoidCallback listener) addClickListener,
    required void Function(VoidCallback listener) removeClickListener,
    required VoidCallback onClosed,
    required AdFullScreenNativeStyle style,
  }) async {
    final showContext = context ?? _rootContext();
    if (showContext == null) {
      return AdShowResult.failure('missing_context');
    }

    final result = await showGeneralDialog<bool>(
      context: showContext,
      barrierDismissible: false,
      barrierLabel: 'Fullscreen native ad',
      barrierColor: style.barrierColor,
      transitionDuration: style.transitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) {
        return FullScreenNativeAdView(
          ad: ad,
          closePassThroughPercent: closePassThroughPercent,
          hasClicked: hasClicked,
          addClickListener: addClickListener,
          removeClickListener: removeClickListener,
          style: style,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
    if (result == true) {
      onClosed();
      return AdShowResult.success();
    }
    // Ad was shown (showSuccess already reported), but dismissed without
    // the close button (e.g. system gesture on some platforms).
    // Always report close to keep the event chain consistent.
    onClosed();
    return AdShowResult.success();
  }

  static BuildContext? _rootContext() {
    BuildContext? root;
    WidgetsBinding.instance.rootElement?.visitChildren((element) {
      root ??= element;
    });
    return root;
  }

  final NativeAd ad;
  final int closePassThroughPercent;
  final bool Function() hasClicked;
  final void Function(VoidCallback listener) addClickListener;
  final void Function(VoidCallback listener) removeClickListener;

  /// Overlay style applied to this fullscreen native ad.
  /// Controls background, close button, top label, and animation.
  ///
  /// 全屏原生广告遮罩层样式，控制背景、关闭按钮、顶部标签和动画。
  final AdFullScreenNativeStyle style;

  @override
  State<FullScreenNativeAdView> createState() => _FullScreenNativeAdViewState();
}

class _FullScreenNativeAdViewState extends State<FullScreenNativeAdView> {
  late bool _closePassThroughEnabled;
  late final int _closePassThroughPercent;
  late final VoidCallback _adClickListener;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _closePassThroughPercent = widget.closePassThroughPercent.clamp(0, 100);
    _closePassThroughEnabled = _rollPercent(_closePassThroughPercent);
    _adClickListener = _onAdClicked;
    widget.addClickListener(_adClickListener);
    log.v(
      '[fullscreen_native] close_first_tap_policy '
      'percent=$_closePassThroughPercent as_ad_click=$_closePassThroughEnabled',
    );
  }

  @override
  void dispose() {
    widget.removeClickListener(_adClickListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final verticalMargin = max(56.0, size.height * 0.06);
    final horizontalMargin = max(20.0, size.width * 0.06);

    final position = widget.style.closeButtonPosition;
    final alignment = _alignmentFor(position);
    final defaultPadding = _defaultEdgeInsets(
      position,
      verticalMargin,
      horizontalMargin,
    );
    final padding = widget.style.closeButtonMargin ?? defaultPadding;

    return Material(
      color: widget.style.backgroundColor,
      child: Stack(
        alignment: alignment,
        children: [
          Positioned.fill(child: AdWidget(ad: widget.ad)),
          SafeArea(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child:
                    widget.style.topLabel ??
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Advertisement',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
              ),
            ),
          ),
          Padding(
            padding: padding,
            child: SizedBox.square(
              dimension: 40,
              child: IgnorePointer(
                ignoring: _shouldPassCloseTapToAd,
                child:
                    widget.style.closeButtonBuilder?.call(_dismiss) ??
                    IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Close',
                      onPressed: _dismiss,
                      icon: const Icon(
                        Icons.cancel_rounded,
                        color: Color(0xFFFDF652),
                        size: 36,
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Alignment _alignmentFor(AdCloseButtonPosition position) {
    switch (position) {
      case AdCloseButtonPosition.topRight:
        return Alignment.topRight;
      case AdCloseButtonPosition.topLeft:
        return Alignment.topLeft;
      case AdCloseButtonPosition.bottomRight:
        return Alignment.bottomRight;
      case AdCloseButtonPosition.bottomLeft:
        return Alignment.bottomLeft;
    }
  }

  static EdgeInsets _defaultEdgeInsets(
    AdCloseButtonPosition position,
    double verticalMargin,
    double horizontalMargin,
  ) {
    switch (position) {
      case AdCloseButtonPosition.topRight:
        return EdgeInsets.only(top: verticalMargin, right: horizontalMargin);
      case AdCloseButtonPosition.topLeft:
        return EdgeInsets.only(top: verticalMargin, left: horizontalMargin);
      case AdCloseButtonPosition.bottomRight:
        return EdgeInsets.only(
          bottom: verticalMargin,
          right: horizontalMargin,
        );
      case AdCloseButtonPosition.bottomLeft:
        return EdgeInsets.only(
          bottom: verticalMargin,
          left: horizontalMargin,
        );
    }
  }

  bool get _shouldPassCloseTapToAd {
    return _closePassThroughEnabled && !widget.hasClicked();
  }

  void _onAdClicked() {
    if (!mounted || !_closePassThroughEnabled) {
      return;
    }
    setState(() {
      _closePassThroughEnabled = false;
    });
  }

  bool _rollPercent(int percent) {
    if (percent <= 0) {
      return false;
    }
    if (percent >= 100) {
      return true;
    }
    return Random().nextInt(100) < percent;
  }

  void _dismiss() {
    if (_closed) {
      return;
    }
    _closed = true;
    Navigator.of(context).pop(true);
  }
}
