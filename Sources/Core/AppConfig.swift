import Foundation

enum AppConfig {
    // 运行时可改，存 UserDefaults
    static let defaults = UserDefaults.standard

    private enum Key {
        static let serverURL = "alist.serverURL"
        static let coursePath = "alist.coursePath"
        static let transcodeHost = "alist.transcodeHost"
        static let token = "alist.token"
        static let username = "alist.username"
        static let password = "alist.password"
    }

    static var serverURL: String {
        get { defaults.string(forKey: Key.serverURL) ?? "http://192.168.88.88:5244" }
        set { defaults.set(newValue, forKey: Key.serverURL) }
    }
    static var coursePath: String {
        get { defaults.string(forKey: Key.coursePath) ?? "飞牛NAS" }
        set { defaults.set(newValue, forKey: Key.coursePath) }
    }
    static var transcodeHost: String {
        get { defaults.string(forKey: Key.transcodeHost) ?? "http://192.168.88.88:6090" }
        set { defaults.set(newValue, forKey: Key.transcodeHost) }
    }
    static var token: String {
        get { defaults.string(forKey: Key.token) ?? "" }
        set { defaults.set(newValue, forKey: Key.token) }
    }
    static var username: String {
        get { defaults.string(forKey: Key.username) ?? "" }
        set { defaults.set(newValue, forKey: Key.username) }
    }
    static var password: String {
        get { defaults.string(forKey: Key.password) ?? "" }
        set { defaults.set(newValue, forKey: Key.password) }
    }
    static var isLoggedIn: Bool { !token.isEmpty }

    static func logout() {
        defaults.removeObject(forKey: Key.token)
    }

    // 每门课根目录的状态文件
    static let stateFileName = ".course_state.json"
    // 本地缓存目录（Documents/.cache）
    static var cacheDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(".cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
