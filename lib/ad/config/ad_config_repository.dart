import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../../tools/log_tool.dart';
import '../core/ad_config.dart';
import 'ad_config_parser.dart';

abstract class AdConfigRepository {
  Future<AdConfig> getConfig();
}

class DefaultAdConfigRepository implements AdConfigRepository {
  DefaultAdConfigRepository({AdConfigParser? parser})
    : _parser = parser ?? AdConfigParser();

  static const _remoteConfigKey = 'ad_config_json';
  static const Map<String, dynamic> _devConfig = {
    'load_timeout': 7,
    'same_placement_cd': 30,
    'different_placement_cd': 30,
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
  static const Map<String, dynamic> _prodConfig = {
    "load_timeout": 7,
    "same_placement_cd": 30,
    "different_placement_cd": 30,
    "open": [
      {
        "source": "admob",
        "weight": 3,
        "type": "open",
        "id": "ca-app-pub-5043805151358377/2870727023",
      },
      {
        "source": "admob",
        "weight": 2,
        "type": "interstitial",
        "id": "ca-app-pub-5043805151358377/7747649188",
      },
      {
        "source": "admob",
        "weight": 1,
        "type": "rewarded",
        "id": "ca-app-pub-5043805151358377/9122870642",
      },
    ],
    "home": [
      {
        "source": "admob",
        "weight": 1,
        "type": "native",
        "id": "ca-app-pub-5043805151358377/1206291566",
      },
    ],
    "message": [
      {
        "source": "admob",
        "weight": 2,
        "type": "rewarded",
        "id": "ca-app-pub-5043805151358377/4371510953",
      },
    ],
    "chatBack": [
      {
        "source": "admob",
        "weight": 2,
        "type": "interstitial",
        "id": "ca-app-pub-5043805151358377/1611212130",
      },
      {
        "source": "admob",
        "weight": 3,
        "type": "rewarded",
        "id": "ca-app-pub-5043805151358377/6151340954",
      },
    ],
    "chatSession": [
      {
        "source": "admob",
        "weight": 2,
        "type": "interstitial",
        "id": "ca-app-pub-5043805151358377/1611212130",
      },
      {
        "source": "admob",
        "weight": 3,
        "type": "rewarded",
        "id": "ca-app-pub-5043805151358377/6151340954",
      },
    ],
    "liveVideo": [
      {
        "source": "admob",
        "weight": 2,
        "type": "rewarded",
        "id": "ca-app-pub-5043805151358377/1597173802",
      },
    ],
  };

  final AdConfigParser _parser;
  AdConfig? _cached;

  @override
  Future<AdConfig> getConfig() async {
    if (_cached != null) {
      log.d('⚙️ [config] memory_hit');
    }
    return _cached ??= await _loadConfig();
  }

  Future<AdConfig> _loadConfig() async {
    log.d('⚙️ [config] loading');
    if (Firebase.apps.isNotEmpty) {
      final remoteJson = FirebaseRemoteConfig.instance.getString(
        _remoteConfigKey,
      );
      if (remoteJson.trim().isNotEmpty) {
        log.d('⚙️ [config] source=remote');
        try {
          final decoded = jsonDecode(remoteJson);
          if (decoded is Map<String, dynamic>) {
            return _parser.parse(decoded);
          }
          if (decoded is Map) {
            return _parser.parse(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          log.e('❌ [config] parse_fail error=$e');
        }
      }
    }

    const useDevConfig = kDebugMode || kProfileMode;
    const localConfig = useDevConfig ? _devConfig : _prodConfig;
    log.d('⚙️ [config] source=local (${useDevConfig ? 'dev' : 'prod'})');
    return _parser.parse(localConfig);
  }
}
