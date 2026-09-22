# LocationTool - iOS 定位模拟工具

基于 TrollStore + CLSimulationManager 私有 API 的 iOS 全局定位模拟应用，支持地图选点、路线模拟、真实道路导航。

## 核心功能

### 1. 单点模拟
- 长按地图任意位置 → 全局定位修改为该点
- 蓝点自动移动到长按位置
- 保持当前缩放级别（不自动放大）
- GCJ-02 → WGS-84 坐标转换，确保长按位置与修改位置一致

### 2. 路线模拟
- 切换到路线模式自动以当前位置为起点
- 点击地图添加后续点
- 使用 MKDirections 规划真实道路路线（非直线插值）
- 支持多途径点分段规划
- 模拟位置沿道路坐标连续移动
- 已走过的路线自动消失
- 速度可调（1-30 m/s）
- 循环/暂停/恢复/停止

### 3. 地图功能
- Apple Maps（MKMapView）
- 搜索地点（MKLocalSearch）
- 双指拖动/缩放/旋转
- 指南针图标（MKCompassButton）
- 三角形定位按钮（缩放到当前位置 200m）
- 恢复真实位置按钮（一直显示）

### 4. 后台运行
- UIBackgroundModes: location
- allowsBackgroundLocationUpdates = true
- 模拟期间 startUpdatingLocation 保持 App 活跃
- DispatchQueue.global().asyncAfter 驱动 Timer（不依赖 RunLoop）

## 技术架构

```
UI 层
├── MapViewController.swift       地图主控制器
├── SearchBarView.swift            搜索栏
├── SearchResultsViewController.swift 搜索结果
├── LocationCardView.swift         单点模式控制面板
└── RouteCardView.swift            路线模式控制面板

Service 层
├── Map/
│   ├── MapService.swift           地图服务协议
│   ├── AppleMapService.swift      Apple Maps 实现
│   └── CoordTransform.swift       GCJ-02 ↔ WGS-84 转换
├── Geocoding/
│   ├── GeocodingService.swift     地理编码协议
│   └── AppleGeocodingService.swift Apple 实现
├── Location/
│   └── LocationBackend.swift     CLSimulationManager 后端
└── Route/
    └── RouteManager.swift         路线推进管理器

Model 层
├── LocationPoint.swift            位置点模型
└── RouteModels.swift              路线/进度模型
```

## 关键技术点

### CLSimulationManager 全局定位修改
- 私有 CoreLocation 类，需 com.apple.locationd.simulation entitlement
- TrollStore 平台级 entitlement（platform-application / no-sandbox 等）
- 调用顺序：stop → clear → append(location) → flush → start → postDarwinNotification
- Darwin 通知 AutomaticTimeZoneUpdateNeeded 唤醒 locationd

### MKMapView 空白瓦片修复
TrollStore 平台级 entitlement 会导致 MKMapView 空白，必须添加：
- com.apple.security.iokit-user-client-class（AGXDeviceUserClient / IOHDIXControllerUserClient / IOSurfaceRootUserClient）
- com.apple.security.exception.files.absolute-path.read-write = ["/"]

### GCJ-02 / WGS-84 坐标转换
- Apple Maps 中国大陆瓦片用 GCJ-02
- mk.convert(touchPoint, toCoordinateFrom:) 返回 GCJ-02
- CLSimulationManager / locationd 接收 WGS-84
- 长按/路线点：GCJ-02 → WGS-84 传给后端
- 显示蓝点/路线：WGS-84 → GCJ-02 传给地图

### ldid 签名（TrollStore）
codesign 无法注入 TrollStore 私有 entitlement，必须用 ldid：
ldid -S<entitlements> <app>.app/<binary_name>
签名 .app 内的 Mach-O 二进制，不是 .app 目录。

## 构建

### GitHub Actions 自动构建
- 仓库：https://github.com/zhangyuyu-maker/mapipa
- 触发：push to master
- Runner：macos-14 + Xcode 15.4
- 流程：archive → ldid 签名 → 打包 IPA → 上传 artifact

### 本地构建
xcodebuild -project LocationTool.xcodeproj -scheme LocationTool -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO

## 安装

1. 从 GitHub Actions 下载 IPA
2. 通过 TrollStore 安装
3. 首次使用授予"始终允许"位置权限

## 系统要求

- iOS 15+（TrollStore 兼容版本）
- TrollStore 已安装
- 已越狱或 TrollStore 环境

## 依赖

- 纯 Apple 框架（MapKit / CoreLocation / UIKit）
- 无第三方 SDK
- 无 CocoaPods / SPM 依赖

## License

MIT