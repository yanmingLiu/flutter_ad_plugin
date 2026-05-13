# Ad Sequence

## Overview

这份文档只描述时序，不重复解释架构分层。

关联文档：

- `/Users/ai3/Documents/siren/docs/ad_architecture.md`
- `/Users/ai3/Documents/siren/docs/ad_usage_guide.md`

## Startup Sequence

```mermaid
sequenceDiagram
    participant Main as main()
    participant Firebase as ConfigTool/Firebase
    participant AdService as AdService
    participant Splash as SplashScreen
    participant Repo as AdConfigRepository
    participant RC as RemoteConfig
    participant SDK as Google Mobile Ads

    Main->>Firebase: initFirebase()
    Main->>Firebase: fetchConfig()
    Main->>AdService: init()
    AdService->>SDK: MobileAds.initialize()
    AdService->>Repo: getConfig()
    Repo->>RC: getString("ad_config_json")
    RC-->>Repo: remote config or empty
    Repo-->>AdService: parsed config
    Main->>Splash: runApp()

    Splash->>Splash: setup()
    Splash->>Firebase: fetchConfig()
    Splash->>AdService: preloadStartupAds()
    AdService->>AdService: preload(open)
    AdService-->>Splash: open preload result
    Splash->>AdService: show(open)
    AdService-->>Splash: returns after ad closed or fail
    Splash->>Splash: _enterApp()
```

## Startup Notes

关键点：

- `main()` 只做基础初始化
- 开屏广告预加载放在 `SplashScreen`
- `preloadStartupAds()` 优先保证 `open`
- `show(open)` 返回后，再进入 `_enterApp()`

## Fullscreen Ad Show Sequence

```mermaid
sequenceDiagram
    participant Biz as Business Page
    participant Service as AdService
    participant Guard as AdDisplayGuard
    participant Controller as FullscreenAdController
    participant Adapter as Admob Adapter
    participant SDK as Google Mobile Ads
    participant Reporter as AdEventReporter

    Biz->>Service: show(placement)
    Service->>Guard: canShow(placement)
    Guard-->>Service: true/false

    alt blocked by guard
        Service-->>Biz: false
    else allowed
        Service->>Controller: hasAvailableAd(placement)
        alt no cache
            Service->>Controller: preload(placement)
        end

        alt still no cache
            Service->>Reporter: ad_show
            Service->>Reporter: ad_show_fail(no cache)
            Service-->>Biz: false
        else has cache
            Service->>Controller: show(placement)
            Controller->>Adapter: show(ad)
            Adapter->>Reporter: ad_show
            Adapter->>SDK: ad.show()
            SDK-->>Adapter: onAdShowedFullScreenContent
            Adapter->>Reporter: ad_show_succ
            SDK-->>Adapter: onAdDismissedFullScreenContent
            Adapter->>Reporter: ad_colse
            Adapter-->>Controller: AdShowResult.success()
            Controller-->>Service: shown=true
            Service-->>Biz: true
        end
    end
```

## Fullscreen Failure Sequence

```mermaid
sequenceDiagram
    participant Biz as Business Page
    participant Service as AdService
    participant Controller as FullscreenAdController
    participant Adapter as Admob Adapter
    participant SDK as Google Mobile Ads
    participant Reporter as AdEventReporter

    Biz->>Service: show(placement)
    Service->>Controller: show(placement)
    Controller->>Adapter: show(ad)
    Adapter->>Reporter: ad_show
    Adapter->>SDK: ad.show()
    SDK-->>Adapter: onAdFailedToShowFullScreenContent
    Adapter->>Reporter: ad_show_fail(code, reason)
    Adapter-->>Controller: AdShowResult.failure(error)
    Controller-->>Service: shown=false
    Service-->>Biz: false
```

## Rewarded Business Sequence

当前业务层语义：

- 只关心广告是否显示成功
- 不关心 reward callback

推荐写法：

```mermaid
sequenceDiagram
    participant Biz as Business
    participant Ad as AdService
    participant API as Your Server

    Biz->>Ad: await show(PlacementType.liveVideo)
    Ad-->>Biz: true/false
    alt shown == true
        Biz->>API: unlock / consume / grant
    else shown == false
        Biz-->>Biz: stop business flow
    end
```

示例代码：

```dart
final shown = await AdService.instance.show(PlacementType.liveVideo);
if (!shown) return;
await unlockApi();
```

## Native Ad Sequence

```mermaid
sequenceDiagram
    participant Biz as Home Page
    participant Service as AdService
    participant Native as NativeAdController
    participant Reporter as AdEventReporter

    Biz->>Service: showNative(home)
    Service->>Native: show(home)
    Native->>Reporter: ad_show

    alt cache exists
        Native->>Reporter: ad_show_succ
        Native-->>Service: NativeAd
        Service-->>Biz: NativeAd
    else no cache
        Native->>Reporter: ad_show_fail(no cache)
        Native-->>Service: null
        Service-->>Biz: null
    end
```

## Config Loading Sequence

```mermaid
sequenceDiagram
    participant Service as AdService
    participant Repo as AdConfigRepository
    participant RC as Firebase Remote Config
    participant Local as Local Config

    Service->>Repo: getConfig()
    Repo->>RC: getString("ad_config_json")
    alt remote config valid
        RC-->>Repo: json string
        Repo-->>Service: parsed remote config
    else remote empty or invalid
        Repo->>Local: read _devConfig / _prodConfig
        Local-->>Repo: local config
        Repo-->>Service: parsed local config
    end
```

## Return Timing

`await AdService.instance.show(...)` 的返回时机：

- 成功展示时：广告关闭后返回 `true`
- 失败时：展示失败后返回 `false`
- 无缓存时：直接返回 `false`
- 频控拦截时：直接返回 `false`

因此下面代码是安全的：

```dart
await AdService.instance.show(PlacementType.open);
_enterApp();
```

它的真实含义是：

- 广告显示成功时，等广告结束再进入首页
- 广告显示失败时，直接进入首页

## Sequence Checklist

如果你要排查广告流程问题，按这个顺序看：

1. `main()` 是否完成 Firebase 初始化
2. Remote Config 是否拿到了 `ad_config_json`
3. 本地 JSON 是否已加入 assets
4. `SplashScreen` 是否触发了 `preloadStartupAds()`
5. `PlacementType.open` 是否真的有可用配置
6. `show()` 前是否被 guard 拦截
7. `ad_show` / `ad_show_succ` / `ad_show_fail` / `ad_colse` 是否按顺序上报
