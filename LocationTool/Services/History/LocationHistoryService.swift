import Foundation

/// 历史定位 API 客户端
/// 负责与 Node.js 后端通信: 增删查历史定位记录
///
/// 设计原则:
/// - 网络错误不影响地图定位和模拟功能, 只在 completion 中返回 Result
/// - 所有请求异步执行, 回调默认在后台线程, UI 更新需自行切主线程
final class LocationHistoryService {
    static let shared = LocationHistoryService()

    private let baseURL: String
    private let session: URLSession

    private init() {
        self.baseURL = LocationHistoryConfig.apiBaseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - GET /api/location-history
    /// 获取历史定位列表 (服务器按 createdAt DESC 排序, 并自动清理超过 5 天的记录)
    func fetchAll(completion: @escaping (Result<[LocationHistoryItem], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/location-history") else {
            completion(.failure(LocationHistoryError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(LocationHistoryError.noData))
                return
            }
            do {
                let resp = try JSONDecoder().decode(LocationHistoryListResponse.self, from: data)
                if resp.success {
                    completion(.success(resp.data))
                } else {
                    completion(.failure(LocationHistoryError.apiError("获取历史记录失败")))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - POST /api/location-history
    /// 新增历史定位 (服务器自动去重: name+lat+lng 相同则只更新 createdAt)
    /// - Parameters:
    ///   - name: 地点名称
    ///   - latitude: 纬度 (GCJ-02)
    ///   - longitude: 经度 (GCJ-02)
    ///   - completion: 可选回调, 保存失败时返回错误
    func save(name: String,
              latitude: Double,
              longitude: Double,
              completion: ((Result<Bool, Error>) -> Void)? = nil) {
        guard let url = URL(string: "\(baseURL)/api/location-history") else {
            completion?(.failure(LocationHistoryError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "latitude": latitude,
            "longitude": longitude
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion?(.failure(error))
            return
        }
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            completion?(.success(true))
        }
        task.resume()
    }

    // MARK: - DELETE /api/location-history/:id
    /// 删除指定历史定位
    func delete(id: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/location-history/\(id)") else {
            completion(.failure(LocationHistoryError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion?(.success(true))
        }
        task.resume()
    }
}

/// 历史记录 API 错误
enum LocationHistoryError: Error, LocalizedError {
    case invalidURL
    case noData
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "API 地址无效"
        case .noData: return "服务器未返回数据"
        case .apiError(let msg): return msg
        }
    }
}
