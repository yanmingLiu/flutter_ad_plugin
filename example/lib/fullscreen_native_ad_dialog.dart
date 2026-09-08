import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_ad_plugin/flutter_ad_plugin.dart';

class FullscreenNativeAdDialog extends StatefulWidget {
  const FullscreenNativeAdDialog({
    super.key,
    required this.placement,
    required this.eventName,
    required this.ad,
    required this.clickTracker,
    required this.closePassThroughPercent,
    required this.onClosed,
    this.adWidget,
  });

  static const advertisementLabelKey = Key('fullscreen_native_ad_label');
  static const closeButtonKey = Key('fullscreen_native_ad_close_button');
  static final Set<String> _showingTags = <String>{};

  static String tagFor(PlacementType placement) {
    return 'fullscreen_native_ad_${placement.name}';
  }

  static Future<bool> show({
    required BuildContext context,
    required PlacementType placement,
    required String eventName,
    required Object ad,
    required NativeAdClickTracker? clickTracker,
    required VoidCallback onClosed,
    int closePassThroughPercent = 0,
  }) async {
    final tag = tagFor(placement);
    if (_showingTags.contains(tag)) {
      return false;
    }
    _showingTags.add(tag);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        useRootNavigator: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullscreenNativeAdDialog(
            placement: placement,
            eventName: eventName,
            ad: ad,
            clickTracker: clickTracker,
            closePassThroughPercent: closePassThroughPercent,
            onClosed: onClosed,
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
      return true;
    } finally {
      _showingTags.remove(tag);
    }
  }

  final PlacementType placement;
  final String eventName;
  final Object ad;
  final NativeAdClickTracker? clickTracker;
  final int closePassThroughPercent;
  final VoidCallback onClosed;
  final Widget? adWidget;

  @override
  State<FullscreenNativeAdDialog> createState() =>
      _FullscreenNativeAdDialogState();
}

class _FullscreenNativeAdDialogState extends State<FullscreenNativeAdDialog> {
  bool _closePassThroughEnabled = false;
  bool _closed = false;
  late final int _closePassThroughPercent;
  late final VoidCallback _adClickListener;

  @override
  void initState() {
    super.initState();
    _closePassThroughPercent = widget.closePassThroughPercent.clamp(0, 100);
    _closePassThroughEnabled = _rollPercent(_closePassThroughPercent);
    _adClickListener = _onAdClicked;
    widget.clickTracker?.addClickListener(widget.ad, _adClickListener);
  }

  @override
  void dispose() {
    widget.clickTracker?.removeClickListener(widget.ad, _adClickListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mediaSize = MediaQuery.sizeOf(context);
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : mediaSize.width;
            final height = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : mediaSize.height;
            final closeTop = max(72.0, height * 0.06);
            final closeRight = max(24.0, width * 0.06);

            return Stack(
              children: [
                Positioned.fill(
                  child:
                      widget.adWidget ??
                      NativeAdView(ad: widget.ad, expand: true),
                ),
                SafeArea(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 34),
                        child: Text(
                          'Advertisement',
                          key: FullscreenNativeAdDialog.advertisementLabelKey,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                              ) ??
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: closeTop,
                  right: closeRight,
                  child: SizedBox.square(
                    dimension: 44,
                    child: IgnorePointer(
                      ignoring: _shouldPassCloseTapToAd,
                      child: _CloseButton(onTap: _onCloseTap),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _shouldCloseDirectly {
    return widget.clickTracker?.hasClicked(widget.ad) ?? false;
  }

  bool get _shouldPassCloseTapToAd {
    return _closePassThroughEnabled && !_shouldCloseDirectly;
  }

  void _onAdClicked() {
    if (!mounted || !_closePassThroughEnabled) {
      return;
    }
    setState(() {
      _closePassThroughEnabled = false;
    });
  }

  void _onCloseTap() {
    _dismiss();
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
    unawaited(_dismissDialog());
  }

  Future<void> _dismissDialog() async {
    widget.onClosed();
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: FullscreenNativeAdDialog.closeButtonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const Icon(
        Icons.cancel_rounded,
        color: Color(0xFFFDF652),
        size: 36,
      ),
    );
  }
}
