import CoreLocation
import MapKit
import UIKit

/// 基于 MKMapView 的地图实现
/// 封装地图渲染、缩放、拖动、Marker、路线绘制，以及点击识别
final class AppleMapService: NSObject, MapService {
    private let mkMapView: MKMapView
    var mapView: UIView { mkMapView }
    var onMapTapped: ((CLLocationCoordinate2D) -> Void)?

    private var selectionAnnotation: MKPointAnnotation?
    private var routeOverlay: MKOverlay?
    private var personAnnotation: MKPointAnnotation?
    private var remainingRouteOverlay: MKOverlay?
    /// 是否已首次缩放到用户位置 (避免每次 userLocation 更新都缩放)
    private var hasZoomedToUserLocation = false
    /// 是否在切换到 follow 模式时自动缩放到 200m 街道级别
    /// 恢复真实位置时临时设为 false, 避免缩放到模拟位置
    var shouldZoomToStreetOnFollow = true

    override init() {
        let mv = MKMapView(frame: .zero)
        mv.showsCompass = true
        mv.showsScale = true
        mv.showsUserLocation = true    // 非模拟时显示系统蓝点（与苹果地图一致）
        mv.isRotateEnabled = false
        mv.isPitchEnabled = false
        self.mkMapView = mv
        super.init()
        mv.delegate = self
        setupTapGesture()
    }

    // MARK: - 手势

    private func setupTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        mkMapView.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: mkMapView)
        let coordinate = mkMapView.convert(point, toCoordinateFrom: mkMapView)
        onMapTapped?(coordinate)
    }

    // MARK: - MapService

    func showLocation(_ coordinate: CLLocationCoordinate2D,
                      latitudinalMeters: CLLocationDistance,
                      longitudinalMeters: CLLocationDistance) {
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: latitudinalMeters,
                                        longitudinalMeters: longitudinalMeters)
        mkMapView.setRegion(region, animated: true)
    }

    func moveTo(_ coordinate: CLLocationCoordinate2D) {
        mkMapView.setCenter(coordinate, animated: true)
    }

    func addMarker(at coordinate: CLLocationCoordinate2D,
                   title: String?,
                   subtitle: String?) {
        if let existing = selectionAnnotation {
            mkMapView.removeAnnotation(existing)
        }
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = title
        annotation.subtitle = subtitle
        selectionAnnotation = annotation
        mkMapView.addAnnotation(annotation)
    }

    func removeMarker() {
        if let existing = selectionAnnotation {
            mkMapView.removeAnnotation(existing)
            selectionAnnotation = nil
        }
    }

    func drawRoute(points: [CLLocationCoordinate2D]) {
        clearRoute()
        guard points.count >= 2 else { return }
        let polyline = MKPolyline(coordinates: points, count: points.count)
        routeOverlay = polyline
        mkMapView.addOverlay(polyline)
        mkMapView.setVisibleMapRect(polyline.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
                                  animated: true)
    }

    func clearRoute() {
        if let overlay = routeOverlay {
            mkMapView.removeOverlay(overlay)
            routeOverlay = nil
        }
    }

    // MARK: - 模拟状态专用

    func updatePersonIcon(at coordinate: CLLocationCoordinate2D) {
        if let existing = personAnnotation {
            existing.coordinate = coordinate
        } else {
            let ann = MKPointAnnotation()
            ann.coordinate = coordinate
            ann.title = "模拟人物"
            personAnnotation = ann
            mkMapView.addAnnotation(ann)
        }
    }

    func removePersonIcon() {
        if let existing = personAnnotation {
            mkMapView.removeAnnotation(existing)
            personAnnotation = nil
        }
    }

    func drawRemainingRoute(from current: CLLocationCoordinate2D,
                            points: [CLLocationCoordinate2D]) {
        clearRemainingRoute()
        var coords: [CLLocationCoordinate2D] = [current]
        coords.append(contentsOf: points)
        guard coords.count >= 2 else { return }
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        remainingRouteOverlay = polyline
        mkMapView.addOverlay(polyline)
    }

    func clearRemainingRoute() {
        if let overlay = remainingRouteOverlay {
            mkMapView.removeOverlay(overlay)
            remainingRouteOverlay = nil
        }
    }

    func setShowsMyLocation(_ flag: Bool) {
        mkMapView.showsUserLocation = flag
    }

    func makeUserTrackingButton() -> UIView {
        let btn = MKUserTrackingButton(mapView: mkMapView)
        btn.tintColor = .systemBlue
        return btn
    }
}

// MARK: - MKMapViewDelegate

extension AppleMapService: MKMapViewDelegate {
    /// 用户点击三角按钮后切换跟踪模式时回调
    /// 切换到 follow / followWithHeading 时, 以用户当前位置 (蓝点) 为中心放大到 200m 街道级别
    /// 这样用户点击三角按钮后能看到附近店名
    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode,
                 animated: Bool) {
        switch mode {
        case .follow, .followWithHeading:
            // 恢复真实位置时跳过 200m 缩放, 避免缩到模拟位置
            guard shouldZoomToStreetOnFollow else { return }
            // 必须检查 userLocation.location != nil, 否则首次启动 GPS 还没来时
            // userLocation.coordinate 可能是 (0,0), 缩放过去会导致位置不在屏幕中心
            guard let userLoc = mapView.userLocation.location else { return }
            let center = userLoc.coordinate
            guard CLLocationCoordinate2DIsValid(center) else { return }
            let street = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 200,
                longitudinalMeters: 200
            )
            mapView.setRegion(street, animated: animated)
        default:
            break
        }
    }

    /// userLocation 更新时回调 (首次收到有效 GPS 后缩放到 200m 街道级别)
    /// 解决首次启动 GPS 还没来时 didChange 拿不到位置的问题
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard !hasZoomedToUserLocation else { return }
        let center = userLocation.coordinate
        guard CLLocationCoordinate2DIsValid(center) else { return }
        let street = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 200,
            longitudinalMeters: 200
        )
        mapView.setRegion(street, animated: true)
        hasZoomedToUserLocation = true
    }

    func mapView(_ mapView: MKMapView,
                 viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }

        // 人物 Icon —— 使用 figure.walk 图标，与目标 Marker 区分
        if annotation === personAnnotation {
            let id = "PersonIcon"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id)
                        as? MKMarkerAnnotationView)
                        ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.markerTintColor = .systemPurple
            view.glyphImage = UIImage(systemName: "figure.walk")
            view.canShowCallout = false
            return view
        }

        let id = "SelectionMarker"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation = annotation
        view.markerTintColor = .systemRed
        view.glyphImage = UIImage(systemName: "mappin.circle.fill")
        view.canShowCallout = true
        return view
    }

    func mapView(_ mapView: MKMapView,
                 rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            if overlay === remainingRouteOverlay {
                renderer.strokeColor = .systemTeal
                renderer.lineWidth = 5
            } else {
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
            }
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}