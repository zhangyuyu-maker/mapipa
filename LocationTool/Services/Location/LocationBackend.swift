import CoreLocation
import Foundation

/// 模拟定位状态
enum SimulationStatus {
    case stopped
    case running
}

/// 系统级定位模拟后端
/// 职责：接收 LocationPoint，调用系统能力修改设备定位
/// 与地图层完全解耦——地图只负责选点，本类负责真正改定位
protocol LocationBackend: AnyObject {
    var status: SimulationStatus { get }
    var simulatedPoint: LocationPoint? { get }
    var onStatusChange: ((SimulationStatus, LocationPoint?) -> Void)? { get set }

    func startSimulation(at point: LocationPoint)
    func stopSimulation()
}

/// 基于系统能力的定位模拟后端
/// 通过 CLLocationManager 的私有 simulateLocation 接口注入系统级模拟定位，
/// 需要 com.apple.developer.location.simulated entitlement（TrollStore 可直接签名写入）。
/// 注入逻辑全部集中在此处，地图/搜索层无需感知。
final class SystemLocationBackend: NSObject, LocationBackend {
    private(set) var status: SimulationStatus = .stopped
    private(set) var simulatedPoint: LocationPoint?
    var onStatusChange: ((SimulationStatus, LocationPoint?) -> Void)?

    private let manager = CLLocationManager()
    private let simulateSel = NSSelectorFromString("_simulateLocation:")
    private let stopSimulateSel = NSSelectorFromString("_stopSimulatingLocation")

    func startSimulation(at point: LocationPoint) {
        simulatedPoint = point
        status = .running
        onStatusChange?(status, point)
        applySimulatedLocation(point)
    }

    func stopSimulation() {
        simulatedPoint = nil
        status = .stopped
        onStatusChange?(status, nil)
        clearSimulatedLocation()
    }

    // MARK: - 系统级定位注入

    private func applySimulatedLocation(_ point: LocationPoint) {
        let location = CLLocation(coordinate: point.coordinate,
                                  altitude: point.altitude ?? 0,
                                  horizontalAccuracy: 5,
                                  verticalAccuracy: 5,
                                  timestamp: Date())
        if manager.responds(to: simulateSel) {
            _ = manager.perform(simulateSel, with: location)
        }
    }

    private func clearSimulatedLocation() {
        if manager.responds(to: stopSimulateSel) {
            _ = manager.perform(stopSimulateSel)
        }
    }
}
