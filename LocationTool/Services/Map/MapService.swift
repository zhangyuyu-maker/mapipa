import CoreLocation
import UIKit

/// 地图服务统一接口
/// 负责地图显示、移动、Marker、路线绘制等纯地图操作
/// 不涉及定位模拟，定位模拟由 LocationBackend 独立负责
protocol MapService: AnyObject {
    /// 底层地图视图（供 VC 加入层级）
    var mapView: UIView { get }

    /// 移动并缩放到指定坐标
    func showLocation(_ coordinate: CLLocationCoordinate2D,
                      latitudinalMeters: CLLocationDistance,
                      longitudinalMeters: CLLocationDistance)

    /// 平滑移动到指定坐标（保持当前缩放级别）
    func moveTo(_ coordinate: CLLocationCoordinate2D)

    /// 直接跳到指定坐标（无动画，保持当前缩放级别）
    func setCenter(_ coordinate: CLLocationCoordinate2D)

    /// 添加/更新选中 Marker
    func addMarker(at coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?)

    /// 移除 Marker
    func removeMarker()

    /// 绘制路线（多段点连线）
    func drawRoute(points: [CLLocationCoordinate2D])

    /// 清除路线
    func clearRoute()

    /// 用户点击地图回调
    var onMapTapped: ((CLLocationCoordinate2D) -> Void)? { get set }

    // MARK: - 模拟状态专用（不影响上方既有方法）

    /// 更新/添加人物 Icon（仅模拟时使用，与 addMarker 互不干扰）
    func updatePersonIcon(at coordinate: CLLocationCoordinate2D)

    /// 移除人物 Icon
    func removePersonIcon()

    /// 绘制剩余路线（从当前位置到剩余途径点）
    func drawRemainingRoute(from current: CLLocationCoordinate2D,
                            points: [CLLocationCoordinate2D])

    /// 清除剩余路线
    func clearRemainingRoute()

    /// 是否显示系统"我的位置"蓝点（非模拟时显示，模拟时隐藏避免与模拟位置混淆）
    func setShowsMyLocation(_ flag: Bool)

    /// 提供"我的位置"按钮（封装为 UIView，便于 VC 直接加入层级）
    func makeUserTrackingButton() -> UIView

    /// 提供指南针按钮（点击恢复北朝上）
    func makeCompassButton() -> UIView
}
