import CoreLocation
import Foundation

/// 路线模拟管理器
/// 职责：按 Route 配置沿折线推进位置，将每个推进点交给 LocationBackend 注入系统
/// 与 MapService 解耦——地图层只负责显示路线与当前位置，推进逻辑集中于此
final class RouteManager {
    private var route: Route?
    private weak var backend: LocationBackend?

    private var isTimerRunning = false
    private let tickInterval: TimeInterval = 0.2

    /// 累积距离数组：cumulative[i] 表示到第 i 个点的累计距离
    private var cumulative: [Double] = []
    private var totalDistance: Double = 0

    private var elapsedDistance: Double = 0

    private(set) var status: RouteStatus = .stopped

    var onProgress: ((RouteProgress) -> Void)?
    var onStatusChange: ((RouteStatus) -> Void)?

    func start(route: Route, backend: LocationBackend) {
        guard route.points.count >= 2 else { return }
        stopTimer()
        self.route = route
        self.backend = backend

        // 计算累积距离
        var cum: [Double] = [0]
        for i in 1..<route.points.count {
            let a = CLLocation(latitude: route.points[i - 1].latitude,
                              longitude: route.points[i - 1].longitude)
            let b = CLLocation(latitude: route.points[i].latitude,
                              longitude: route.points[i].longitude)
            cum.append(cum.last! + a.distance(from: b))
        }
        cumulative = cum
        totalDistance = cum.last ?? 0
        elapsedDistance = 0

        status = .running
        onStatusChange?(status)

        // 立即下发起点
        let startPoint = route.points[0]
        backend.startSimulation(at: startPoint.locationPoint)
        emitProgress(at: 0, coordinate: startPoint.coordinate)
        startTimer()
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
        cumulative = []
        totalDistance = 0
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
            self.tick()
            self.scheduleNextTick()
        }
    }

    // MARK: - 推进

    private func tick() {
        guard let route = route, route.points.count >= 2 else { return }
        let step = route.speedMetersPerSecond * tickInterval
        elapsedDistance += step

        if elapsedDistance >= totalDistance {
            if route.loop {
                elapsedDistance = elapsedDistance.truncatingRemainder(dividingBy: totalDistance)
            } else {
                // 到达终点
                elapsedDistance = totalDistance
                let end = route.points.last!
                backend?.startSimulation(at: end.locationPoint)
                emitProgress(at: route.points.count - 2, coordinate: end.coordinate)
                stopTimer()
                status = .stopped
                onStatusChange?(status)
                return
            }
        }

        // 找到当前段
        var idx = 0
        while idx < cumulative.count - 2 && elapsedDistance >= cumulative[idx + 1] {
            idx += 1
        }
        // 在段内插值
        let segStart = cumulative[idx]
        let segEnd = cumulative[idx + 1]
        let segLen = segEnd - segStart
        let t = segLen > 0 ? (elapsedDistance - segStart) / segLen : 0
        let p0 = route.points[idx]
        let p1 = route.points[idx + 1]
        let lat = p0.latitude + (p1.latitude - p0.latitude) * t
        let lon = p0.longitude + (p1.longitude - p0.longitude) * t
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let point = LocationPoint(latitude: lat, longitude: lon)
        backend?.startSimulation(at: point)
        emitProgress(at: idx, coordinate: coord)
    }

    private func emitProgress(at segmentIndex: Int, coordinate: CLLocationCoordinate2D) {
        guard let route = route else { return }
        let p = RouteProgress(elapsedDistance: elapsedDistance,
                              totalDistance: totalDistance,
                              speed: route.speedMetersPerSecond,
                              segmentIndex: segmentIndex,
                              totalSegments: max(0, route.points.count - 1),
                              currentCoordinate: coordinate)
        onProgress?(p)
    }
}