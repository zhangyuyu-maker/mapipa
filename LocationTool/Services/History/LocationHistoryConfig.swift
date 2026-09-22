import Foundation

/// 历史定位 API 配置
/// 修改 apiBaseURL 即可切换服务器地址 (开发/生产环境)
enum LocationHistoryConfig {
    /// API 基础地址
    /// - 开发环境: http://localhost:3000
    /// - 生产环境: 改为服务器地址, 例如 http://your-server.com:3000
    /// 所有历史记录请求都通过此地址, 方便以后更换服务器
    static let apiBaseURL = "http://120.48.137.4:8005"
}
