import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // 依赖注入：地图 Provider、地理编码 Provider、定位后端
        let mapService = AppleMapService()
        let geocoding = AppleGeocodingService()
        let backend = SystemLocationBackend()

        let viewController = MapViewController(mapService: mapService,
                                               geocoding: geocoding,
                                               backend: backend)
        let navigation = UINavigationController(rootViewController: viewController)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigation
        self.window = window
        window.makeKeyAndVisible()
    }
}
