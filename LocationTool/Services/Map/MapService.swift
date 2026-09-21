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
}
