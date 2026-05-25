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

/// 广告形式（使用类包装 String 以支持动态扩展）
class AdType {
  final String name;
  const AdType(this.name);

  static const open = AdType('open');
  static const interstitial = AdType('interstitial');
  static const rewarded = AdType('rewarded');
  static const native = AdType('native');
  static const doubleNative = AdType('double_native');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdType && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  bool get isFullscreen =>
      this == open || this == interstitial || this == rewarded;

  bool get isNative => this == native || this == doubleNative;

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
