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
    private var userTrackingButton: UIView!
    private var restoreRealLocationButton: UIButton!
    private let searchResults = SearchResultsViewController()
    private var routeModeButton: UIBarButtonItem?

    // MARK: - 状态（真实位置 / 模拟位置 彻底分离）
    private var mode: MapMode = .single
    /// 真实 GPS 位置（由 CLLocationManager 获取，模拟期间只保存不显示）
    private var realLocation: CLLocation?
    /// 当前模拟位置（模拟期间地图中心/人物 Icon/Marker 都跟随此坐标）
    private var simulationLocation: CLLocation?
    /// 途径点列表（单点模式：长按或"增加途径点"模式下点击地图添加）
    private var waypoints: [LocationPoint] = []
    /// 当前途径点索引
    private var currentWaypointIndex: Int = 0
    /// 当前模拟目标点
    private var simulationTarget: LocationPoint?
    /// 单点模式：用户长按选定的最终目标
    private var mockPoint: LocationPoint?
    /// 单点模式：用户选中的点（用于卡片显示）
    private var selectedPoint: LocationPoint?
    /// 路线模式：路线点列表
    private var routePoints: [RoutePoint] = []
    /// 是否处于"增加途径点"模式
    private var isAddingWaypoint: Bool = false
    /// 当前单点模拟构建的路线点（供 onRouteProgress 计算剩余路线）
    private var currentSingleRoutePoints: [RoutePoint] = []

    private let realLocationManager = CLLocationManager()

    /// 是否处于模拟状态
    private var isSimulating: Bool {
        backend.status == .running || routeManager.status == .running
    }

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
        locationCard.updateWaypointCount(waypoints.count)
        updateModeUI()
        updateRouteCardInfo()
        // 默认显示一个区域，避免真实 GPS 还没回来时地图空白
        let defaultCoord = CLLocationCoordinate2D(latitude: 35.0, longitude: 105.0)
        mapService.showLocation(defaultCoord, latitudinalMeters: 2_000_000, longitudinalMeters: 2_000_000)
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

        userTrackingButton = mapService.makeUserTrackingButton()
        userTrackingButton.translatesAutoresizingMaskIntoConstraints = false
        userTrackingButton.backgroundColor = .systemBackground
        userTrackingButton.layer.cornerRadius = 22
        userTrackingButton.layer.shadowColor = UIColor.black.cgColor
        userTrackingButton.layer.shadowOpacity = 0.2
        userTrackingButton.layer.shadowRadius = 4
        view.addSubview(userTrackingButton)

        // 恢复真实位置浮动按钮 (放在三角形按钮上方, 用 icon 显示)
        restoreRealLocationButton = UIButton(type: .system)
        restoreRealLocationButton.setImage(UIImage(systemName: "location.fill",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
                                           for: .normal)
        restoreRealLocationButton.tintColor = .systemOrange
        restoreRealLocationButton.translatesAutoresizingMaskIntoConstraints = false
        restoreRealLocationButton.backgroundColor = .systemBackground
        restoreRealLocationButton.layer.cornerRadius = 22
        restoreRealLocationButton.layer.shadowColor = UIColor.black.cgColor
        restoreRealLocationButton.layer.shadowOpacity = 0.2
        restoreRealLocationButton.layer.shadowRadius = 4
        restoreRealLocationButton.addTarget(self, action: #selector(restoreRealLocation), for: .touchUpInside)
        // 默认隐藏, 仅模拟运行时显示
        restoreRealLocationButton.isHidden = true
        view.addSubview(restoreRealLocationButton)

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

            userTrackingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            userTrackingButton.bottomAnchor.constraint(equalTo: locationCard.topAnchor, constant: -16),
            userTrackingButton.widthAnchor.constraint(equalToConstant: 44),
            userTrackingButton.heightAnchor.constraint(equalToConstant: 44),
            restoreRealLocationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            restoreRealLocationButton.bottomAnchor.constraint(equalTo: userTrackingButton.topAnchor, constant: -12),
            restoreRealLocationButton.widthAnchor.constraint(equalToConstant: 44),
            restoreRealLocationButton.heightAnchor.constraint(equalToConstant: 44),

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
        if !isRoute {
            selectedPoint = nil
            mockPoint = nil
            mapService.removeMarker()
        } else {
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
        locationCard.onAddWaypoint = { [weak self] in
            self?.toggleWaypointAdding()
        }

        // 路线模式回调
        routeCard.onSpeedChange = { [weak self] speed in
            self?.routeManager.updateSpeed(speed)
        }
        routeCard.onLoopChange = { _ in }
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


        backend.onStatusChange = { [weak self] status, _ in
            self?.locationCard.updateStatus(status)
            // 模拟运行时显示恢复按钮, 停止时隐藏
            self?.restoreRealLocationButton.isHidden = (status != .running)
            if status == .stopped {
                self?.onSimulationEnded()
            }
        }

        routeManager.onStatusChange = { [weak self] status in
            self?.routeCard.updateStatus(status)
            self?.restoreRealLocationButton.isHidden = (status != .running)
            if status == .stopped {
                self?.onSimulationEnded()
            }
        }
        routeManager.onProgress = { [weak self] progress in
            self?.onRouteProgress(progress)
        }
    }

    // MARK: - 真实位置（realLocation）

    private func setupRealLocation() {
        realLocationManager.delegate = self
        // 使用最高精度，避免室内/缓存位置造成的偏差
        realLocationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        realLocationManager.pausesLocationUpdatesAutomatically = false
        realLocationManager.distanceFilter = kCLDistanceFilterNone
        realLocationManager.requestWhenInUseAuthorization()
        // 已授权则立即请求一次位置（避免已授权用户启动时地图空白无蓝点）
        if realLocationManager.authorizationStatus == .authorizedWhenInUse
            || realLocationManager.authorizationStatus == .authorizedAlways {
            // 设置跟踪模式: 蓝点一出现就自动居中, 避免启动时蓝点在屏幕边缘
            if let mk = mapService.mapView as? MKMapView {
                mk.setUserTrackingMode(.follow, animated: false)
            }
            realLocationManager.requestLocation()
        }
    }

    /// 右下角"我的位置"按钮
    /// 非模拟状态：以最新真实 GPS 为准
    /// 模拟状态：以 simulationLocation 为准（不获取真实 GPS）
    @objc private func showCurrentLocation() {
        if isSimulating {
            // 模拟中：地图中心跟随 simulationLocation
            if let sim = simulationLocation {
                mapService.showLocation(sim.coordinate,
                                        latitudinalMeters: 200,
                                        longitudinalMeters: 200)
            }
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            present(locationFailAlert("系统定位服务未开启"), animated: true)
            return
        }
        // 清空旧坐标，强制重新获取最新真实 GPS（系统蓝点会自动显示）
        realLocation = nil
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
        guard let mk = mapService.mapView as? MKMapView else { return }
        let coordinate = mk.convert(touchPoint, toCoordinateFrom: mk)

        // "增加途径点"模式：把长按位置作为途径点
        if isAddingWaypoint {
            let wp = LocationPoint(coordinate: coordinate, name: "途径点\(waypoints.count + 1)")
            waypoints.append(wp)
            locationCard.updateWaypointCount(waypoints.count)
            mapService.addMarker(at: coordinate, title: wp.name, subtitle: nil)
            return
        }

        // 长按 = 单纯修改系统定位到长按位置
        // 蓝点 (showsUserLocation) 保持显示, backend.startSimulation 后系统蓝点会自动跑到长按位置
        // 不弹功能框、不加红色 marker、不加人物 icon —— 蓝点本身就是当前位置
        let wgs84Coord = CoordTransform.gcj02ToWgs84(coordinate)
        let target = LocationPoint(coordinate: wgs84Coord, name: "模拟位置")
        mockPoint = target
        simulationTarget = target
        simulationLocation = CLLocation(latitude: wgs84Coord.latitude, longitude: wgs84Coord.longitude)
        // 立即注入到系统层 (WGS-84), 蓝点会自动跳到长按位置
        // MKMapView 显示蓝点时会自动把 WGS-84 转回 GCJ-02, 所以蓝点正好落在用户长按位置
        // 不调用 mapService.showLocation -- 保留用户当前缩放级别
        backend.startSimulation(at: target)
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
        // "增加途径点"模式下，单击地图也添加途径点
        if isAddingWaypoint {
            let wp = LocationPoint(coordinate: coordinate, name: "途径点\(waypoints.count + 1)")
            waypoints.append(wp)
            locationCard.updateWaypointCount(waypoints.count)
            mapService.addMarker(at: coordinate, title: wp.name, subtitle: nil)
            return
        }

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

    // MARK: - 途径点模式切换

    private func toggleWaypointAdding() {
        isAddingWaypoint.toggle()
        locationCard.setWaypointAdding(isAddingWaypoint)
        if isAddingWaypoint {
            // 进入途径点添加模式，清除当前选中点 Marker
            mapService.removeMarker()
        }
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
                let region = realLocation.map {
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
        mockPoint = point
        simulationTarget = point
        mapService.addMarker(at: coordinate, title: point.name, subtitle: point.address)
        locationCard.update(point: point)
        locationCard.setStartEnabled(true)
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

    // MARK: - 路线模式模拟控制

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

    // MARK: - 单点模拟（人物移动 + 路线推进）

    private func toggleSingleSimulation() {
        if isSimulating {
            // 停止模拟
            routeManager.stop()
            backend.stopSimulation()
            return
        }
        startSingleSimulation()
    }

    private func startSingleSimulation() {
        // 起点规则：
        // - 已有 simulationLocation：从当前模拟位置继续
        // - 首次模拟：从真实 GPS 位置开始
        let startPoint: LocationPoint
        if let sim = simulationLocation {
            startPoint = LocationPoint(coordinate: sim.coordinate, name: "当前模拟位置")
        } else if let real = realLocation {
            startPoint = LocationPoint(coordinate: real.coordinate, name: "起点")
            simulationLocation = real
        } else {
            // 没有真实位置，提示先获取
            let alert = UIAlertController(title: "无真实位置",
                                          message: "请先点击右下角「我的位置」获取真实 GPS",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }

        // 构建路线点：[起点, 途径点1, 途径点2, ..., 最终目标]
        var routePoints: [RoutePoint] = [RoutePoint(coordinate: startPoint.coordinate, name: "起点")]
        routePoints.append(contentsOf: waypoints.map { RoutePoint(coordinate: $0.coordinate, name: $0.name) })
        if let target = mockPoint {
            // 避免与途径点重复
            let exists = waypoints.contains { $0.coordinate.latitude == target.coordinate.latitude
                                              && $0.coordinate.longitude == target.coordinate.longitude }
            if !exists {
                routePoints.append(RoutePoint(coordinate: target.coordinate, name: target.name ?? "目标"))
            }
        }
        guard routePoints.count >= 2 else {
            let alert = UIAlertController(title: "未选择目标",
                                          message: "请长按地图选择模拟目标位置，或点击「增加途径点」",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        // 速度按单点模式默认 5 m/s（可后续暴露 UI 调整）
        let route = Route(points: routePoints, speedMetersPerSecond: 5.0, loop: false)
        simulationTarget = mockPoint ?? waypoints.last
        currentWaypointIndex = 0
        // 隐藏系统蓝点，避免与模拟位置混淆
        mapService.setShowsMyLocation(false)
        // 显示人物 Icon
        mapService.updatePersonIcon(at: startPoint.coordinate)
        // 绘制剩余路线：起点 → 途径点 → 目标
        let remaining = routePoints.dropFirst().map { $0.coordinate }
        mapService.drawRemainingRoute(from: startPoint.coordinate, points: remaining)
        // 保存当前路线点供 onRouteProgress 使用
        currentSingleRoutePoints = routePoints
        // 启动 RouteManager 推进
        routeManager.start(route: route, backend: backend)
    }

    /// 模拟过程中长按更新目标
    private func restartSingleSimulationWithNewTarget(_ newTarget: LocationPoint) {
        // 当前 simulationLocation 作为新起点
        guard let sim = simulationLocation else { return }
        let startPoint = LocationPoint(coordinate: sim.coordinate, name: "当前模拟位置")
        var newRoutePoints: [RoutePoint] = [RoutePoint(coordinate: startPoint.coordinate, name: "起点")]
        // 保留未到达的途径点
        let remainingWaypoints = Array(waypoints.dropFirst(currentWaypointIndex))
        newRoutePoints.append(contentsOf: remainingWaypoints.map { RoutePoint(coordinate: $0.coordinate, name: $0.name) })
        newRoutePoints.append(RoutePoint(coordinate: newTarget.coordinate, name: newTarget.name ?? "目标"))
        let route = Route(points: newRoutePoints, speedMetersPerSecond: 5.0, loop: false)
        simulationTarget = newTarget
        mockPoint = newTarget
        // 停止当前并重启
        routeManager.stop()
        // restart 时 stopSimulation 会清除状态，重新 start
        mapService.updatePersonIcon(at: startPoint.coordinate)
        let remaining = newRoutePoints.dropFirst().map { $0.coordinate }
        mapService.drawRemainingRoute(from: startPoint.coordinate, points: remaining)
        currentSingleRoutePoints = newRoutePoints
        routeManager.start(route: route, backend: backend)
    }

    /// RouteManager 推进回调：更新 simulationLocation / 人物 Icon / 地图中心 / 剩余路线
    private func onRouteProgress(_ progress: RouteProgress) {
        let coord = progress.currentCoordinate
        simulationLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        // 更新人物 Icon
        mapService.updatePersonIcon(at: coord)
        // 地图中心跟随 simulationLocation
        mapService.moveTo(coord)
        // 重新计算剩余路线：当前点 → 剩余途径点
        // 段索引 progress.segmentIndex 表示当前在 第 idx 到 第 idx+1 段
        // 剩余点 = [idx+1, idx+2, ..., 末尾]
        let routePoints = currentSingleRoutePoints
        let remainingIdx = progress.segmentIndex + 1
        if remainingIdx < routePoints.count {
            let remaining = Array(routePoints[remainingIdx...].map { $0.coordinate })
            mapService.drawRemainingRoute(from: coord, points: remaining)
        } else {
            mapService.clearRemainingRoute()
        }
        currentWaypointIndex = progress.segmentIndex
    }

    /// 模拟结束回调
    private func onSimulationEnded() {
        // 不自动恢复真实位置（保持当前位置），仅清除人物 Icon 和剩余路线
        // 由用户点击"恢复真实位置"主动恢复
        mapService.clearRemainingRoute()
        // 保留人物 Icon 在最后位置直到用户恢复真实位置
    }

    // MARK: - 恢复真实位置

    @objc private func restoreRealLocation() {
        // 1. 停止当前模拟
        routeManager.stop()
        backend.stopSimulation()
        // 2. 清除模拟状态
        simulationLocation = nil
        simulationTarget = nil
        waypoints.removeAll()
        currentWaypointIndex = 0
        mockPoint = nil
        selectedPoint = nil
        locationCard.update(point: nil)
        locationCard.updateWaypointCount(0)
        locationCard.setStartEnabled(false)
        // 3. 清除地图人物 Icon 与剩余路线，恢复系统蓝点显示
        mapService.removePersonIcon()
        mapService.clearRemainingRoute()
        mapService.setShowsMyLocation(true)
        // 4. 切换到跟随模式: 蓝点会从模拟位置过渡回真实位置, 地图自动跟随
        if let mk = mapService.mapView as? MKMapView {
            mk.setUserTrackingMode(.follow, animated: true)
        }
        // 5. 重新获取最新真实 GPS
        realLocation = nil
        guard CLLocationManager.locationServicesEnabled() else {
            present(locationFailAlert("系统定位服务未开启"), animated: true)
            return
        }
        realLocationManager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension MapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // 过滤缓存坐标：timestamp 超过 5 秒视为旧位置，丢弃
        if Date().timeIntervalSince(location.timestamp) > 5 { return }
        // 过滤低精度坐标
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 50 { return }
        realLocation = location
        // 模拟中：realLocation 只保存，绝不修改地图中心 / Marker / 人物 Icon
        if isSimulating { return }
        // 非模拟：地图中心 = realLocation（系统蓝点自动显示真实位置）
        mapService.showLocation(location.coordinate,
                                latitudinalMeters: 500,
                                longitudinalMeters: 500)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 过滤 locationd 处于模拟模式时的伪错误:
        // 修改定位后重启 app, locationd 仍在用 CLSimulationManager 注入的模拟位置,
        // CLLocationManager.requestLocation() 拿不到真实位置会回调 didFailWithError,
        // 错误码为 kCLErrorUnknown (0) - 这不是真正的错误, 不应弹框打扰用户.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        if let clError = error as? CLError, clError.code == .denied { return }
        present(locationFailAlert(error.localizedDescription), animated: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }
}