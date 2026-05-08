import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../tools/log_tool.dart';
import '../core/ad_config.dart';
import 'ad_config_parser.dart';

abstract class AdConfigRepository {
  Future<AdConfig> getConfig();
}

class DefaultAdConfigRepository implements AdConfigRepository {
  DefaultAdConfigRepository({
    AdConfigParser? parser,
    String? remoteConfigJson,
    Map<String, dynamic>? fallbackConfig,
  }) : _parser = parser ?? AdConfigParser(),
       _remoteConfigJson = remoteConfigJson,
       _fallbackConfig = fallbackConfig;

  static const _remoteConfigKey = 'ad_config_json';
  static const Map<String, dynamic> _devConfig = {
    'load_timeout': 7,
    'same_placement_cd': 30,
    'different_placement_cd': 30,
    'placement_policy': {
      'open': {
        'is_fullscreen': true,
        'apply_same_placement_cd': true,
        'apply_different_placement_cd': true,
        'contributes_to_global_cooldown': true,
        'show_not_ready_toast': false,
      },
      'home': {
        'is_fullscreen': false,
        'apply_same_placement_cd': false,
        'apply_different_placement_cd': false,
        'contributes_to_global_cooldown': false,
        'show_not_ready_toast': false,
      },
      'message': {
        'is_fullscreen': true,
        'apply_same_placement_cd': false,
        'apply_different_placement_cd': false,
        'contributes_to_global_cooldown': false,
        'show_not_ready_toast': true,
      },
      'chatBack': {
        'is_fullscreen': true,
        'apply_same_placement_cd': true,
        'apply_different_placement_cd': true,
        'contributes_to_global_cooldown': true,
        'show_not_ready_toast': false,
      },
      'chatSession': {
        'is_fullscreen': true,
        'apply_same_placement_cd': true,
        'apply_different_placement_cd': true,
        'contributes_to_global_cooldown': true,
        'show_not_ready_toast': false,
      },
      'liveVideo': {
        'is_fullscreen': true,
        'apply_same_placement_cd': false,
        'apply_different_placement_cd': false,
        'contributes_to_global_cooldown': false,
        'show_not_ready_toast': true,
      },
    },
    'open': [
      {
        'source': 'admob',
        'weight': 3,
        'type': 'open',
        'id': 'ca-app-pub-3940256099942544/5575463023',
      },
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 1,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
    'home': [
      {
        'source': 'admob',
        'weight': 1,
        'type': 'native',
        'id': 'ca-app-pub-3940256099942544/1044960115',
      },
    ],
    'message': [
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 3,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
    'chatBack': [
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 3,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
    'chatSession': [
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 3,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
    'liveVideo': [
      {
        'source': 'admob',
        'weight': 2,
        'type': 'interstitial',
        'id': 'ca-app-pub-3940256099942544/4411468910',
      },
      {
        'source': 'admob',
        'weight': 3,
        'type': 'rewarded',
        'id': 'ca-app-pub-3940256099942544/1712485313',
      },
    ],
  };
  static const Map<String, dynamic> _prodConfig = {};

  final AdConfigParser _parser;
  final String? _remoteConfigJson;
  final Map<String, dynamic>? _fallbackConfig;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    if (_cached != null) {
      log.d('[ad][config] hit_memory_cache');
    }
    return _cached ??= await _loadConfig();
  }

  Future<AdConfig> _loadConfig() async {
    log.d('[ad][config] load_start');
    final remoteJson = _remoteConfigJson;
    log.d('[ad][config] source=remote remoteJson=$remoteJson');

    if (remoteJson != null && remoteJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(remoteJson);
        if (decoded is Map<String, dynamic>) {
          log.d('[ad][config] source=remote key=$_remoteConfigKey');
          return _parser.parse(decoded);
        }
        if (decoded is Map) {
          log.d('[ad][config] source=remote key=$_remoteConfigKey');
          return _parser.parse(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        log.e('[ad][config] remote_parse_fail error=$e');
      }
    }

    const useDevConfig = kDebugMode || kProfileMode;
    final localConfig =
        _fallbackConfig ?? (useDevConfig ? _devConfig : _prodConfig);
    log.d('[ad][config] source=local mode=${useDevConfig ? 'dev' : 'prod'}');
    return _parser.parse(localConfig);
  }
}
