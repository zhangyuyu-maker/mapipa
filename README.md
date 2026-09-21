# LocationTool（定位工具）

iOS 定位模拟工具，第一阶段：地图 + 地点搜索 + 选点 + 模拟定位。

## 技术栈

- Swift 5 / UIKit（纯代码布局，无 Storyboard）
- MapKit + MKLocalSearch + CLGeocoder（系统原生，无需 API Key）
- iOS 16.0+ / TrollStore IPA

## 架构

```
UI (MapViewController / SearchBarView / LocationCardView / SearchResultsViewController)
        │
        ▼
MapService  ──►  AppleMapService (MKMapView)
GeocodingService ──► AppleGeocodingService (MKLocalSearch + CLGeocoder)
        │
        ▼
LocationPoint (模型)
        │
        ▼
LocationBackend ──► SystemLocationBackend (CLLocationManager 私有 simulateLocation)
        │
        ▼
   系统定位模拟
```

地图层与定位后端完全解耦：地图只负责选点产出 `LocationPoint`，真正改系统定位由 `LocationBackend` 独立完成。后续更换地图 Provider 不影响定位核心。

## 第一阶段已实现功能

1. 地图显示 / 缩放 / 拖动（MKMapView）
2. 点击地图选点 → 显示 Marker
3. 底部卡片显示纬度、经度、地点名称
4. 顶部搜索框 → MKLocalSearch 地点搜索
5. 搜索结果列表 → 点击移动地图并放置 Marker
6. 逆地理编码（CLGeocoder 补全地址）
7. 设为模拟位置 → 开始模拟 / 停止模拟
8. 当前真实位置按钮（CLLocationManager）
9. 模拟状态指示（已停止 / 运行中）

## 构建与运行

### 方式一：GitHub Actions 云端构建（无需 Mac）

适合没有 Mac 的用户，完全免费。

1. 将本项目 push 到 GitHub 仓库（公开或私有均可）
2. GitHub 会自动触发 Actions 构建（见 `.github/workflows/build-ipa.yml`）
3. 构建完成后，在仓库页面点击 `Actions` 标签 → 选择最新的 `Build IPA` 运行
4. 在运行详情页底部 `Artifacts` 区域下载 `LocationTool-ipa`（一个 zip，解压后得到 `LocationTool.ipa`）
5. 将 `LocationTool.ipa` 拖入 TrollStore 安装
6. 首次运行需要在「设置 → 通用 → VPN与设备管理」信任签名

> 也可以在 `Actions` 页面手动点 `Run workflow` 触发构建。

### 方式二：Xcode（需要 Mac）

1. 双击打开 `LocationTool.xcworkspace`
2. 在 Xcode 中选择你的开发者团队（Signing & Capabilities）
3. 连接 iOS 16+ 设备，选择目标设备
4. `Cmd + R` 运行
5. 打包 IPA：`Product -> Archive -> Distribute App -> Copy App`

### 方式三：TrollStore 直接安装未签名 IPA

1. 用上述任一方式获得 `.ipa` 文件
2. 将 `.ipa` 拖入 TrollStore 安装

> 定位模拟需要 `com.apple.developer.location.simulated` entitlement，已在 `LocationTool.entitlements` 中声明。TrollStore 的 fakesign 会保留该 entitlement，无需 Apple 开发者账号。

## 后续阶段（未实现）

- 路线模拟（RouteManager）：起点 → 途经点 → 终点、速度、暂停、循环
- GPX 导入与轨迹模拟
- 摇杆控制
- 位置收藏夹（FavoriteLocationManager）
- 系统级定位后端完善（TrollStore 注入）

