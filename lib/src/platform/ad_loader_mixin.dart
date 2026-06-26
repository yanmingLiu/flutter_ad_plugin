import 'dart:async';

import '../utils/ad_logger.dart';
import '../utils/cancellation_token.dart';

import '../core/ad_config.dart';
import '../core/ad_enums.dart';
import '../core/ad_models.dart';

/// Mixin providing a common load-with-timeout pattern for ad adapters.
///
/// Extracts the duplicated Completer + Timer logic from all adapter
/// `load()` implementations into a single reusable mixin.
///
/// Usage in an adapter:
/// ```dart
/// class MyAdapter with CommonLoaderMixin<MyAdType> implements AdTypeAdapter {
///   @override
///   Future<AdLoadResult<Object>> load({...}) {
///     return loadWithCompleter(
///       unit: unit, timeout: timeout,
///       loadTimeoutLabel: 'my_type',
///       sourceName: source.name, typeName: type.name,
///       cancellationToken: cancellationToken,
///       startLoad: (onLoaded, onFailed) async { ... },
///     );
///   }
/// }
/// ```
///
/// ---
/// 公共加载超时模式 Mixin。将各适配器重复的 Completer+Timer 逻辑提取为
/// 单一可复用 mixin。
mixin CommonLoaderMixin<TAd extends Object> {
  /// Wraps an async load operation with timeout and cancellation support.
  Future<AdLoadResult<Object>> loadWithCompleter({
    required AdUnitConfig unit,
    required Duration timeout,
    required String loadTimeoutLabel,
    required String sourceName,
    required String typeName,
    required Future<void> Function(
      void Function(TAd ad) onLoaded,
      void Function(Object error) onFailed,
    ) startLoad,
    CancellationToken? cancellationToken,
  }) async {
    final completer = Completer<AdLoadResult<Object>>();

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        log.v(
          '❌ [adapter_load] timeout: source=$sourceName type=$typeName '
          'id=${unit.id} timeout=${timeout.inSeconds}s',
        );
        completer.complete(
          AdLoadResult.failure(
            type: AdType(unit.type.name),
            adUnitId: unit.id,
            error: TimeoutException('$loadTimeoutLabel ad load timeout'),
          ),
        );
      }
    });

    if (cancellationToken?.isCancelled ?? false) {
      timer.cancel();
      return AdLoadResult.failure(
        type: AdType(unit.type.name),
        adUnitId: unit.id,
        error: 'cancelled',
      );
    }

    try {
      await startLoad(
        (ad) {
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.success(
                ad: ad,
                type: AdType(unit.type.name),
                adUnitId: unit.id,
              ),
            );
          }
        },
        (error) {
          log.v(
            '❌ [adapter_load] failed: source=$sourceName type=$typeName '
            'id=${unit.id} error=$error',
          );
          if (!completer.isCompleted) {
            completer.complete(
              AdLoadResult.failure(
                type: AdType(unit.type.name),
                adUnitId: unit.id,
                error: error,
              ),
            );
          }
        },
      );
    } catch (e) {
      log.v(
        '❌ [adapter_load] failed: source=$sourceName type=$typeName '
        'id=${unit.id} error=$e',
      );
      if (!completer.isCompleted) {
        completer.complete(
          AdLoadResult.failure(
            type: AdType(unit.type.name),
            adUnitId: unit.id,
            error: e,
          ),
        );
      }
    }

    return completer.future.whenComplete(timer.cancel);
  }
}
