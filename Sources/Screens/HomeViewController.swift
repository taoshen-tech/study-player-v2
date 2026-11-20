import UIKit

/// 首页：最近计划 / 继续学习 / 全部课程
final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private enum Section { case planned, recent, courses }
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var courses: [Course] = []
    private var allStates: [String: CourseState] = [:]
    private var sections: [Section] = []
    private let store = StudyStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "刷题课堂"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "设置", style: .plain, target: self, action: #selector(onSettings))

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(table)
        table.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(loadData), for: .valueChanged)
        table.refreshControl = refresh
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if courses.isEmpty { loadData() } else { rebuildSections() }
    }

    @objc private func loadData() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let root = "/\(AppConfig.coursePath)"
                let files = try await AlistService.shared.list(root)
                let dirs = files.filter { $0.isDir }.map { Course(name: $0.name, path: $0.path, modified: $0.modified) }
                var states: [String: CourseState] = [:]
                for c in dirs {
                    states[c.name] = await self.store.load(course: c.name)
                }
                await MainActor.run {
                    self.courses = dirs
                    self.allStates = states
                    self.rebuildSections()
                    self.table.refreshControl?.endRefreshing()
                    self.table.reloadData()
                }
            } catch {
                await MainActor.run {
                    self.table.refreshControl?.endRefreshing()
                    let ac = UIAlertController(title: "加载失败", message: error.localizedDescription, preferredStyle: .alert)
                    ac.addAction(UIAlertAction(title: "好", style: .default))
                    self.present(ac, animated: true)
                }
            }
        }
    }

    private func rebuildSections() {
        var s: [Section] = []
        if hasPlanned() { s.append(.planned) }
        if hasRecent() { s.append(.recent) }
        s.append(.courses)
        sections = s
    }

    private func hasPlanned() -> Bool { allStates.values.contains { !$0.planned.isEmpty } }
    private func hasRecent() -> Bool { allStates.values.contains { !$0.recent.isEmpty } }

    // MARK: - Table
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sections[section] {
        case .planned: return "最近计划"
        case .recent: return "继续学习"
        case .courses: return "全部课程"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .planned: return allStates.values.reduce(0) { $0 + $1.planned.count }
        case .recent: return min(allStates.values.reduce(0) { $0 + $1.recent.count }, 10)
        case .courses: return courses.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        switch sections[indexPath.section] {
        case .courses:
            let c = courses[indexPath.row]
            let st = allStates[c.name] ?? CourseState(course: c.name)
            cell.textLabel?.text = c.name
            cell.detailTextLabel?.text = "已看 \(st.doneCount)/\(st.total) · \(st.percent)%"
            cell.imageView?.image = UIImage(systemName: "folder.fill")
            cell.imageView?.tintColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
        case .recent:
            let items = allRecent().prefix(10)
            let item = Array(items)[indexPath.row]
            cell.textLabel?.text = item.path.split(separator: "/").last.map(String.init)
            cell.detailTextLabel?.text = "\(item.course) · \(item.state.timeText) · \(item.state.percent)%"
            cell.imageView?.image = UIImage(systemName: "play.circle.fill")
            cell.imageView?.tintColor = item.state.status == .done ? .systemGreen : .systemBlue
            cell.accessoryType = .disclosureIndicator
        case .planned:
            let items = allPlanned()
            let item = items[indexPath.row]
            cell.textLabel?.text = item.path.split(separator: "/").last.map(String.init)
            cell.detailTextLabel?.text = "\(item.state.planDate ?? "") · \(item.course) · \(item.state.status.label)"
            cell.imageView?.image = UIImage(systemName: item.state.status == .done ? "checkmark.circle.fill" : "calendar")
            cell.imageView?.tintColor = item.state.status == .done ? .systemGreen : .systemOrange
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section] {
        case .courses:
            let c = courses[indexPath.row]
            let vc = CourseViewController(course: c)
            navigationController?.pushViewController(vc, animated: true)
        case .recent, .planned:
            let item = sections[indexPath.section] == .recent
                ? Array(allRecent().prefix(10))[indexPath.row]
                : allPlanned()[indexPath.row]
            openAndPlay(item)
        }
    }

    /// 首页卡片直接进入课程并定位播放该文件
    private func openAndPlay(_ item: PlayItem) {
        guard let course = courses.first(where: { $0.name == item.course }) else { return }
        let vc = CourseViewController(course: course, initialPath: item.path)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func allRecent() -> [PlayItem] {
        var result: [PlayItem] = []
        for (course, st) in allStates {
            for r in st.recent {
                result.append(PlayItem(course: course, path: r.path, name: r.path.split(separator: "/").last.map(String.init) ?? "", state: r.state))
            }
        }
        return result.sorted { $0.state.updatedAt > $1.state.updatedAt }
    }

    private func allPlanned() -> [PlayItem] {
        var result: [PlayItem] = []
        for (course, st) in allStates {
            for p in st.planned {
                result.append(PlayItem(course: course, path: p.path, name: p.path.split(separator: "/").last.map(String.init) ?? "", state: p.state))
            }
        }
        return result.sorted { ($0.state.planDate ?? "") < ($1.state.planDate ?? "") }
    }

    @objc private func onSettings() {
        let ac = UIAlertController(title: "设置", message: nil, preferredStyle: .actionSheet)
        ac.addAction(UIAlertAction(title: "切换账号", style: .default) { [weak self] _ in
            AppConfig.logout()
            (UIApplication.shared.delegate as? AppDelegate)?.switchToLogin()
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        ac.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(ac, animated: true)
    }
}
