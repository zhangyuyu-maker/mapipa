import CoreLocation
import Foundation

/// 路线点
/// 路线由一系列 RoutePoint 组成，按顺序连接成折线
struct RoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let name: String?

    init(coordinate: CLLocationCoordinate2D, name: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.name = name
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationPoint: LocationPoint {
        LocationPoint(latitude: latitude, longitude: longitude, name: name)
    }
}

/// 路线
/// 由多个点顺序连接，模拟时按 speedMetersPerSecond 沿折线推进
struct Route: Codable {
    var points: [RoutePoint]
    var speedMetersPerSecond: Double
    var loop: Bool

    init(points: [RoutePoint] = [],
         speedMetersPerSecond: Double = 5.0,
         loop: Bool = false) {
        self.points = points
        self.speedMetersPerSecond = speedMetersPerSecond
        self.loop = loop
    }

    /// 路线总距离（米）
    var totalDistance: Double {
        guard points.count >= 2 else { return 0 }
        var d = 0.0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude,
                               longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude,
                               longitude: points[i].longitude)
            d += a.distance(from: b)
        }
        return d
    }

    /// 预计总时间（秒），速度为 0 时返回 0
    var estimatedDuration: TimeInterval {
        let s = speedMetersPerSecond
        guard s > 0 else { return 0 }
        return totalDistance / s
    }
}

/// 路线模拟状态
enum RouteStatus {
    case stopped
    case running
    case paused
}

/// 路线进度信息
struct RouteProgress {
    /// 已行驶距离（米）
    let elapsedDistance: Double
    /// 总距离（米）
    let totalDistance: Double
    /// 当前速度（米/秒）
    let speed: Double
    /// 当前段索引（0..totalSegments-1）
    let segmentIndex: Int
    /// 总段数 = points.count - 1
    let totalSegments: Int
    /// 当前推进到的坐标（用于更新人物 Icon / 地图中心）
    let currentCoordinate: CLLocationCoordinate2D
    /// 进度比例 0..1
    var progress: Double {
        guard totalDistance > 0 else { return 0 }
        return min(1, elapsedDistance / totalDistance)
    }
    /// 预计剩余时间（秒）
    var remainingDuration: TimeInterval {
        let s = speed
        guard s > 0 else { return 0 }
        return max(0, totalDistance - elapsedDistance) / s
    }
}