import CoreLocation
import Foundation

/// 地理编码 / 地点搜索统一接口
/// UI 层只依赖此协议，不依赖具体地图厂商，方便后续更换 Provider
protocol GeocodingService {
    /// 地点搜索（关键词 -> 结果列表）
    func search(keyword: String,
                region: CLCircularRegion?) async throws -> [LocationSearchResult]

    /// 逆地理编码（经纬度 -> 地址）
    func reverseGeocode(latitude: Double,
                        longitude: Double) async throws -> LocationAddress
}
