# 广告配置（JSON 驱动）

插件通过 JSON 决定广告位、广告类型候选、权重、加载超时、频控与展示策略。  
默认实现与 example 使用同一份结构。

## 完整示例

```json
{
  "load_timeout": 7,
  "same_placement_cd": 30,
  "different_placement_cd": 30,
  "placement_policy": {
    "open": {
      "is_fullscreen": true,
      "apply_same_placement_cd": true,
      "apply_different_placement_cd": true,
      "contributes_to_global_cooldown": true,
      "show_not_ready_toast": false
    },
    "home": {
      "is_fullscreen": false,
      "apply_same_placement_cd": false,
      "apply_different_placement_cd": false,
      "contributes_to_global_cooldown": false,
      "show_not_ready_toast": false
    }
  },
  "open": [
    { "source": "admob", "weight": 3, "type": "open", "id": "ca-app-pub-3940256099942544/5575463023" },
    { "source": "admob", "weight": 2, "type": "interstitial", "id": "ca-app-pub-3940256099942544/4411468910" },
    { "source": "admob", "weight": 1, "type": "rewarded", "id": "ca-app-pub-3940256099942544/1712485313" }
  ],
  "home": [
    { "source": "admob", "weight": 1, "type": "native", "id": "ca-app-pub-3940256099942544/1044960115" }
  ]
}
```

## 字段说明

- `load_timeout`：单次加载超时（秒）。
- `same_placement_cd`：同广告位冷却（秒）。
- `different_placement_cd`：跨广告位冷却（秒）。
- `<placement_key>`：广告位键（如 `open`、`home`、`message`）。
- `source`：广告源（当前实现 `admob`）。
- `type`：广告类型（`open/interstitial/rewarded/native`）。
- `weight`：候选权重，越大越优先。
- `id`：广告单元 ID。

## `placement_policy`（可选）

按广告位键覆盖策略：

- `is_fullscreen`
- `apply_same_placement_cd`
- `apply_different_placement_cd`
- `contributes_to_global_cooldown`
- `show_not_ready_toast`

字段中文说明：

- `is_fullscreen`：是否按全屏广告位处理。  
  `true` 时会进入全屏展示互斥与冷却链路；`false` 时按非全屏位处理（常见于 `native`）。

- `apply_same_placement_cd`：是否启用“同广告位冷却”。  
  `true` 时，同一个 placement 在冷却窗口内重复触发会被拦截。

- `apply_different_placement_cd`：是否启用“跨广告位冷却”。  
  `true` 时，如果刚展示过其他 placement 的全屏广告，在跨位冷却窗口内会被拦截。

- `contributes_to_global_cooldown`：是否把本次展示计入“全局冷却时间线”。  
  `true` 时，该 placement 成功展示后会影响其他开启跨位冷却的 placement。

- `show_not_ready_toast`：广告未就绪时是否提示用户。  
  `true` 时，未命中缓存/加载失败场景可弹提示；`false` 时静默失败并走业务回退。

推荐实践：

- `open/chatBack/chatSession` 这类入口拦截位，通常配置为：
  `is_fullscreen=true`、`apply_same_placement_cd=true`、`apply_different_placement_cd=true`、`contributes_to_global_cooldown=true`。

- `message/liveVideo` 这类高频触发位，通常按业务体验降低限制：
  可关闭同位/跨位冷却，按需开启 `show_not_ready_toast`。

- `home` 原生位通常配置为：
  `is_fullscreen=false`，并关闭冷却相关字段。

未配置时，插件按候选广告类型自动推导默认策略：

- 含 `native` 的 placement 默认视为非全屏
- 纯全屏类型 placement 默认启用全屏相关策略

## 动态规则说明

能力与策略都按 JSON 动态计算：

- 该 placement 出现了哪些 `type`，就允许哪些候选类型进入加载
- 是否全屏、是否冷却、是否提示，优先读 `placement_policy`，否则自动推导

## 配置入口

- 默认仓库：`DefaultAdConfigRepository`
- 自定义实现：实现 `AdConfigRepository`
- 或使用 `DefaultAdConfigRepository(remoteConfigJson: ...)` 直接传 JSON 字符串
