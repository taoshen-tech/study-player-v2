import Foundation

/// Alist API 封装（async/await）
final class AlistService {
    static let shared = AlistService()
    private init() {}

    private var base: String { AppConfig.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression) }
    private var token: String { AppConfig.token }

    private func url(_ path: String) -> URL { URL(string: base + path)! }

    private func authHeaders() -> [String: String] {
        ["Content-Type": "application/json", "Authorization": token]
    }

    // MARK: 登录
    func login(username: String, password: String) async throws -> String {
        var req = URLRequest(url: url("/api/auth/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONDecoder().decode(ApiResponse<LoginData>.self, from: data)
        guard body.code == 200, let t = body.data?.token else {
            throw NSError(domain: "Alist", code: body.code, userInfo: [NSLocalizedDescriptionKey: body.message ?? "登录失败"])
        }
        return t
    }

    // MARK: 列目录
    func list(_ path: String) async throws -> [AlistFile] {
        var req = URLRequest(url: url("/api/fs/list"))
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "password": ""])
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONDecoder().decode(ApiResponse<ListData>.self, from: data)
        guard body.code == 200 else {
            throw NSError(domain: "Alist", code: body.code, userInfo: [NSLocalizedDescriptionKey: body.message ?? "列目录失败"])
        }
        let files = body.data?.content ?? []
        return files.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: 文件信息
    func info(_ path: String) async throws -> AlistFile? {
        var req = URLRequest(url: url("/api/fs/get"))
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "password": ""])
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONDecoder().decode(ApiResponse<AlistFile>.self, from: data)
        guard body.code == 200 else { return nil }
        return body.data
    }

    // MARK: 读文本
    func readText(_ path: String) async -> String? {
        do {
            guard let f = try await info(path), let raw = f.rawURL, !raw.isEmpty else { return nil }
            let fixed = fixRawURL(raw)
            var req = URLRequest(url: URL(string: fixed)!)
            req.setValue(token, forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    // MARK: 写文本（原子写：先写临时文件，再 rename 覆盖）
    func writeText(_ path: String, content: String) async throws {
        let tmp = path + ".tmp"
        try await putRaw(tmp, content: content)
        // Alist rename：把 tmp 改成目标名（覆盖）
        var req = URLRequest(url: url("/api/fs/rename"))
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": tmp, "name": (path as NSString).lastPathComponent])
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONDecoder().decode(ApiResponse<EmptyData>.self, from: data)
        guard body.code == 200 else {
            throw NSError(domain: "Alist", code: body.code, userInfo: [NSLocalizedDescriptionKey: body.message ?? "写入失败"])
        }
    }

    private func putRaw(_ path: String, content: String) async throws {
        var req = URLRequest(url: url("/api/fs/put"))
        req.httpMethod = "PUT"
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), forHTTPHeaderField: "File-Path")
        req.setValue("false", forHTTPHeaderField: "As-Task")
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = content.data(using: .utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Alist", code: -1, userInfo: [NSLocalizedDescriptionKey: "写入临时文件失败"])
        }
    }

    // MARK: 播放地址
    func videoURL(path: String, fileName: String) async -> String {
        if fileName.lowercased().hasSuffix(".flv") {
            let host = AppConfig.transcodeHost.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
            return host + "/play?path=" + path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        }
        guard let f = try? await info(path), let raw = f.rawURL else { return "" }
        return fixRawURL(raw)
    }

    private func fixRawURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "127.0.0.1", with: URL(string: base)?.host ?? "127.0.0.1")
    }

    /// 生成播放地址（不转码）：FLV/MKV/MP4 一律交给 KSPlayer 的 FFmpeg 内核直接播。
    /// 只处理 Alist 返回的 raw_url 里 127.0.0.1 的问题。
    func videoURLDirect(path: String) async -> String {
        guard let f = try? await info(path), let raw = f.rawURL, !raw.isEmpty else {
            // 兜底：拼 Alist 的 /d 下载直链
            return base + "/d" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        }
        return fixRawURL(raw)
    }

    // MARK: 改名（标记已看前缀）
    func rename(path: String, to newName: String) async throws {
        var req = URLRequest(url: url("/api/fs/rename"))
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = authHeaders()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "name": newName])
        let (data, _) = try await URLSession.shared.data(for: req)
        let body = try JSONDecoder().decode(ApiResponse<EmptyData>.self, from: data)
        guard body.code == 200 else {
            throw NSError(domain: "Alist", code: body.code, userInfo: [NSLocalizedDescriptionKey: body.message ?? "改名失败"])
        }
    }
}

// MARK: - 响应模型
struct ApiResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
}
struct LoginData: Decodable { let token: String }
struct ListData: Decodable { let content: [AlistFile]? }
struct EmptyData: Decodable {}
