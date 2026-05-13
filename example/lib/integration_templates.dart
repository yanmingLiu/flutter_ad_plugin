import 'dart:convert';

import 'package:flutter_ad_plugin/ad/analytics/ad_event.dart';
import 'package:flutter_ad_plugin/ad/analytics/ad_event_reporter.dart';
import 'package:flutter_ad_plugin/ad/config/ad_config_parser.dart';
import 'package:flutter_ad_plugin/ad/config/ad_config_repository.dart';
import 'package:flutter_ad_plugin/ad/core/ad_config.dart';

class MyConfigRepository implements AdConfigRepository {
  static const Map<String, dynamic> _jsonConfig = {
    'load_timeout': 7,
    'same_placement_cd': 30,
    'different_placement_cd': 30,
    // 启动后自动预加载的列表
    'preload_list': ['open', 'home', 'message'],
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
        'not_ready_msg': 'Ad is still loading, please wait a moment.',
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
        'template_type': 'medium',
        'refresh_minutes': 20,
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

  static String get rawJson => jsonEncode(_jsonConfig);

  @override
  Future<AdConfig> getConfig() async {
    return AdConfigParser().parse(_jsonConfig);
  }
}

class MyAdEventReporter implements AdEventReporter {
  @override
  Future<void> report(AdEvent event) async {
    // ignore: avoid_print
    print(
      '[my-ad-event] type=${event.eventType.name} placement=${event.placement} unit=${event.adUnitId}',
    );
  }
}
