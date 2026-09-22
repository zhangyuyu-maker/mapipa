import CoreLocation
import Foundation

/// 历史定位记录模型 (与服务器 JSON 字段一一对应)
/// 存储的是 GCJ-02 坐标 (地图显示坐标), 点击历史记录时可直接传给 mapService
struct LocationHistoryItem: Codable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let createdAt: String  // ISO 8601 格式

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// API 响应: 历史列表
struct LocationHistoryListResponse: Codable {
    let success: Bool
    let data: [LocationHistoryItem]
}

/// API 响应: 单条记录 (新增/更新返回)
struct LocationHistoryItemResponse: Codable {
    let success: Bool
    let data: LocationHistoryItem?
}
