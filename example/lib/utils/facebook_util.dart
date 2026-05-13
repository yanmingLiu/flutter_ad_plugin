
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FacebookSDKUtil {
  static const MethodChannel _channel = MethodChannel('facebook_sdk_init');
  static const String m1 = "initializeFbSDK";
  static const String _logAdImpressionMethod = 'logAdImpression';
  static const int _maxPendingAdImpressions = 50;
  
  static bool _isInitialized = false;
  static String? _appId;
  static String? _token;
  static final List<_PendingAdImpression> _pendingAdImpressions = [];

  static bool get isInitialized => _isInitialized;

  static Future<void> initializeFacebookSDK({
    required String appId,
    required String clientToken,
  }) async {
    try {
      _appId = appId;
      _token = clientToken;

      final result = await _channel.invokeMethod(m1, {
        'appId': appId,
        'token': clientToken,
      });

      _isInitialized = true;
      debugPrint('Facebook SDK initialized: $result');
      await _flushPendingAdImpressions();
    } on PlatformException catch (e) {
      debugPrint('Facebook SDK init failed: ${e.message}');
      _isInitialized = false;
      rethrow;
    }
  }

  static Future<void> logAdImpression({
    required double value,
    required String currency,
    required String adType,
    String adPlatform = 'AdMob',
    String? adSource,
    String? adUnitId,
  }) async {
    if (value <= 0 || currency.isEmpty) {
      debugPrint('Facebook ad revenue parameters invalid: value=$value currency=$currency');
      return;
    }
    if (!_isInitialized) {
      _pendingAdImpressions.add(
        _PendingAdImpression(
          value: value,
          currency: currency,
          adType: adType,
          adPlatform: adPlatform,
          adSource: adSource,
          adUnitId: adUnitId,
        ),
      );
      if (_pendingAdImpressions.length > _maxPendingAdImpressions) {
        _pendingAdImpressions.removeAt(0);
      }
      debugPrint('Facebook SDK not initialized, buffering ad impression');
      return;
    }

    await _sendAdImpression(
      value: value,
      currency: currency,
      adType: adType,
      adPlatform: adPlatform,
      adSource: adSource,
      adUnitId: adUnitId,
    );
  }

  static Future<void> _sendAdImpression({
    required double value,
    required String currency,
    required String adType,
    required String adPlatform,
    String? adSource,
    String? adUnitId,
  }) async {
    try {
      await _channel.invokeMethod(_logAdImpressionMethod, {
        'value': value,
        'currency': currency,
        'adType': adType,
        'adPlatform': adPlatform,
        'adSource': adSource ?? adPlatform,
        'adUnitId': adUnitId ?? '',
      });
      debugPrint('[fb][ad_impression] sent value=$value currency=$currency adType=$adType');
    } on PlatformException catch (e) {
      debugPrint('Facebook ad impression logging failed: ${e.message}');
    }
  }

  static Future<void> _flushPendingAdImpressions() async {
    if (_pendingAdImpressions.isEmpty) return;

    final pending = List<_PendingAdImpression>.of(_pendingAdImpressions);
    _pendingAdImpressions.clear();
    for (final event in pending) {
      await _sendAdImpression(
        value: event.value,
        currency: event.currency,
        adType: event.adType,
        adPlatform: event.adPlatform,
        adSource: event.adSource,
        adUnitId: event.adUnitId,
      );
    }
  }

  static Future<void> retryIfNeed() async {
    if (!_isInitialized && _appId != null && _token != null) {
      try {
        await initializeFacebookSDK(appId: _appId!, clientToken: _token!);
      } catch (e) {
        debugPrint('Facebook SDK retry initialization failed: $e');
      }
    }
  }
}

class _PendingAdImpression {
  const _PendingAdImpression({
    required this.value,
    required this.currency,
    required this.adType,
    required this.adPlatform,
    this.adSource,
    this.adUnitId,
  });

  final double value;
  final String currency;
  final String adType;
  final String adPlatform;
  final String? adSource;
  final String? adUnitId;
}
