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

    override init() {
        let mv = MKMapView(frame: .zero)
        mv.showsCompass = true
        mv.showsScale = true
        mv.showsUserLocation = true
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
}

// MARK: - MKMapViewDelegate

extension AppleMapService: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView,
                 viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }
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
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 4
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
