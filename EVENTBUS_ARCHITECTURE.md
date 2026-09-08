# Flutter 广告插件 EventBus 架构重构方案

## 一、原始架构问题分析

### 1.1 当前回调链结构

**加载流程（AdLoaderService）：**
```
adapter.load(onCallback: _wrapCallback(placement, unit, eventName))
  → _wrapCallback 返回闭包 (AdRawCallback) => void
    → 查 cache attribution
    → _eventMapper.map(callback, ...) 转成 AdEvent
    → _reporter.report(event)
```

**展示流程（AdPresenter）：**
```
adapter.show(onCallback: _showCallback(showPlacement, eventName, slot))
  → _showCallback 返回闭包 (AdRawCallback) => void
    → _eventMapper.map(callback, ...) 转成 AdEvent
    → _reporter.report(event)

onClosed: () {
  _cache.removeSlot(...)
  _loader.preload(...)   // 补货硬编码在回调里
}
```

### 1.2 核心问题

| 问题 | 具体表现 | 影响 |
|------|---------|------|
| **事件翻译重复** | `_wrapCallback`（加载）和 `_showCallback`（展示）各写了一套 eventMapper 调用 | 新增事件类型要改两处 |
| **补货逻辑耦合** | `onClosed` 里直接调 `_loader.preload()` 补货 | AdPresenter 必须知道 AdLoader 存在，无法独立测试 |
| **中心枢纽依赖** | AdLoaderService 和 AdPresenter 都直接持有 `_reporter`、`_eventMapper` | 新增订阅者（如 A/B 实验、调试面板）要改这两个类 |
| **requestId 透传脆弱** | 闭包捕获 `eventName`，widget 场景下要手动覆盖 | 漏传一层就断链 |
| **隐式调用关系** | grep 不到"谁处理了这个事件"，得读闭包 | 新人理解成本高 |

---

## 二、EventBus 架构设计

### 2.1 核心思想

**从"推模式的嵌套回调"变为"发布/订阅的事件总线"：**

```
发布者（Publisher）          事件总线（EventBus）          订阅者（Subscriber）
─────────────────          ──────────────────          ─────────────────
AdStore      ──publish──→  AdDomainEvent  ──listen──→  AdTelemetry（埋点）
AdPresenter  ──publish──→  (sealed class) ──listen──→  AdPoolManager（补货）
                         同步广播(sync:true)  ──listen──→  未来新增订阅者
```

### 2.2 设计原则

1. **对外 API 不变**：`await kit.show()` 仍然返回结果，EventBus 只用于内部组件通信
2. **同步传递**：`StreamController.broadcast(sync: true)`，保证事件顺序和原回调链一致
3. **事件不可变**：`AdDomainEvent` 是不可变值对象，携带完整上下文
4. **单一职责**：每个组件只关心自己发布/订阅什么，不关心对方是谁
5. **可测试**：订阅者可独立 mock，发布者可独立验证事件发出

### 2.3 边界划分：什么走 EventBus，什么不走

| 走返回值（业务方需要 await） | 走 EventBus（内部副作用） |
|---------------------------|------------------------|
| show 的成功/失败状态 | 埋点记录 |
| preload 的 true/false | 自动补货触发 |
| reward 金额 | 配置变更通知 |
| 业务方决策所需的一切 | 业务方不关心、内部组件关心的一切 |

---

## 三、事件定义清单

### 3.1 基类

```dart
/// lib/src/core/ad_event_bus.dart
sealed class AdDomainEvent {
  const AdDomainEvent({
    required this.placement,
    this.cacheKey,
    this.slot,
    this.requestId,
    this.scene,
  });

  final PlacementType placement;
  final String? cacheKey;
  final String? slot;
  final String? requestId;
  final String? scene;
}
```

### 3.2 具体事件

| 事件类 | 触发时机 | 发布者 | 主要订阅者 |
|--------|---------|--------|-----------|
| `AdLoadRequested` | 开始加载 | AdPreloadService | AdTelemetry |
| `AdLoaded` | 加载成功 | AdStore | AdTelemetry |
| `AdFailedToLoad` | 加载失败/被 guard 阻止 | AdStore / AdPreloadService | AdTelemetry |
| `AdShowed` | 广告展示（SDK 回调 showed） | AdPresenter | AdTelemetry, AdPoolManager |
| `AdClicked` | 用户点击 | AdStore / AdPresenter | AdTelemetry |
| `AdClosed` | 广告关闭 | AdPresenter | AdTelemetry |
| `AdRewarded` | 激励视频奖励 | AdPresenter | AdTelemetry |
| `AdImpression` | 曝光（非付费） | AdStore / AdPresenter | AdTelemetry |
| `AdPaid` | 付费事件（带 revenue） | AdStore / AdPresenter | AdTelemetry |
| `AdConfigChanged` | 配置热更新 | AdMobKit | 未来扩展 |

### 3.3 事件字段设计要点

- **requestId 必带**：每个事件携带请求 ID，订阅者可关联同一次请求的所有事件
- **scene 必带**：业务场景名，原 `eventName`，用于埋点分组
- **ad 按需带**：`AdLoaded`、`AdShowed` 携带 `AdNetworkAd`，纯状态事件不带
- **error 用 Object?**：不限制异常类型，保留原始 stack trace 能力

---

## 四、组件职责重新划分

### 4.1 重构后架构图

```
AdMobKit（编排层：init / config reload / consent / show 流程控制）
  │
  ├── AdEventBus          同步事件总线，所有组件共享
  │
  ├── AdPreloadService    加载管线：single-flight 去重、guard 决策、requestId 生成
  │     └─ 发布：AdLoadRequested（通过 telemetry.begin）
  │     └─ 调用：AdStore.preload()
  │
  ├── AdStore             缓存层：waterfall、过期、generation 失效
  │     └─ 发布：AdLoaded, AdFailedToLoad, AdClicked, AdImpression, AdPaid
  │     └─ 提供：bindEvents(ad, scene, requestId) 切换事件上下文
  │
  ├── AdPresenter         展示层：全屏互斥、cooldown、timeout、reward
  │     └─ 发布：AdShowed, AdClosed, AdRewarded, AdClicked, AdImpression, AdPaid
  │     └─ 返回：AdShowResult（对外 API，不走 bus）
  │
  ├── AdPoolManager       库存层：水位线、自动补货、退避重试
  │     └─ 订阅：AdShowed → 自动补货
  │
  ├── AdTelemetry         埋点层：事件 → AdEvent → reporter
  │     └─ 订阅：所有事件
  │     └─ 提供：begin() 生成 requestId（loadRequested/showRequested）
  │
  ├── AdWidgetManager     Widget 层：acquire/bind/release
  │     └─ 调用：AdStore.bindEvents() 切换 widget 场景
  │
  └── AdNetworkRegistry   网络层：插件注册、能力检查
```

### 4.2 关键设计：AdStore 的事件上下文切换

Widget 广告和全屏广告共用同一个缓存的 ad，但它们的 scene/requestId 不同。AdStore 维护 `Map<AdNetworkAd, _AdEventContext>`：

```dart
class _AdEventContext {
  final String scene;
  final String requestId;
}

// 加载时设置默认上下文
_eventContexts[ad] = _AdEventContext(scene: preloadScene, requestId: preloadRequestId);

// 展示时覆盖为展示场景
void bindEvents(StoredAd stored, {required String scene, required String requestId}) {
  _eventContexts[stored.ad] = _AdEventContext(scene: scene, requestId: requestId);
}

// 网络回调时，优先用当前上下文
void _onNetworkEvent(AdNetworkEvent event, AdNetworkAd? ad) {
  final ctx = ad != null ? _eventContexts[ad] : null;
  final scene = ctx?.scene ?? _defaultScene;
  final requestId = ctx?.requestId ?? _defaultRequestId;
  _bus.publish(_mapToDomain(event, scene, requestId));
}
```

---

## 五、详细实现步骤

### 阶段 0：准备（30 分钟）

**目标**：建立基线，确保重构前一切正常。

1. 运行 `flutter analyze lib test`，确认 0 issue
2. 运行 `flutter test --no-pub`，记录测试数量（当前 142 个）
3. 确认 `git status` 干净，创建分支 `feature/eventbus-refactor`
4. 在 `pubspec.yaml` 中确认 Dart SDK >= 3.0（需要 sealed class 支持）

### 阶段 1：创建 EventBus 基础设施（1 小时）

**目标**：建立事件总线和事件定义，不改动现有代码。

#### 步骤 1.1：创建 `lib/src/core/ad_event_bus.dart`

```dart
import 'dart:async';
import 'ad_enums.dart';
import '../network/ad_network.dart'; // 如果 AdNetworkAd 定义在这

sealed class AdDomainEvent {
  const AdDomainEvent({
    required this.placement,
    this.cacheKey,
    this.slot,
    this.requestId,
    this.scene,
  });
  final PlacementType placement;
  final String? cacheKey;
  final String? slot;
  final String? requestId;
  final String? scene;
}

// 依次定义 10 个事件类（见第三节清单）

class AdEventBus {
  // 关键：sync: true 保证同步传递，事件顺序与原回调链一致
  final StreamController<AdDomainEvent> _controller =
      StreamController<AdDomainEvent>.broadcast(sync: true);

  void publish(AdDomainEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Stream<T> on<T extends AdDomainEvent>() {
    return _controller.stream.where((e) => e is T).cast<T>();
  }

  Future<void> dispose() => _controller.close();
}
```

**关键决策**：为什么 `sync: true`？
- 原回调链是同步的：`adapter.load(onCallback: (cb) { reporter.report(...) })`
- 如果用默认 `sync: false`，事件会进入微任务队列，`await preload()` 返回时事件可能还没处理
- 测试中 `expect(reporter.events, hasLength(1))` 会因为时序问题失败
- **这是最容易踩的坑，必须在代码注释中标注不可更改**

#### 步骤 1.2：写 EventBus 单元测试

```dart
test('publishes and receives synchronously', () {
  final bus = AdEventBus();
  final received = <AdLoaded>[];
  bus.on<AdLoaded>().listen(received.add);

  bus.publish(AdLoaded(placement: placement, requestId: 'r1', scene: 's', ad: ad));

  // sync:true 意味着 publish 返回时订阅者已经执行完
  expect(received, hasLength(1));
  bus.dispose();
});
```

### 阶段 2：改造 AdTelemetry 为订阅者（1.5 小时）

**目标**：AdTelemetry 不再被直接调用，改为订阅 EventBus。

#### 步骤 2.1：修改构造函数，接收 bus 并订阅

```dart
class AdTelemetry {
  AdTelemetry({
    required AdEventReporter reporter,
    required AdEventBus bus,
  }) : _reporter = reporter, _bus = bus {
    _subscriptions = [
      _bus.on<AdLoaded>().listen(_onLoaded),
      _bus.on<AdFailedToLoad>().listen(_onFailedToLoad),
      _bus.on<AdShowed>().listen(_onShowed),
      _bus.on<AdClicked>().listen(_onClicked),
      _bus.on<AdClosed>().listen(_onClosed),
      _bus.on<AdRewarded>().listen(_onRewarded),
      _bus.on<AdImpression>().listen(_onImpression),
      _bus.on<AdPaid>().listen(_onPaid),
    ];
  }

  final AdEventReporter _reporter;
  final AdEventBus _bus;
  late final List<StreamSubscription> _subscriptions;

  // 保留 begin() 用于生成 requestId 并记录 loadRequested/showRequested
  String begin({required PlacementType placement, required String scene, ...}) {
    final requestId = AdIdGenerator.next('request');
    _report(type: AdEventType.loadRequested, ...);
    return requestId;
  }

  // 保留 outcome() 用于 notReady/blocked/failedToShow（这些不是网络事件，没有对应 domain event）
  void outcome({required AdEventType type, ...}) {
    _report(type: type, ...);
  }

  void _onLoaded(AdLoaded event) => _report(type: AdEventType.loaded, ...);
  // ... 其他 _onXxx 方法

  void dispose() {
    for (final sub in _subscriptions) sub.cancel();
  }
}
```

**关键决策**：为什么保留 `begin()` 和 `outcome()`？
- `loadRequested`/`showRequested` 是"请求开始"事件，由调用方主动触发，不是网络回调
- `notReady`/`blocked`/`failedToShow` 是展示前的失败状态，SDK 不会发这些事件
- 这两类仍由 AdMobKit 显式调用，不走 EventBus

#### 步骤 2.2：修改 `_report` 为同步调用 reporter

```dart
void _report({...}) {
  final adEvent = AdEvent(...);
  try {
    _reporter.report(adEvent); // 同步调用，不要用 Future.sync 包装
  } catch (_) {
    // reporter 异常不能影响广告运行时
  }
}
```

**坑**：如果用 `unawaited(Future.sync(() => _reporter.report(event)))`，事件会进入微任务，`await preload()` 返回时 reporter 可能还没收到。必须同步调用。

### 阶段 3：改造 AdStore 为发布者（2 小时）

**目标**：AdStore 不再接收 onEvent 回调，改为 publish 到 bus。

#### 步骤 3.1：修改构造函数，接收 bus

```dart
class AdStore {
  AdStore({
    required AdNetworkRegistry networks,
    required AdEventBus bus,
    this.maxAge = const Duration(hours: 1),
  }) : _networks = networks, _bus = bus;

  final AdEventBus _bus;
  final Map<AdNetworkAd, _AdEventContext> _eventContexts = {};
}
```

#### 步骤 3.2：修改 `preload()`，接收 requestId，移除 onEvent 参数

```dart
Future<bool> preload({
  required PlacementType placement,
  required String scene,
  required String requestId,  // 新增：由 AdPreloadService 通过 telemetry.begin 生成
  // 移除：onEvent 回调
  ...
}) async {
  for (final unit in units) {
    final ad = await network.load(
      request,
      onEvent: (event) => _onNetworkEvent(event, ad, placement, cacheKey, slot, scene, requestId),
    );
    // 加载成功不是网络事件，显式发布
    _bus.publish(AdLoaded(placement: placement, requestId: requestId, scene: scene, ad: ad));
    return true;
  }
  // 所有 unit 失败时，最后一个失败已经通过 _onNetworkEvent 发布了 AdFailedToLoad
  return false;
}
```

#### 步骤 3.3：实现 `_onNetworkEvent`，统一映射网络事件到领域事件

```dart
void _onNetworkEvent(
  AdNetworkEvent event,
  AdNetworkAd? ad,
  PlacementType placement,
  String? cacheKey,
  String? slot,
  String defaultScene,
  String defaultRequestId,
) {
  // 优先用 ad 当前绑定的上下文（widget 场景会覆盖 preload 场景）
  final ctx = ad != null ? _eventContexts[ad] : null;
  final scene = ctx?.scene ?? defaultScene;
  final requestId = ctx?.requestId ?? defaultRequestId;

  final domainEvent = switch (event) {
    AdNetworkFailure(:final error) => AdFailedToLoad(..., error: error),
    AdNetworkClicked() => AdClicked(...),
    AdNetworkShowed() => AdShowed(..., ad: ad),
    AdNetworkClosed() => AdClosed(...),
    AdNetworkRewarded(:final amount, :final type) => AdRewarded(..., amount: amount, type: type),
    AdNetworkPaid(:final value, :final currency) => AdPaid(..., revenue: value, currency: currency),
    AdNetworkImpression(:final network) => AdImpression(..., network: network),
  };
  _bus.publish(domainEvent);
}
```

#### 步骤 3.4：实现 `bindEvents()`，支持场景切换

```dart
void bindEvents(StoredAd stored, {required String scene, required String requestId}) {
  _eventContexts[stored.ad] = _AdEventContext(scene: scene, requestId: requestId);
}
```

**为什么需要 bindEvents？**
- 同一个 ad 先被 preload（scene='cold_start'），后被 widget 使用（scene='home_feed'）
- 网络回调（点击/曝光）发生时，应该用 widget 的 scene，而不是 preload 的 scene
- bindEvents 让调用方在合适时机切换上下文

### 阶段 4：改造 AdPresenter 为发布者（2 小时）

**目标**：AdPresenter 的网络回调改为 publish 到 bus，移除 _showCallback。

#### 步骤 4.1：修改 `show()`，接收 requestId

```dart
Future<AdShowResult> show({
  required PlacementType placement,
  required String scene,
  String? requestId,  // 新增：由 AdMobKit 通过 telemetry.begin 生成
  ...
}) async {
  final effectiveRequestId = requestId ?? AdIdGenerator.next('request');

  // 展示前绑定事件上下文，让后续网络回调用展示场景
  _store.bindEvents(stored, scene: scene, requestId: effectiveRequestId);

  final result = await adapter.show(
    ...,
    onEvent: (event) {
      // 直接映射并发布，不再需要 _showCallback 闭包
      if (event is AdNetworkShowed) {
        _bus.publish(AdShowed(..., requestId: effectiveRequestId, scene: scene));
      } else if (event is AdNetworkClosed) {
        _bus.publish(AdClosed(..., requestId: effectiveRequestId, scene: scene));
      }
      // ... 其他事件
    },
  );

  // onClosed 不再硬编码补货
  // 补货由 AdPoolManager 订阅 AdShowed 自动触发
}
```

#### 步骤 4.2：处理 timeout 但已 showed 的边界情况

```dart
} on TimeoutException {
  // 如果 SDK 已经回调 showed，只是没按时 return，仍算展示成功
  // 但对外返回 timedOut 状态（业务方通过 result.shown 判断）
  // showed 事件已经通过 onEvent 发布了，telemetry 已记录
  return AdShowResult(status: AdShowStatus.timedOut, ...);
}
```

**关键决策**：timeout 但已 showed 时：
- 对外返回 `timedOut`（`result.shown == false`），保持原行为
- 但 `AdShowed` 事件已发布，telemetry 记录了 showed
- AdMobKit 不记录 `failedToShow`（因为已经 showed 了）

### 阶段 5：改造 AdPreloadService（1 小时）

**目标**：移除 telemetry.outcome 调用（加载结果走事件流），guard 阻止时发布事件。

```dart
Future<bool> load(...) async {
  final requestId = _telemetry.begin(type: AdEventType.loadRequested, ...);

  if (!(await _guardDecision(...)).allowed) {
    // guard 阻止时，store.preload 不会被调用，需要显式发布失败事件
    _bus.publish(AdFailedToLoad(..., requestId: requestId, error: 'blocked_by_guard'));
    return false;
  }

  try {
    // 加载成功/失败由 AdStore 通过 bus 发布，这里不再调用 telemetry.outcome
    return await _store.preload(..., requestId: requestId);
  } catch (error) {
    _bus.publish(AdFailedToLoad(..., requestId: requestId, error: error));
    return false;
  }
}
```

### 阶段 6：改造 AdPoolManager 为订阅者（1 小时）

**目标**：补货逻辑从 onClosed 回调移到 AdShowed 事件订阅。

```dart
class AdPoolManager {
  AdPoolManager({required AdStore store, required AdEventBus bus, ...}) {
    _showSubscription = _bus.on<AdShowed>().listen(_onAdShowed);
  }

  StreamSubscription<AdShowed>? _showSubscription;

  void _onAdShowed(AdShowed event) {
    final identity = AdCacheIdentity(placement: event.placement, cacheKey: event.cacheKey ?? 'default');
    final target = _poolTargets[identity]?.targetCount ?? 1;

    if (_store.cachedCount(event.placement, cacheKey: identity.cacheKey) >= target) return;

    // fire-and-forget，不阻塞 show 返回
    unawaited(maintainPool(
      event.placement,
      cacheKey: identity.cacheKey,
      scene: '${event.scene ?? 'show'}#refill',
      targetCount: target,
    ));
  }
}
```

**关键决策**：为什么订阅 AdShowed 而不是 AdClosed？
- 原逻辑在 onClosed 时补货，但关闭到补货有延迟
- 订阅 AdShowed 可以在展示开始时就补货，用户关闭广告时新广告可能已经加载好了
- 但要注意：show 消耗了一个缓存，如果 targetCount=1，展示时缓存已空，立即补货

### 阶段 7：改造 AdMobKit 组装层（1.5 小时）

**目标**：创建唯一 bus，注入所有组件，移除回调参数和显式补货调用。

```dart
Future<void> initialize() async {
  final bus = AdEventBus();
  final store = AdStore(networks: registry, bus: bus);
  final telemetry = AdTelemetry(reporter: reporter, bus: bus);
  final presenter = AdPresenter(store: store, networks: registry, bus: bus);
  final preloadService = AdPreloadService(store: store, telemetry: telemetry, bus: bus, ...);
  final poolManager = AdPoolManager(store: store, bus: bus, loadAd: preloadService.load, ...);

  _bus = bus;
  _store = store;
  _telemetry = telemetry;
  _presenter = presenter;
  _preloadService = preloadService;
  _poolManager = poolManager;
}

Future<AdShowResult> show(...) async {
  final requestId = _telemetry.begin(type: AdEventType.showRequested, ...);
  final result = await _presenter.show(..., requestId: requestId);

  // notReady/blocked/failedToShow 不是网络事件，显式记录
  // showed 已通过 AdShowed 事件记录，这里跳过
  if (result.status != AdShowStatus.showed &&
      result.status != AdShowStatus.timedOut) {
    _telemetry.outcome(type: _mapToTerminal(result.status), requestId: requestId, ...);
  }

  return result;
}
```

### 阶段 8：改造 AdWidgetManager（30 分钟）

**目标**：移除 telemetry 依赖，bindEvents 用新签名。

```dart
class AdWidgetManager {
  AdWidgetManager({required AdStore store, ...}) {
    // 不再需要 telemetry
  }

  void _bindEvents(StoredAd stored, String scene) {
    final requestId = AdIdGenerator.next('request');
    _store.bindEvents(stored, scene: scene, requestId: requestId);
    // 事件通过 bus 自动传递给 telemetry，不需要手动调用
  }
}
```

### 阶段 9：测试适配（2 小时）

**目标**：更新所有测试，适配新 API。

#### 需要修改的测试模式

1. **构造函数新增 bus 参数**：
   ```dart
   // 旧
   final store = AdStore(networks: registry);
   // 新
   final store = AdStore(networks: registry, bus: AdEventBus());
   ```

2. **preload 新增 requestId 参数**：
   ```dart
   // 旧
   await store.preload(placement: p, scene: 's', units: [...], ...);
   // 新
   await store.preload(placement: p, scene: 's', requestId: 'test', units: [...], ...);
   ```

3. **移除 onEvent 参数**：
   ```dart
   // 旧
   await store.preload(..., onEvent: events.add);
   // 新
   final bus = AdEventBus();
   bus.on<AdFailedToLoad>().listen(events.add);
   final store = AdStore(networks: registry, bus: bus);
   ```

4. **Reporter 改为同步**：
   ```dart
   // 旧（async 函数体会进入微任务）
   Future<void> report(AdEvent event) async => events.add(event);
   // 新（同步添加）
   Future<void> report(AdEvent event) {
     events.add(event);
     return Future.value();
   }
   ```

### 阶段 10：清理与验证（1 小时）

1. 删除不再使用的 `AdEventMapper`（事件映射逻辑内联到了发布者）
2. 删除 `AdLoaderService._wrapCallback` 和 `AdPresenter._showCallback`
3. 运行 `flutter analyze lib test example/lib`，确认 0 issue
4. 运行 `flutter test --no-pub`，确认全部通过
5. 运行 example app build，确认无编译错误
6. 更新 `CHANGELOG.md` 和 `AGENTS.md`

---

## 六、关键技术决策与坑

### 6.1 必须用 `sync: true`

**坑**：默认 `StreamController.broadcast()` 是异步的，`publish()` 返回后订阅者还没执行。

**表现**：
```dart
await kit.preload(...);
expect(reporter.events.whereType<AdLoaded>(), hasLength(1)); // 失败！事件还在微任务队列
```

**解决**：`StreamController.broadcast(sync: true)`，并在注释中标注不可更改。

### 6.2 Reporter 必须同步调用

**坑**：`Future<void>.sync(() => reporter.report(event))` 会把 report 放进微任务。

**表现**：同上，`await preload()` 返回时 reporter 还没收到事件。

**解决**：直接 `reporter.report(event)`，用 try-catch 包裹异常。

### 6.3 showed 事件的双重记录风险

**坑**：AdPresenter 发布 `AdShowed`，AdMobKit 又调用 `telemetry.outcome(type: showed)`，导致 showed 埋点重复。

**解决**：AdMobKit 在 `result.status == showed` 时跳过 outcome 调用，只记录 notReady/blocked/failedToShow。

### 6.4 timeout 但已 showed 的语义

**坑**：SDK 回调了 showed 但没按时 return，对外返回 timedOut，但 showed 事件已发布。

**解决**：
- 对外保持 `result.shown == false`（timedOut 状态）
- 内部 showed 事件正常发布（telemetry 记录 showed）
- AdMobKit 不记录 failedToShow（因为已经 showed 了）

### 6.5 AdStore 的事件上下文切换

**坑**：同一个 ad 被 preload 和 widget 共用，网络回调的 scene 应该用当前使用者的 scene。

**解决**：`Map<AdNetworkAd, _AdEventContext>` + `bindEvents()` 方法，调用方在合适时机切换。

### 6.6 guard 阻止时的事件发布

**坑**：guard 阻止时 `store.preload()` 不会被调用，`AdFailedToLoad` 不会自动发布。

**解决**：AdPreloadService 在 guard 阻止时显式发布 `AdFailedToLoad`。

---

## 七、验证标准

### 7.1 功能验证

- [ ] `flutter analyze lib test example/lib` 0 issue
- [ ] `flutter test --no-pub` 全部通过（142+ 个测试）
- [ ] example app Android debug build 成功
- [ ] example app iOS simulator build 成功

### 7.2 行为验证

- [ ] 同一个 requestId 内事件有序：loadRequested → loaded → showed → impression → closed
- [ ] show 返回值与原行为一致（shown/notReady/blocked/failed/timedOut）
- [ ] preload 返回值与原行为一致（true/false）
- [ ] 自动补货在 show 后触发，缓存数量符合水位线
- [ ] widget 广告的点击/曝光事件使用 widget 的 scene，不是 preload 的 scene
- [ ] guard 阻止时记录 failedToLoad，不记录 loaded

### 7.3 架构验证

- [ ] AdPresenter 不再直接持有 AdLoaderService（补货解耦）
- [ ] AdLoaderService 和 AdPresenter 不再直接持有 AdEventReporter（埋点解耦）
- [ ] 新增订阅者只需 `bus.on<T>().listen()`，不修改核心代码
- [ ] `AdEventMapper` 类已删除（映射逻辑内联到发布者）

---

## 八、预估工作量

| 阶段 | 内容 | 预估时间 |
|------|------|---------|
| 0 | 准备 | 30 min |
| 1 | EventBus 基础设施 | 1 h |
| 2 | AdTelemetry 订阅者 | 1.5 h |
| 3 | AdStore 发布者 | 2 h |
| 4 | AdPresenter 发布者 | 2 h |
| 5 | AdPreloadService | 1 h |
| 6 | AdPoolManager 订阅者 | 1 h |
| 7 | AdMobKit 组装 | 1.5 h |
| 8 | AdWidgetManager | 30 min |
| 9 | 测试适配 | 2 h |
| 10 | 清理验证 | 1 h |
| **合计** | | **~14 h** |

---

## 九、回滚方案

如果重构后出现难以定位的问题：

1. `git checkout -- lib/` 恢复所有 lib 代码
2. `git clean -fd lib/src/core/ad_event_bus.dart lib/src/runtime/` 删除新文件
3. 恢复测试文件
4. 确认 `flutter test` 通过

建议分阶段提交：每完成一个阶段就 commit，方便二分定位问题。
