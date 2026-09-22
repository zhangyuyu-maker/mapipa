import CoreLocation
import Foundation
import MapKit

/// 路线模拟管理器
/// 职责：用 MKDirections 规划真实道路路线，沿道路坐标推进位置
/// 将每个推进点交给 LocationBackend 注入系统
final class RouteManager {
    private var route: Route?
    private weak var backend: LocationBackend?

    private var isTimerRunning = false
    private let tickInterval: TimeInterval = 0.2

    /// 道路坐标数组（由 MKDirections 规划得到，非用户点直线）
    private var roadPath: [CLLocationCoordinate2D] = []
    /// 道路坐标的累积距离数组
    private var roadCumulative: [Double] = []
    /// 道路总距离
    private var roadTotalDistance: Double = 0

    private var elapsedDistance: Double = 0

    private(set) var status: RouteStatus = .stopped

    var onProgress: ((RouteProgress) -> Void)?
    var onStatusChange: ((RouteStatus) -> Void)?
    /// 路线规划失败回调
    var onRoutePlanningFailed: (() -> Void)?

    func start(route: Route, backend: LocationBackend) {
        guard route.points.count >= 2 else { return }
        stopTimer()
        self.route = route
        self.backend = backend

        status = .running
        onStatusChange?(status)

        // 异步规划真实道路路线
        planRoadRoute(points: route.points) { [weak self] coords, success in
            guard let self = self else { return }
            guard success, let coords = coords, coords.count >= 2 else {
                // 路线规划失败, 停止模拟
                self.status = .stopped
                self.onStatusChange?(self.status)
                self.onRoutePlanningFailed?()
                return
            }
            // 计算道路坐标的累积距离
            var cum: [Double] = [0]
            for i in 1..<coords.count {
                let a = CLLocation(latitude: coords[i - 1].latitude,
                                  longitude: coords[i - 1].longitude)
                let b = CLLocation(latitude: coords[i].latitude,
                                  longitude: coords[i].longitude)
                cum.append(cum.last! + a.distance(from: b))
            }
            self.roadPath = coords
            self.roadCumulative = cum
            self.roadTotalDistance = cum.last ?? 0
            self.elapsedDistance = 0

            // 立即下发起点
            let startCoord = coords[0]
            backend.startSimulation(at: LocationPoint(latitude: startCoord.latitude,
                                                      longitude: startCoord.longitude))
            self.emitProgress(at: 0, coordinate: startCoord)
            self.startTimer()
        }
    }

    // MARK: - MKDirections 道路路线规划

    /// 用 MKDirections 分段规划每两个相邻点之间的真实道路路线
    /// 拼接所有段的道路坐标成一条完整路线
    private func planRoadRoute(points: [RoutePoint],
                               completion: @escaping ([CLLocationCoordinate2D]?, Bool) -> Void) {
        guard points.count >= 2 else {
            completion(nil, false)
            return
        }

        var allCoords: [CLLocationCoordinate2D] = []
        let group = DispatchGroup()
        var hasFailed = false

        for i in 0..<(points.count - 1) {
            group.enter()
            let source = MKMapItem(placemark: MKPlacemark(coordinate: points[i].coordinate))
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: points[i + 1].coordinate))
            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = .automobile

            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                if let _ = error {
                    hasFailed = true
                    group.leave()
                    return
                }
                guard let route = response?.routes.first else {
                    hasFailed = true
                    group.leave()
                    return
                }
                // 提取 polyline 的所有道路坐标点
                let count = route.polyline.pointCount
                var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                      count: count)
                route.polyline.getCoordinates(&coords,
                                              range: NSRange(location: 0, length: count))
                // 拼接到完整路线 (跳过每段第一个点避免重复, 第一段保留)
                let startIdx = (i == 0) ? 0 : 1
                allCoords.append(contentsOf: coords[startIdx...])
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if hasFailed || allCoords.count < 2 {
                completion(nil, false)
            } else {
                completion(allCoords, true)
            }
        }
    }

    func pause() {
        guard status == .running else { return }
        status = .paused
        onStatusChange?(status)
        stopTimer()
    }

    func resume() {
        guard status == .paused, route != nil else { return }
        status = .running
        onStatusChange?(status)
        startTimer()
    }

    func stop() {
        stopTimer()
        status = .stopped
        onStatusChange?(status)
        backend?.stopSimulation()
        elapsedDistance = 0
        roadPath = []
        roadCumulative = []
        roadTotalDistance = 0
        route = nil
    }

    /// 实时更新速度（无需重启即可生效）
    func updateSpeed(_ speed: Double) {
        guard var r = route else { return }
        r.speedMetersPerSecond = speed
        route = r
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        isTimerRunning = true
        scheduleNextTick()
    }

    private func stopTimer() {
        isTimerRunning = false
    }

    private func scheduleNextTick() {
        let ms = Int(tickInterval * 1000)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
            guard let self = self, self.isTimerRunning else { return }
            // 切到主线程执行 tick, 避免与 stop/pause/updateSpeed 等主线程操作竞争
            DispatchQueue.main.async {
                guard self.isTimerRunning else { return }
                self.tick()
                self.scheduleNextTick()
            }
        }
    }

    // MARK: - 沿道路坐标推进

    private func tick() {
        guard !roadPath.isEmpty, roadPath.count >= 2 else { return }
        let speed = route?.speedMetersPerSecond ?? 5.0
        let step = speed * tickInterval
        elapsedDistance += step

        if elapsedDistance >= roadTotalDistance {
            if route?.loop == true {
                elapsedDistance = elapsedDistance.truncatingRemainder(dividingBy: roadTotalDistance)
            } else {
                // 到达终点
                elapsedDistance = roadTotalDistance
                let end = roadPath.last!
                backend?.startSimulation(at: LocationPoint(latitude: end.latitude,
                                                           longitude: end.longitude))
                emitProgress(at: roadPath.count - 2, coordinate: end)
                stopTimer()
                status = .stopped
                onStatusChange?(status)
                return
            }
        }

        // 找到当前段
        var idx = 0
        while idx < roadCumulative.count - 2 && elapsedDistance >= roadCumulative[idx + 1] {
            idx += 1
        }
        // 在段内插值
        let segStart = roadCumulative[idx]
        let segEnd = roadCumulative[idx + 1]
        let segLen = segEnd - segStart
        let t = segLen > 0 ? (elapsedDistance - segStart) / segLen : 0
        let p0 = roadPath[idx]
        let p1 = roadPath[idx + 1]
        let lat = p0.latitude + (p1.latitude - p0.latitude) * t
        let lon = p0.longitude + (p1.longitude - p0.longitude) * t
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        backend?.startSimulation(at: LocationPoint(latitude: lat, longitude: lon))
        emitProgress(at: idx, coordinate: coord)
    }

    private func emitProgress(at segmentIndex: Int, coordinate: CLLocationCoordinate2D) {
        guard let route = route else { return }
        // 计算剩余道路坐标 (从当前段到末尾)
        let remaining = Array(roadPath[segmentIndex...])
        let p = RouteProgress(elapsedDistance: elapsedDistance,
                              totalDistance: roadTotalDistance,
                              speed: route.speedMetersPerSecond,
                              segmentIndex: segmentIndex,
                              totalSegments: max(0, roadPath.count - 1),
                              currentCoordinate: coordinate,
                              remainingCoordinates: remaining)
        // tick 已在主线程执行, 直接回调
        onProgress?(p)
    }
}
