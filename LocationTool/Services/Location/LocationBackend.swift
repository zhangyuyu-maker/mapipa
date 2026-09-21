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
///
/// 实现方式：调用 CoreLocation 私有类 `CLSimulationManager`
/// （与 TrollStore 上主流工具 Geranium / AppDump3 等同款方案）
/// 需要 entitlement：
///  - com.apple.locationd.simulation  (CLSimulationManager 调用权限)
///  - com.apple.developer.location.simulated  (CLLocationManager 私有 API 调用权限)
///
/// 注入逻辑全部集中在此处，地图/搜索层无需感知。
/// 若设备 iOS 17.1+ 漏洞被修复导致私有 API 不可用，调用会静默失败，
/// 不影响 UI 与路线推进（RouteManager 仍会按 onProgress 推进位置）。
final class SystemLocationBackend: NSObject, LocationBackend {
    private(set) var status: SimulationStatus = .stopped
    private(set) var simulatedPoint: LocationPoint?
    var onStatusChange: ((SimulationStatus, LocationPoint?) -> Void)?

    // CLSimulationManager 私有类实例（懒加载，所有调用复用同一实例）
    private var simulationManager: NSObject?

    // CLSimulationManager 方法选择器
    private let stopSel = NSSelectorFromString("stopLocationSimulation")
    private let clearSel = NSSelectorFromString("clearSimulatedLocations")
    private let appendSel = NSSelectorFromString("appendSimulatedLocation:")
    private let flushSel = NSSelectorFromString("flush")
    private let startSel = NSSelectorFromString("startLocationSimulation")

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

    // MARK: - 系统级定位注入（CLSimulationManager 私有 API）

    /// 懒加载 CLSimulationManager 实例
    private func resolveSimulationManager() -> NSObject? {
        if let m = simulationManager { return m }
        guard let cls = NSClassFromString("CLSimulationManager") as? NSObject.Type else {
            return nil
        }
        let m = cls.init()
        simulationManager = m
        return m
    }

    private func applySimulatedLocation(_ point: LocationPoint) {
        guard let manager = resolveSimulationManager() else { return }
        let location = CLLocation(coordinate: point.coordinate,
                                  altitude: point.altitude ?? 0,
                                  horizontalAccuracy: 5,
                                  verticalAccuracy: 5,
                                  timestamp: Date())
        // 先停止之前的模拟并清空队列
        if manager.responds(to: stopSel) {
            _ = manager.perform(stopSel)
        }
        if manager.responds(to: clearSel) {
            _ = manager.perform(clearSel)
        }
        // 添加新位置
        if manager.responds(to: appendSel) {
            _ = manager.perform(appendSel, with: location)
        }
        // flush 后启动
        if manager.responds(to: flushSel) {
            _ = manager.perform(flushSel)
        }
        if manager.responds(to: startSel) {
            _ = manager.perform(startSel)
        }
    }

    private func clearSimulatedLocation() {
        guard let manager = simulationManager else { return }
        if manager.responds(to: stopSel) {
            _ = manager.perform(stopSel)
        }
        if manager.responds(to: clearSel) {
            _ = manager.perform(clearSel)
        }
        if manager.responds(to: flushSel) {
            _ = manager.perform(flushSel)
        }
    }
}