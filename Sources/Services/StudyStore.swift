import Foundation

/// 学习状态仓库：内存 + 本地缓存 + Alist 云同步。
/// 按课程分文件，播放时只读写当前课程的 .course_state.json。
final class StudyStore {
    static let shared = StudyStore()
    private init() {}

    private var states: [String: CourseState] = [:]   // courseName -> state
    private let io = DispatchQueue(label: "study.store.io", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: 本地缓存路径
    private func localURL(_ course: String) -> URL {
        AppConfig.cacheDir.appendingPathComponent(course + ".json")
    }
    private func remotePath(_ course: String) -> String {
        "/\(AppConfig.coursePath)/\(course)/\(AppConfig.stateFileName)"
    }

    // MARK: 加载（先本地秒开，再后台拉云端）
    func load(course: String) async -> CourseState {
        if let s = states[course] { return s }
        var state = CourseState(course: course)
        if let data = try? Data(contentsOf: localURL(course)),
           let parsed = try? decoder.decode(CourseState.self, from: data) {
            state = parsed
        }
        states[course] = state

        // 后台同步云端
        Task {
            if let text = await AlistService.shared.readText(remotePath(course)),
               let data = text.data(using: .utf8),
               let remote = try? decoder.decode(CourseState.self, from: data),
               remote.updatedAt >= state.updatedAt {
                await MainActor.run {
                    self.states[course] = remote
                    self.saveLocal(remote, course: course)
                }
            }
        }
        return state
    }

    func get(course: String) -> CourseState {
        states[course] ?? CourseState(course: course)
    }

    /// 整体替换（用于路径迁移等批量改动）
    func replaceAll(course: String, state: CourseState) {
        var s = state
        s.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        states[course] = s
        saveLocal(s, course: course)
        scheduleCloudSync(course: course, state: s)
    }

    // MARK: 更新单章状态（实时写本地，节流写云）
    func update(course: String, path: String, state: ChapterState) {
        var s = get(course: course)
        s.setState(state, for: path)
        states[course] = s
        saveLocal(s, course: course)
        scheduleCloudSync(course: course, state: s)
    }

    /// 批量更新（播放退出时的最终同步）
    func flush(course: String) async {
        guard let s = states[course] else { return }
        await syncCloud(course: course, state: s)
    }

    private func saveLocal(_ state: CourseState, course: String) {
        io.async {
            guard let data = try? self.encoder.encode(state) else { return }
            try? data.write(to: self.localURL(course), options: .atomic)
        }
    }

    // 节流：5 秒内的多次更新合并成一次云写入
    private var pendingTimer: Timer?
    private var pendingCourse: String?
    private func scheduleCloudSync(course: String, state: CourseState) {
        DispatchQueue.main.async {
            self.pendingCourse = course
            self.pendingTimer?.invalidate()
            self.pendingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                guard let self, let c = self.pendingCourse, let s = self.states[c] else { return }
                Task { await self.syncCloud(course: c, state: s) }
            }
        }
    }

    private func syncCloud(course: String, state: CourseState) async {
        guard let data = try? encoder.encode(state),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await AlistService.shared.writeText(remotePath(course), content: text)
    }
}
