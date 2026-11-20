import Foundation

// MARK: - Alist 文件
struct AlistFile: Codable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int64
    let modified: String?
    let sign: String?
    let rawURL: String?

    enum CodingKeys: String, CodingKey {
        case name, path, size, modified, sign
        case isDir = "is_dir"
        case rawURL = "raw_url"
    }

    var isVideo: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "m3u8", "flv", "mov", "mkv", "avi", "ts", "webm"].contains(ext)
    }
    var displayName: String { name }
}

// MARK: - 学习状态
enum StudyStatus: String, Codable {
    case unseen
    case watching
    case done

    var label: String {
        switch self {
        case .unseen: return "未看"
        case .watching: return "在看"
        case .done: return "已看"
        }
    }
    var colorHex: String {
        switch self {
        case .unseen: return "#9AA0A6"
        case .watching: return "#1A73E8"
        case .done: return "#1E8E5A"
        }
    }
}

struct ChapterState: Codable {
    var status: StudyStatus = .unseen
    var position: Double = 0        // 上次播到（秒）
    var duration: Double = 0        // 总时长（秒）
    var planDate: String?           // yyyy-MM-dd 计划学习日期
    var updatedAt: Int64 = 0

    var percent: Int {
        if status == .done { return 100 }
        guard duration > 0 else { return 0 }
        return Int((position / duration * 100).rounded()).clamped(to: 0...99)
    }
    var timeText: String {
        guard duration > 0 else { return "--" }
        return "\(Self.fmt(position)) / \(Self.fmt(duration))"
    }
    static func fmt(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - 一门课的状态
struct CourseState: Codable {
    var version: Int = 1
    var course: String
    var updatedAt: Int64 = 0
    var chapters: [String: ChapterState] = [:]

    init(course: String) { self.course = course }

    func state(for path: String) -> ChapterState {
        chapters[path] ?? ChapterState()
    }

    mutating func setState(_ state: ChapterState, for path: String) {
        chapters[path] = state
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// 改名后迁移进度
    mutating func migrate(from old: String, to new: String) {
        guard let s = chapters.removeValue(forKey: old) else { return }
        chapters[new] = s
        updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
    }

    var total: Int { chapters.count }
    var doneCount: Int { chapters.values.filter { $0.status == .done }.count }
    var percent: Int { total == 0 ? 0 : Int((Double(doneCount) / Double(total) * 100).rounded()) }

    /// 最近看过（排除未看），按更新时间倒序
    var recent: [(path: String, state: ChapterState)] {
        chapters.filter { $0.value.status != .unseen }
            .map { (path: $0.key, state: $0.value) }
            .sorted { $0.state.updatedAt > $1.state.updatedAt }
    }

    /// 有计划日期的章节，按日期升序
    var planned: [(path: String, state: ChapterState)] {
        chapters.filter { $0.value.planDate != nil }
            .map { (path: $0.key, state: $0.value) }
            .sorted { ($0.state.planDate ?? "") < ($1.state.planDate ?? "") }
    }
}

// MARK: - 课程
struct Course {
    let name: String
    let path: String
    let modified: String?
}

// MARK: - 首页聚合项
struct PlayItem {
    let course: String
    let path: String
    let name: String
    let state: ChapterState
}
