import CoreLocation
import MapKit

/// 基于系统能力的地理编码实现：
/// - 地点搜索：MKLocalSearch（无需 API Key，全球覆盖）
/// - 逆地理编码：CLGeocoder
/// 全部使用 iOS 系统原生框架，不引入第三方地图 SDK
final class AppleGeocodingService: GeocodingService {
    private let geocoder = CLGeocoder()

    func search(keyword: String,
                region: CLCircularRegion?) async throws -> [LocationSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.resultTypes = [.pointOfInterest, .address]
        if let region = region {
            request.region = MKCoordinateRegion(center: region.center,
                                                latitudinalMeters: region.radius * 2,
                                                longitudinalMeters: region.radius * 2)
        }
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems.map { item in
            let placemark = item.placemark
            let address = [
                placemark.administrativeArea,
                placemark.locality,
                placemark.subLocality,
                placemark.thoroughfare,
                placemark.subThoroughfare
            ].compactMap { $0 }.joined(separator: " ")
            return LocationSearchResult(
                name: item.name ?? placemark.name ?? keyword,
                address: address.isEmpty ? nil : address,
                coordinate: placemark.coordinate
            )
        }
    }

    func reverseGeocode(latitude: Double,
                        longitude: Double) async throws -> LocationAddress {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let pm = placemarks.first else {
            throw GeocodingError.noResult
        }
        return LocationAddress(
            name: pm.name,
            thoroughfare: pm.thoroughfare,
            locality: pm.locality,
            subLocality: pm.subLocality,
            administrativeArea: pm.administrativeArea,
            country: pm.country,
            postalCode: pm.postalCode
        )
    }
}

enum GeocodingError: Error, LocalizedError {
    case noResult
    var errorDescription: String? { "未找到对应的地点信息" }
}
