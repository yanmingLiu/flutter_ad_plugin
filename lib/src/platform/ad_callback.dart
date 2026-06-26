/// Raw ad lifecycle callbacks emitted by adapters.
///
/// Adapters emit these callbacks via [AdTypeAdapter.onCallback] instead of
/// calling [AdEventReporter] directly. The engine layer converts them to
/// [AdEvent] through [AdEventMapper] before reporting.
sealed class AdRawCallback {
  final Object ad;
  const AdRawCallback(this.ad);
}

class AdImpressionCallback extends AdRawCallback {
  final String? network;
  const AdImpressionCallback(super.ad, this.network);
}

class AdPaidCallback extends AdRawCallback {
  final double valueMicros;
  final String currencyCode;
  final String? network;
  const AdPaidCallback(super.ad, this.valueMicros, this.currencyCode, this.network);
}

class AdClickedCallback extends AdRawCallback {
  final String? network;
  const AdClickedCallback(super.ad, this.network);
}

class AdClosedCallback extends AdRawCallback {
  final String? network;
  const AdClosedCallback(super.ad, this.network);
}

class AdShowedCallback extends AdRawCallback {
  final String? network;
  const AdShowedCallback(super.ad, this.network);
}

class AdShowFailedCallback extends AdRawCallback {
  final int? errorCode;
  final String? errorMessage;
  final String? network;
  const AdShowFailedCallback(super.ad, this.errorCode, this.errorMessage, this.network);
}
