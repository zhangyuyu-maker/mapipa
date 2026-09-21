import CoreLocation
import MapKit
import UIKit

/// 工作模式
enum MapMode {
    case single      // 单点模拟
    case route       // 路线模拟
}

/// 地图主控制器
/// 职责：编排 MapService / GeocodingService / LocationBackend / RouteManager 与 UI 交互
/// 不直接依赖具体地图厂商（AppleMapService/AppleGeocodingService 可替换）
final class MapViewController: UIViewController {
    // MARK: - 依赖（协议注入，便于替换 Provider）
    private let mapService: MapService
    private let geocoding: GeocodingService
    private let backend: LocationBackend
    private let routeManager: RouteManager

    // MARK: - UI
    private let searchBar = SearchBarView()
    private let locationCard = LocationCardView()
    private let routeCard = RouteCardView()
    private let currentLocationButton = UIButton(type: .system)
    private let searchResults = SearchResultsViewController()
    private var routeModeButton: UIBarButtonItem?

    // MARK: - 状态
    private var mode: MapMode = .single
    private var selectedPoint: LocationPoint?       // 单点模式：地图选中的点
    private var mockPoint: LocationPoint?           // 单点模式：已设为模拟位置的点
    private var routePoints: [RoutePoint] = []      // 路线模式：路线点列表
    private let realLocationManager = CLLocationManager()
    private var currentRealLocation: CLLocation?

    init(mapService: MapService,
         geocoding: GeocodingService,
         backend: LocationBackend,
         routeManager: RouteManager) {
        self.mapService = mapService
        self.geocoding = geocoding
        self.backend = backend
        self.routeManager = routeManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "定位工具"
        view.backgroundColor = .systemBackground
        setupLayout()
        bindActions()
        setupRealLocation()
        setupLongPressGesture()
        locationCard.updateStatus(backend.status)
        updateModeUI()
        updateRouteCardInfo()
    }

    // MARK: - 布局

    private func setupLayout() {
        let mapView = mapService.mapView
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        locationCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(locationCard)

        routeCard.translatesAutoresizingMaskIntoConstraints = false
        routeCard.isHidden = true
        view.addSubview(routeCard)

        currentLocationButton.translatesAutoresizingMaskIntoConstraints = false
        currentLocationButton.setImage(UIImage(systemName: "location.fill"), for: .normal)
        currentLocationButton.backgroundColor = .systemBackground
        currentLocationButton.layer.cornerRadius = 22
        currentLocationButton.layer.shadowColor = UIColor.black.cgColor
        currentLocationButton.layer.shadowOpacity = 0.2
        currentLocationButton.layer.shadowRadius = 4
        view.addSubview(currentLocationButton)

        addChild(searchResults)
        searchResults.view.translatesAutoresizingMaskIntoConstraints = false
        searchResults.view.isHidden = true
        view.addSubview(searchResults.view)
        searchResults.didMove(toParent: self)

        let routeBtn = UIButton(type: .system)
        routeBtn.setImage(UIImage(systemName: "point.topleft.down.curvedto.point.bottomright.up"), for: .normal)
        routeBtn.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: routeBtn)
        routeModeButton = navigationItem.rightBarButtonItem

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: 52),

            mapView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            locationCard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            locationCard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            locationCard.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            routeCard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            routeCard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            routeCard.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            currentLocationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            currentLocationButton.bottomAnchor.constraint(equalTo: locationCard.topAnchor, constant: -16),
            currentLocationButton.widthAnchor.constraint(equalToConstant: 44),
            currentLocationButton.heightAnchor.constraint(equalToConstant: 44),

            searchResults.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            searchResults.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchResults.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchResults.view.bottomAnchor.constraint(equalTo: locationCard.topAnchor)
        ])
    }

    // MARK: - 模式切换

    @objc private func toggleMode() {
        switch mode {
        case .single:
            mode = .route
        case .route:
            mode = .single
        }
        updateModeUI()
    }

    private func updateModeUI() {
        let isRoute = (mode == .route)
        locationCard.isHidden = isRoute
        routeCard.isHidden = !isRoute
        title = isRoute ? "路线模拟" : "定位工具"
        if let btn = routeModeButton?.customView as? UIButton {
            btn.tintColor = isRoute ? .systemBlue : .systemGray
        }
        // 切换到单点模式时清除选中状态与地图标记
        if !isRoute {
            selectedPoint = nil
            mockPoint = nil
            mapService.removeMarker()
        } else {
            // 切换到路线模式：保留已绘制的路线，清除单点 Marker
            mapService.removeMarker()
        }
    }

    // MARK: - 绑定交互

    private func bindActions() {
        mapService.onMapTapped = { [weak self] coordinate in
            self?.handleMapTap(coordinate)
        }

        searchBar.onSearch = { [weak self] keyword in
            self?.performSearch(keyword)
        }
        searchBar.onCancel = { [weak self] in
            self?.searchResults.view.isHidden = true
        }

        searchResults.onSelect = { [weak self] result in
            self?.handleSearchResult(result)
        }

        // 单点模式回调
        locationCard.onSetMock = { [weak self] in
            guard let point = self?.selectedPoint else { return }
            self?.mockPoint = point
            self?.locationCard.setStartEnabled(true)
        }
        locationCard.onStartStop = { [weak self] in
            self?.toggleSingleSimulation()
        }

        // 路线模式回调
        routeCard.onSpeedChange = { [weak self] speed in
            self?.routeManager.updateSpeed(speed)
        }
        routeCard.onLoopChange = { _ in
            // 循环切换在下次启动路线时生效
        }
        routeCard.onClear = { [weak self] in
            self?.clearRoute()
        }
        routeCard.onStart = { [weak self] in
            self?.startRoute()
        }
        routeCard.onPause = { [weak self] in
            self?.routeManager.pause()
        }
        routeCard.onResume = { [weak self] in
            self?.routeManager.resume()
        }
        routeCard.onStop = { [weak self] in
            self?.routeManager.stop()
        }

        currentLocationButton.addTarget(self, action: #selector(showCurrentLocation), for: .touchUpInside)

        backend.onStatusChange = { [weak self] status, _ in
            self?.locationCard.updateStatus(status)
        }

        routeManager.onStatusChange = { [weak self] status in
            self?.routeCard.updateStatus(status)
        }
        routeManager.onProgress = { [weak self] progress in
            self?.routeCard.updateProgress(progress)
        }
    }

    // MARK: - 真实位置

    private func setupRealLocation() {
        realLocationManager.delegate = self
        // 使用最高精度，避免室内/缓存位置造成的偏差
        realLocationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        realLocationManager.pausesLocationUpdatesAutomatically = false
        realLocationManager.requestWhenInUseAuthorization()
    }

    @objc private func showCurrentLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            present(locationFailAlert("系统定位服务未开启"), animated: true)
            return
        }
        // 清空旧坐标，强制重新获取最新真实 GPS
        currentRealLocation = nil
        mapService.removeMarker()
        realLocationManager.requestLocation()
    }

    private func locationFailAlert(_ message: String) -> UIAlertController {
        let alert = UIAlertController(title: "定位失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        return alert
    }

    // MARK: - 长按地图设置模拟目标

    private func setupLongPressGesture() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.5
        mapService.mapView.addGestureRecognizer(lp)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let touchPoint = gesture.location(in: mapService.mapView)
        // 长按坐标必须以地图实际回调出来的 CLLocationCoordinate2D 为准
        guard let mk = mapService.mapView as? MKMapView else { return }
        let coordinate = mk.convert(touchPoint, toCoordinateFrom: mk)
        let target = LocationPoint(coordinate: coordinate, name: "模拟目标")
        // 设置模拟目标 = 长按坐标
        mockPoint = target
        selectedPoint = target
        mapService.addMarker(at: coordinate, title: "模拟目标", subtitle: nil)
        locationCard.update(point: target)
        locationCard.setStartEnabled(true)
        // 如果当前已处于模拟状态，则更新模拟目标为新的长按位置
        if backend.status == .running {
            backend.startSimulation(at: target)
        }
    }

    // MARK: - 地图点选

    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        switch mode {
        case .single:
            handleSingleModeTap(coordinate)
        case .route:
            handleRouteModeTap(coordinate)
        }
    }

    private func handleSingleModeTap(_ coordinate: CLLocationCoordinate2D) {
        Task {
            let point = LocationPoint(coordinate: coordinate)
            await MainActor.run {
                self.selectedPoint = point
                self.mapService.addMarker(at: coordinate, title: nil, subtitle: nil)
                self.locationCard.update(point: point)
            }
            do {
                let address = try await geocoding.reverseGeocode(latitude: coordinate.latitude,
                                                                  longitude: coordinate.longitude)
                let full = LocationPoint(latitude: coordinate.latitude,
                                         longitude: coordinate.longitude,
                                         name: address.name,
                                         address: address.fullAddress.isEmpty ? nil : address.fullAddress)
                await MainActor.run {
                    self.selectedPoint = full
                    self.mapService.addMarker(at: coordinate,
                                              title: full.name,
                                              subtitle: full.address)
                    self.locationCard.update(point: full)
                }
            } catch {
                // 逆地理失败不影响已选点
            }
        }
    }

    private func handleRouteModeTap(_ coordinate: CLLocationCoordinate2D) {
        let index = routePoints.count
        let point = RoutePoint(coordinate: coordinate,
                               name: "点\(index + 1)")
        routePoints.append(point)
        redrawRouteOnMap()
        updateRouteCardInfo()
    }

    // MARK: - 搜索

    private func performSearch(_ keyword: String) {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults.results = []
            searchResults.view.isHidden = false
            return
        }
        Task {
            do {
                let region = currentRealLocation.map {
                    CLCircularRegion(center: $0.coordinate, radius: 50_000, identifier: "search")
                }
                let results = try await geocoding.search(keyword: keyword, region: region)
                await MainActor.run {
                    self.searchResults.results = results
                    self.searchResults.view.isHidden = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults.results = []
                    self.searchResults.view.isHidden = false
                }
            }
        }
    }

    private func handleSearchResult(_ result: LocationSearchResult) {
        switch mode {
        case .single:
            handleSingleSearchResult(result)
        case .route:
            handleRouteSearchResult(result)
        }
    }

    private func handleSingleSearchResult(_ result: LocationSearchResult) {
        let coordinate = result.coordinate
        mapService.showLocation(coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        let point = result.point
        selectedPoint = point
        mapService.addMarker(at: coordinate, title: point.name, subtitle: point.address)
        locationCard.update(point: point)
        searchResults.view.isHidden = true
    }

    private func handleRouteSearchResult(_ result: LocationSearchResult) {
        let index = routePoints.count
        let point = RoutePoint(coordinate: result.coordinate,
                               name: result.point.name ?? "点\(index + 1)")
        routePoints.append(point)
        mapService.showLocation(result.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        redrawRouteOnMap()
        updateRouteCardInfo()
        searchResults.view.isHidden = true
    }

    // MARK: - 路线绘制

    private func redrawRouteOnMap() {
        if routePoints.isEmpty {
            mapService.clearRoute()
            mapService.removeMarker()
            return
        }
        let coords = routePoints.map { $0.coordinate }
        mapService.drawRoute(points: coords)
        // 在终点放一个 Marker
        if let last = routePoints.last {
            mapService.addMarker(at: last.coordinate,
                                 title: last.name,
                                 subtitle: "终点")
        }
    }

    private func updateRouteCardInfo() {
        let route = Route(points: routePoints,
                         speedMetersPerSecond: routeCard.currentSpeed(),
                         loop: routeCard.currentLoop())
        routeCard.updateRouteInfo(pointCount: routePoints.count,
                                  totalDistance: route.totalDistance,
                                  estimatedDuration: route.estimatedDuration)
    }

    // MARK: - 路线模拟控制

    private func startRoute() {
        guard routePoints.count >= 2 else {
            let alert = UIAlertController(title: "路线点不足",
                                          message: "至少需要 2 个路线点才能开始模拟",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        routeCard.resetProgress()
        let route = Route(points: routePoints,
                         speedMetersPerSecond: routeCard.currentSpeed(),
                         loop: routeCard.currentLoop())
        routeManager.start(route: route, backend: backend)
    }

    private func clearRoute() {
        routeManager.stop()
        routePoints.removeAll()
        mapService.clearRoute()
        mapService.removeMarker()
        routeCard.resetProgress()
        updateRouteCardInfo()
    }

    // MARK: - 单点模拟

    private func toggleSingleSimulation() {
        switch backend.status {
        case .stopped:
            // 起点概念上为当前真实 GPS 位置；目标点为用户长按地图所选位置
            // SystemLocationBackend.startSimulation 直接将系统定位注入到目标坐标
            guard let point = mockPoint else {
                // 未指定目标 → 提示用户长按地图选择模拟目标
                let alert = UIAlertController(title: "未选择目标",
                                              message: "请长按地图选择模拟目标位置",
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                present(alert, animated: true)
                return
            }
            backend.startSimulation(at: point)
        case .running:
            backend.stopSimulation()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension MapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // 过滤缓存坐标：timestamp 超过 5 秒视为旧位置，丢弃
        if Date().timeIntervalSince(location.timestamp) > 5 { return }
        currentRealLocation = location
        // 地图中心以真实 GPS 坐标为准
        mapService.showLocation(location.coordinate,
                                latitudinalMeters: 500,
                                longitudinalMeters: 500)
        // 显式显示"我的位置"Marker，不依赖系统蓝点（系统蓝点可能用不同定位源）
        mapService.addMarker(at: location.coordinate, title: "我的位置", subtitle: nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 获取不到真实 GPS 时，明确提示定位失败，不要使用其他位置代替
        present(locationFailAlert(error.localizedDescription), animated: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }
}
