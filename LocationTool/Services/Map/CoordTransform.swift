import CoreLocation
import Foundation

/// 坐标系转换工具
///
/// 中国大陆 Apple Maps 瓦片使用 GCJ-02（火星坐标系）显示，
/// 而 `MKMapView.convert(_:toCoordinateFrom:)` 返回的也是 GCJ-02 坐标。
/// 但 CLSimulationManager / locationd 接收的是 WGS-84 真实坐标。
/// 直接把 GCJ-02 坐标传给 CLSimulationManager 会导致蓝点偏移到错误位置。
///
/// 参考实现：Geranium/LocSim/CoordTransform.swift
struct CoordTransform {
    // MARK: - 大地测量常量

    /// Krasovsky 1940 椭球体长半轴（GCJ-02 使用）
    private static let krasovskySemiMajorAxis = 6378245.0
    /// WGS-84 椭球体偏心率平方
    private static let wgs84EccentricitySquared = 0.00669342162296594323

    /// GCJ-02 (火星坐标) -> WGS-84 (世界大地测量系统)
    ///
    /// 用于修正中国大陆地图坐标偏移。长按 MKMapView 得到 GCJ-02 坐标后，
    /// 必须用本方法转换成 WGS-84 才能传给 CLSimulationManager。
    static func gcj02ToWgs84(_ gcjCoordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isOutOfChina(gcjCoordinate) {
            return gcjCoordinate
        }
        return reverseGeocode(gcjCoordinate)
    }

    /// WGS-84 (世界大地测量系统) -> GCJ-02 (火星坐标)
    ///
    /// 用于把真实 GPS 坐标（WGS-84）转换成可在中国大陆地图上正确显示的 GCJ-02 坐标。
    static func wgs84ToGcj02(_ wgsCoordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isOutOfChina(wgsCoordinate) {
            return wgsCoordinate
        }
        return geocode(wgsCoordinate)
    }

    // MARK: - 核心转换逻辑

    /// 正向编码：把 WGS-84 坐标加上 GCJ-02 偏移
    private static func geocode(_ wgsCoordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var adjustedCoordinate = wgsCoordinate
        var latOffset = transformLatitude(
            x: wgsCoordinate.longitude - 105.0, y: wgsCoordinate.latitude - 35.0)
        var lonOffset = transformLongitude(
            x: wgsCoordinate.longitude - 105.0, y: wgsCoordinate.latitude - 35.0)
        let radLat = wgsCoordinate.latitude / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - wgs84EccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)
        latOffset =
            (latOffset * 180.0)
            / ((krasovskySemiMajorAxis * (1 - wgs84EccentricitySquared)) / (magic * sqrtMagic)
                * Double.pi)
        lonOffset =
            (lonOffset * 180.0) / (krasovskySemiMajorAxis / sqrtMagic * cos(radLat) * Double.pi)
        adjustedCoordinate.latitude += latOffset
        adjustedCoordinate.longitude += lonOffset
        return adjustedCoordinate
    }

    /// 逆向编码：通过迭代近似从 GCJ-02 坐标去除偏移得到 WGS-84
    private static func reverseGeocode(_ gcjCoordinate: CLLocationCoordinate2D)
        -> CLLocationCoordinate2D
    {
        let initialPoint = gcjCoordinate
        let geocodedPoint = geocode(initialPoint)
        let latOffset = geocodedPoint.latitude - initialPoint.latitude
        let lonOffset = geocodedPoint.longitude - initialPoint.longitude
        return CLLocationCoordinate2D(
            latitude: initialPoint.latitude - latOffset,
            longitude: initialPoint.longitude - lonOffset
        )
    }

    /// 判断坐标是否在中国大陆之外（境外无需偏移）
    private static func isOutOfChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return coordinate.longitude < 72.004 || coordinate.longitude > 137.847
            || coordinate.latitude < 0.8293 || coordinate.latitude > 55.8271
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var lat = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        lat += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        lat += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        lat += (160.0 * sin(y / 12.0 * Double.pi) + 320 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return lat
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var lon = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        lon += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        lon += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        lon += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return lon
    }
}