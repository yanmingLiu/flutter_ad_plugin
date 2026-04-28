# 广告配置

抽取版配置格式和原项目一致：

```json
{
  "load_timeout": 7,
  "same_placement_cd": 30,
  "different_placement_cd": 30,
  "open": [
    {
      "source": "admob",
      "weight": 3,
      "type": "open",
      "id": "ca-app-pub-3940256099942544/5575463023"
    }
  ],
  "home": [
    {
      "source": "admob",
      "weight": 1,
      "type": "native",
      "id": "ca-app-pub-3940256099942544/1044960115"
    }
  ]
}
```

字段说明：

- `load_timeout`：单个广告源加载超时时间，单位秒。
- `same_placement_cd`：同广告位冷却时间，单位秒。
- `different_placement_cd`：跨广告位冷却时间，单位秒。
- `source`：广告源，目前实现了 `admob`。
- `type`：广告类型，支持 `open`、`interstitial`、`rewarded`、`native`。
- `weight`：候选广告源排序权重，数值越大越先尝试。
- `id`：广告单元 ID。

配置入口在 `DefaultAdConfigRepository`。如果需要接入 Firebase Remote Config、后端接口或本地文件，只需要实现 `AdConfigRepository` 或向 `DefaultAdConfigRepository(remoteConfigJson: ...)` 传入远程 JSON。
