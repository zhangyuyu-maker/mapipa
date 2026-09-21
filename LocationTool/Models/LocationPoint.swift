import CoreLocation
import Foundation

/// 位置点模型 —— 地图层与定位后端之间的唯一数据契约
/// 地图只负责产出 LocationPoint，真正的系统定位修改由 LocationBackend 负责
struct LocationPoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let name: String?
    let address: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double,
         longitude: Double,
         altitude: Double? = nil,
         name: String? = nil,
         address: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.name = name
        self.address = address
    }

    init(coordinate: CLLocationCoordinate2D,
         altitude: Double? = nil,
         name: String? = nil,
         address: String? = nil) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.altitude = altitude
        self.name = name
        self.address = address
    }
}

/// 搜索结果项
struct LocationSearchResult {
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D

    var point: LocationPoint {
        LocationPoint(latitude: coordinate.latitude,
                      longitude: coordinate.longitude,
                      name: name,
                      address: address)
    }
}

/// 逆地理编码结果
struct LocationAddress: Equatable {
    let name: String?
    let thoroughfare: String?      // 街道
    let locality: String?          // 城市
    let subLocality: String?       // 区
    let administrativeArea: String?// 省/州
    let country: String?
    let postalCode: String?

    /// 拼接后的完整地址
    var fullAddress: String {
        [administrativeArea, subLocality, locality, thoroughfare, postalCode]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
