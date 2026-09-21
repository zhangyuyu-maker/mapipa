import CoreLocation
import MapKit
import UIKit

/// 地图主控制器
/// 职责：编排 MapService / GeocodingService / LocationBackend 与 UI 交互
/// 不直接依赖具体地图厂商（AppleMapService/AppleGeocodingService 可替换）
final class MapViewController: UIViewController {
    // MARK: - 依赖（协议注入，便于替换 Provider）
    private let mapService: MapService
    private let geocoding: GeocodingService
    private let backend: LocationBackend

    // MARK: - UI
    private let searchBar = SearchBarView()
    private let locationCard = LocationCardView()
    private let currentLocationButton = UIButton(type: .system)
    private let searchResults = SearchResultsViewController()

    // MARK: - 状态
    private var selectedPoint: LocationPoint?   // 地图选中的点
    private var mockPoint: LocationPoint?       // 已设为模拟位置的点
    private let realLocationManager = CLLocationManager()
    private var currentRealLocation: CLLocation?

    init(mapService: MapService,
         geocoding: GeocodingService,
         backend: LocationBackend) {
        self.mapService = mapService
        self.geocoding = geocoding
        self.backend = backend
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
        locationCard.updateStatus(backend.status)
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

        locationCard.onSetMock = { [weak self] in
            guard let point = self?.selectedPoint else { return }
            self?.mockPoint = point
            self?.locationCard.setStartEnabled(true)
        }

        locationCard.onStartStop = { [weak self] in
            self?.toggleSimulation()
        }

        currentLocationButton.addTarget(self, action: #selector(showCurrentLocation), for: .touchUpInside)

        backend.onStatusChange = { [weak self] status, _ in
            self?.locationCard.updateStatus(status)
        }
    }

    // MARK: - 真实位置

    private func setupRealLocation() {
        realLocationManager.delegate = self
        realLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        realLocationManager.requestWhenInUseAuthorization()
    }

    @objc private func showCurrentLocation() {
        if CLLocationManager.locationServicesEnabled() {
            realLocationManager.requestLocation()
        }
    }

    // MARK: - 地图点选

    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
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
        let coordinate = result.coordinate
        mapService.showLocation(coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        let point = result.point
        selectedPoint = point
        mapService.addMarker(at: coordinate, title: point.name, subtitle: point.address)
        locationCard.update(point: point)
        searchResults.view.isHidden = true
    }

    // MARK: - 模拟定位

    private func toggleSimulation() {
        switch backend.status {
        case .stopped:
            guard let point = mockPoint else { return }
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
        currentRealLocation = location
        mapService.showLocation(location.coordinate,
                                latitudinalMeters: 500,
                                longitudinalMeters: 500)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 真实位置获取失败时静默处理，用户仍可手动选点
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }
}
