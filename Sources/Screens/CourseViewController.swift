import UIKit

/// 课程详情页：章节三态（未看/在看/已看）、进度、计划日期、点播。
/// 三态设计参考 KSPlayer Demo 的 PlayModel（current/duration/isFavorite）+ 主流慕课 App。
final class CourseViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let course: Course
    private let initialPath: String?
    private let table = UITableView(frame: .zero, style: .plain)
    private var files: [AlistFile] = []
    private var videoFiles: [AlistFile] = []
    private var state: CourseState = CourseState(course: "")
    private let store = StudyStore.shared
    private let progressHeader = UIView()
    private let progressLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)

    /// 三态筛选：nil=全部
    private var filter: StudyStatus?

    init(course: Course, initialPath: String? = nil) {
        self.course = course
        self.initialPath = initialPath
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = course.name
        view.backgroundColor = .systemBackground

        // 三态筛选切换
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "筛选", style: .plain, target: self, action: #selector(onFilter))

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.tableHeaderView = progressHeader
        view.addSubview(table)
        table.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupHeader()
        Task { await load() }
    }

    private func setupHeader() {
        progressHeader.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 64)
        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressBar.trackTintColor = .systemGray5
        progressBar.tintColor = .systemGreen
        progressHeader.addSubview(progressLabel)
        progressHeader.addSubview(progressBar)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressLabel.leadingAnchor.constraint(equalTo: progressHeader.leadingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(equalTo: progressHeader.trailingAnchor, constant: -16),
            progressLabel.topAnchor.constraint(equalTo: progressHeader.topAnchor, constant: 12),
            progressBar.leadingAnchor.constraint(equalTo: progressHeader.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: progressHeader.trailingAnchor, constant: -16),
            progressBar.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 10),
        ])
    }

    private func load() async {
        state = await store.load(course: course.name)
        do {
            let list = try await AlistService.shared.list(course.path)
            await MainActor.run {
                self.videoFiles = list.filter { $0.isVideo }
                self.updateHeader()
                self.table.reloadData()
                self.openInitialIfNeeded()
            }
        } catch {
            await MainActor.run { self.showAlert("加载失败", error.localizedDescription) }
        }
    }

    private func updateHeader() {
        let total = videoFiles.count
        let done = videoFiles.filter { state.state(for: $0.path).status == .done }.count
        let pct = total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded())
        progressLabel.text = "总体进度  \(done)/\(total) 节已看 · \(pct)%"
        progressBar.progress = Float(pct) / 100
        title = filter == nil ? course.name : "\(course.name) · \(filter!.label)"
    }

    private func openInitialIfNeeded() {
        guard let p = initialPath, let idx = videoFiles.firstIndex(where: { $0.path == p }) else { return }
        presentPlayer(at: idx)
    }

    private var visibleFiles: [AlistFile] {
        guard let f = filter else { return videoFiles }
        return videoFiles.filter { state.state(for: $0.path).status == f }
    }

    // MARK: - Table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleFiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let f = visibleFiles[indexPath.row]
        let st = state.state(for: f.path)
        cell.textLabel?.text = f.displayName
        cell.textLabel?.font = .systemFont(ofSize: 14)

        let icon = st.status == .done ? "checkmark.circle.fill"
                  : (st.status == .watching ? "play.circle.fill" : "circle")
        let color: UIColor = st.status == .done ? .systemGreen
                           : (st.status == .watching ? .systemBlue : .systemGray3)
        cell.imageView?.image = UIImage(systemName: icon)
        cell.imageView?.tintColor = color

        var detail = st.status.label
        if st.duration > 0 { detail += " · \(st.timeText)" }
        if let plan = st.planDate { detail += " · 计划 \(plan)" }
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let realIdx = videoFiles.firstIndex(where: { $0.path == visibleFiles[indexPath.row].path }) else { return }
        presentPlayer(at: realIdx)
    }

    /// 左滑：标记已看/未看、计划日期、改名
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let f = visibleFiles[indexPath.row]
        let st = state.state(for: f.path)

        let toggle = UIContextualAction(style: .normal, title: st.status == .done ? "标未看" : "标已看") { [weak self] _, _, done in
            guard let self else { return }
            var s = self.state.state(for: f.path)
            if s.status == .done {
                s.status = .unseen
                s.position = 0
            } else {
                s.status = .done
                s.position = s.duration
            }
            s.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            self.store.update(course: self.course.name, path: f.path, state: s)
            self.state = self.store.get(course: self.course.name)
            self.updateHeader()
            self.table.reloadData()
            Task { await self.store.flush(course: self.course.name) }
            done(true)
        }
        toggle.backgroundColor = .systemGreen

        let plan = UIContextualAction(style: .normal, title: "计划") { [weak self] _, _, done in
            self?.showPlanPicker(file: f)
            done(true)
        }
        plan.backgroundColor = .systemOrange

        let rename = UIContextualAction(style: .normal, title: "改名") { [weak self] _, _, done in
            self?.toggleName(file: f)
            done(true)
        }
        rename.backgroundColor = .systemBlue

        return UISwipeActionsConfiguration(actions: [toggle, plan, rename])
    }

    private func showPlanPicker(file: AlistFile) {
        let ac = UIAlertController(title: "设置计划学习日期", message: nil, preferredStyle: .actionSheet)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let today = Date()
        for i in -1...7 {
            let d = Calendar.current.date(byAdding: .day, value: i, to: today)!
            let label = i == 0 ? "今天" : (i == -1 ? "昨天" : fmt.string(from: d))
            ac.addAction(UIAlertAction(title: "\(label)（\(fmt.string(from: d))）", style: .default) { [weak self] _ in
                guard let self else { return }
                var s = self.state.state(for: file.path)
                s.planDate = fmt.string(from: d)
                s.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
                self.store.update(course: self.course.name, path: file.path, state: s)
                self.state = self.store.get(course: self.course.name)
                self.table.reloadData()
                Task { await self.store.flush(course: self.course.name) }
            })
        }
        ac.addAction(UIAlertAction(title: "清除计划", style: .destructive) { [weak self] _ in
            guard let self else { return }
            var s = self.state.state(for: file.path)
            s.planDate = nil
            self.store.update(course: self.course.name, path: file.path, state: s)
            self.state = self.store.get(course: self.course.name)
            self.table.reloadData()
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        ac.popoverPresentationController?.sourceView = table
        ac.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.width/2, y: view.bounds.height/2, width: 1, height: 1)
        present(ac, animated: true)
    }

    private func toggleName(file: AlistFile) {
        let isDone = file.name.hasPrefix("✅")
        let newName = isDone
            ? file.name.replacingOccurrences(of: "^✅\\s*", with: "", options: .regularExpression)
            : "✅ " + file.name
        let dir = (file.path as NSString).deletingLastPathComponent
        let newPath = dir + "/" + newName
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AlistService.shared.rename(path: file.path, to: newName)
                var migrated = self.store.get(course: self.course.name)
                migrated.migrate(from: file.path, to: newPath)
                self.store.replaceAll(course: self.course.name, state: migrated)
                await MainActor.run {
                    if let idx = self.videoFiles.firstIndex(where: { $0.path == file.path }) {
                        self.videoFiles[idx] = AlistFile(name: newName, path: newPath, isDir: false,
                            size: file.size, modified: file.modified, sign: file.sign, rawURL: file.rawURL)
                    }
                    self.state = self.store.get(course: self.course.name)
                    self.table.reloadData()
                    self.toast(isDone ? "已取消标记" : "已标记看过")
                }
            } catch {
                await MainActor.run { self.toast("改名失败：\(error.localizedDescription)") }
            }
        }
    }

    @objc private func onFilter() {
        let ac = UIAlertController(title: "筛选章节", message: nil, preferredStyle: .actionSheet)
        ac.addAction(UIAlertAction(title: "全部", style: .default) { [weak self] _ in self?.applyFilter(nil) })
        for s in [StudyStatus.unseen, .watching, .done] {
            ac.addAction(UIAlertAction(title: s.label, style: .default) { [weak self] _ in self?.applyFilter(s) })
        }
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        ac.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(ac, animated: true)
    }

    private func applyFilter(_ f: StudyStatus?) {
        filter = f
        updateHeader()
        table.reloadData()
    }

    private func presentPlayer(at index: Int) {
        let vc = KSPlayerViewController(course: course.name, videos: videoFiles, index: index)
        vc.onStateChange = { [weak self] _, _, _, _ in
            guard let self else { return }
            self.state = self.store.get(course: self.course.name)
            self.updateHeader()
            self.table.reloadData()
        }
        present(vc, animated: true)
    }

    private func toast(_ msg: String) {
        let label = UILabel()
        label.text = msg
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.font = .systemFont(ofSize: 13)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.frame = CGRect(x: 0, y: 0, width: 220, height: 40)
        label.center = CGPoint(x: view.center.x, y: view.bounds.height - 120)
        view.addSubview(label)
        UIView.animate(withDuration: 0.2) { label.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.0) { label.alpha = 0 } completion: { _ in label.removeFromSuperview() }
        }
    }

    private func showAlert(_ title: String, _ msg: String) {
        let ac = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default))
        present(ac, animated: true)
    }
}
