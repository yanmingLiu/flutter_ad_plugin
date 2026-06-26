/// 广告位类型（使用类包装 String 以支持动态扩展）
class PlacementType {
  final String name;
  const PlacementType(this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlacementType &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// Ad format (String-wrapped to support dynamic extension from server config).
///
/// ---
/// 广告形式（使用类包装 String 以支持动态扩展）
class AdType {
  final String name;
  const AdType(this.name);

  static const open = AdType('open');
  static const interstitial = AdType('interstitial');
  static const rewarded = AdType('rewarded');
  static const native = AdType('native');
  static const doubleNative = AdType('double_native');
  static const banner = AdType('banner');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdType && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  /// Fullscreen ad types that occupy the entire screen and block on dismissal.
  ///
  /// 全屏广告类型（占据全屏，阻塞至用户关闭）。
  bool get isFullscreen =>
      this == open || this == interstitial || this == rewarded;

  /// Native ad types rendered inline via a platform factory.
  ///
  /// 原生广告类型（通过平台工厂内联渲染）。
  bool get isNative => this == native || this == doubleNative;

  /// Banner ad type displayed as an embedded widget.
  ///
  /// Banner 广告类型（嵌入式 Widget 展示）。
  bool get isBanner => this == banner;

  bool get isDoubleNative => this == doubleNative;

  @override
  String toString() => name;
}

/// 广告来源（使用类包装 String 以支持动态扩展）
class AdSource {
  final String name;
  const AdSource(this.name);

  static const admob = AdSource('admob');
  static const max = AdSource('max');
  static const topon = AdSource('topon');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdSource &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}
