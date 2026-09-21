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
///  - TrollStore 平台级 entitlement（platform-application / no-sandbox 等）
///
/// 关键实现细节（参考 Geranium LocSimManager.swift）：
///  1. `CLSimulationManager` 必须是进程级单例（static let），否则会被 ARC 释放导致模拟立即停止
///  2. 调用完 `startLocationSimulation` / `stopLocationSimulation` 后，
///     必须发送 `AutomaticTimeZoneUpdateNeeded` Darwin 通知唤醒 locationd，否则修改不生效
///  3. 调用顺序：stop → clear → append(location) → flush → start → postDarwinNotification
///
/// 若设备 iOS 17.1+ 漏洞被修复导致私有 API 不可用，调用会静默失败，
/// 不影响 UI 与路线推进（RouteManager 仍会按 onProgress 推进位置）。
final class SystemLocationBackend: NSObject, LocationBackend {
    private(set) var status: SimulationStatus = .stopped
    private(set) var simulatedPoint: LocationPoint?
    var onStatusChange: ((SimulationStatus, LocationPoint?) -> Void)?

    /// CLSimulationManager 进程级单例
    /// 重要：必须是 static let，否则 ARC 会在 applySimulatedLocation 返回后释放实例，
    /// 导致 locationd 立即停止模拟（这是 Geranium 等工具的关键差异点）
    private static let simulationManager: NSObject? = {
        guard let cls = NSClassFromString("CLSimulationManager") as? NSObject.Type else {
            return nil
        }
        return cls.init()
    }()

    // CLSimulationManager 方法选择器
    private let stopSel = NSSelectorFromString("stopLocationSimulation")
    private let clearSel = NSSelectorFromString("clearSimulatedLocations")
    private let appendSel = NSSelectorFromString("appendSimulatedLocation:")
    private let flushSel = NSSelectorFromString("flush")
    private let startSel = NSSelectorFromString("startLocationSimulation")

    /// 唤醒 locationd 的 Darwin 通知名（Geranium 同款方案）
    private let darwinNotificationName = "AutomaticTimeZoneUpdateNeeded" as CFString

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

    private func applySimulatedLocation(_ point: LocationPoint) {
        guard let manager = Self.simulationManager else { return }
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
        // 发送 Darwin 通知唤醒 locationd（关键：不发送则系统不会刷新定位）
        postDarwinNotification()
    }

    private func clearSimulatedLocation() {
        guard let manager = Self.simulationManager else { return }
        if manager.responds(to: stopSel) {
            _ = manager.perform(stopSel)
        }
        if manager.responds(to: clearSel) {
            _ = manager.perform(clearSel)
        }
        if manager.responds(to: flushSel) {
            _ = manager.perform(flushSel)
        }
        // 同样需要唤醒 locationd 清除状态
        postDarwinNotification()
    }

    /// 发送 Darwin 通知，立即唤醒 locationd 重新读取模拟位置
    /// 参考：Geranium/LocSim/LocSimManager.swift 的 post_required_timezone_update()
    private func postDarwinNotification() {
        CFNotificationCenterPostNotificationWithOptions(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName),
            nil, nil, kCFNotificationDeliverImmediately
        )
    }
}
