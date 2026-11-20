import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    /// 播放器全屏时放开横屏，其余锁竖屏
    var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = makeRoot()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        orientationMask
    }

    private func makeRoot() -> UIViewController {
        if AppConfig.isLoggedIn {
            return UINavigationController(rootViewController: HomeViewController())
        }
        return UINavigationController(rootViewController: LoginViewController())
    }

    func switchToHome() {
        let nav = UINavigationController(rootViewController: HomeViewController())
        window?.rootViewController = nav
        if let w = window {
            UIView.transition(with: w, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
        }
    }

    func switchToLogin() {
        let nav = UINavigationController(rootViewController: LoginViewController())
        window?.rootViewController = nav
    }
}
