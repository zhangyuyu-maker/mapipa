import CoreLocation
import Foundation

/// 路线模拟管理器
/// 职责：按 Route 配置沿折线推进位置，将每个推进点交给 LocationBackend 注入系统
/// 与 MapService 解耦——地图层只负责显示路线与当前位置，推进逻辑集中于此
final class RouteManager {
    private var route: Route?
    private weak var backend: LocationBackend?

    private var timer: Timer?
    private let tickInterval: TimeInterval = 0.5

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
        backend.startSimulation(at: route.points[0].locationPoint)
        emitProgress(at: 0)
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
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
                backend?.startSimulation(at: route.points.last!.locationPoint)
                emitProgress(at: route.points.count - 2)
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
        let point = LocationPoint(latitude: lat, longitude: lon)
        backend?.startSimulation(at: point)
        emitProgress(at: idx)
    }

    private func emitProgress(at segmentIndex: Int) {
        guard let route = route else { return }
        let p = RouteProgress(elapsedDistance: elapsedDistance,
                              totalDistance: totalDistance,
                              speed: route.speedMetersPerSecond,
                              segmentIndex: segmentIndex,
                              totalSegments: max(0, route.points.count - 1))
        onProgress?(p)
    }
}
