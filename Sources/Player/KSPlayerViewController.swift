import UIKit
import AVFoundation
import MediaPlayer
import KSPlayer

/// 基于 KSPlayer 内核（自带 FFmpeg，FLV/MKV/MP4 全格式直接播，无需转码）
/// 自定义控制层：参考 KSPlayer 官方 panGestureBegan/Changed 分层，按刷题场景定制。
/// 手势：单击暂停/播放 / 双击左右±10s / 长按递进倍速(2-3-4x) /
///       左半屏竖滑亮度 / 右半屏竖滑音量 / 横滑拖进度 / 全屏 / 锁屏
final class KSPlayerViewController: UIViewController {

    // MARK: - 数据源
    private let videos: [AlistFile]
    private let courseName: String
    private var index: Int
    private let store = StudyStore.shared

    var onStateChange: ((_ path: String, _ pos: Double, _ duration: Double, _ finished: Bool) -> Void)?

    // MARK: - KSPlayer 内核
    private var playerLayer: KSPlayerLayer!
    private var playerView: UIView!

    // MARK: - 控件
    private let topBar = UIView()
    private let bottomBar = UIView()
    private let titleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let lockButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)
    private let currentLabel = UILabel()
    private let totalLabel = UILabel()
    private let slider = UISlider()
    private let speedButton = UIButton(type: .system)
    private let hud = PlayerHUD()
    private let volumeView = MPVolumeView(frame: .zero)

    private var controlsVisible = true
    private var isLocked = false
    private var hideTimer: Timer?
    private var currentDuration: Double = 0
    private var currentPosition: Double = 0
    private var didFinish = false

    // 长按递进倍速
    private var longPressTimer: Timer?
    private var speedLevel = 0
    private let speedSteps: [Float] = [2.0, 3.0, 4.0]

    private var originalBrightness: CGFloat = UIScreen.main.brightness

    init(course: String, videos: [AlistFile], index: Int) {
        self.courseName = course
        self.videos = videos
        self.index = index
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        playerLayer?.stop()
        UIScreen.main.brightness = originalBrightness
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // 关键：KSPlayer 会自动在 AVPlayer(系统) 与 KSMEPlayer(FFmpeg) 间切换
        // FLV/MKV 等系统不支持的格式自动走 FFmpeg 内核，无需任何转码
        KSOptions.secondPlayerType = KSMEPlayer.self

        volumeView.isHidden = true
        view.addSubview(volumeView)

        loadCurrent()
        buildUI()
        addGestures()
        view.layoutIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - 加载视频（FLV 直接播，不转码）
    private func loadCurrent() {
        guard videos.indices.contains(index) else { return }
        let file = videos[index]
        didFinish = false
        titleLabel.text = file.displayName

        // 恢复进度
        let st = store.get(course: courseName).state(for: file.path)
        Task { [weak self] in
            guard let self else { return }
            let urlStr = await AlistService.shared.videoURLDirect(path: file.path)
            guard let u = URL(string: urlStr) else { return }

            let options = KSOptions()
            if st.position > 0 { options.startPlayTime = st.position }

            let layer = KSPlayerLayer(url: u, options: options)
            layer.delegate = self
            self.playerLayer = layer

            let pv = layer.makeUIView()
            pv.translatesAutoresizingMaskIntoConstraints = false
            self.view.insertSubview(pv, at: 0)
            NSLayoutConstraint.activate([
                pv.topAnchor.constraint(equalTo: self.view.topAnchor),
                pv.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                pv.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                pv.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            ])
            self.playerView = pv
            layer.play()

            var watching = st
            watching.status = .watching
            self.store.update(course: self.courseName, path: file.path, state: watching)
        }
    }

    // MARK: - 手势
    private func addGestures() {
        let single = UITapGestureRecognizer(target: self, action: #selector(onSingleTap))
        let double = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        view.addGestureRecognizer(single)
        view.addGestureRecognizer(double)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress))
        longPress.minimumPressDuration = 0.4
        longPress.delegate = self
        view.addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func onSingleTap() {
        if isLocked { hud.show(text: "🔒 已锁定，点右上角解锁"); return }
        togglePlay()
        toggleControls()
    }

    @objc private func onDoubleTap(_ g: UITapGestureRecognizer) {
        if isLocked { return }
        let x = g.location(in: view).x
        let delta: Double = x < view.bounds.width / 2 ? -10 : 10
        seekBy(delta)
        hud.show(text: delta < 0 ? "⏪ 快退 10 秒" : "⏩ 快进 10 秒")
    }

    @objc private func onLongPress(_ g: UILongPressGestureRecognizer) {
        if isLocked { return }
        switch g.state {
        case .began:
            speedLevel = 0
            applySpeed()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                guard let self, self.speedLevel < self.speedSteps.count - 1 else { return }
                self.speedLevel += 1
                self.applySpeed()
            }
        case .ended, .cancelled, .failed:
            longPressTimer?.invalidate()
            longPressTimer = nil
            playerLayer?.player.playbackRate = 1.0
            hud.hide()
        default: break
        }
    }

    private func applySpeed() {
        let s = speedSteps[speedLevel]
        playerLayer?.player.playbackRate = s
        hud.show(text: "⏩ \(Int(s))x 快进")
    }

    private enum PanMode { case none, seek, brightness, volume }
    private var panMode: PanMode = .none
    private var panStart: CGPoint = .zero
    private var panStartBrightness: CGFloat = 0
    private var panStartVolume: Float = 0
    private var panStartTime: Double = 0

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        if isLocked { return }
        let p = g.location(in: view)
        switch g.state {
        case .began:
            // 滑动即取消长按倍速
            longPressTimer?.invalidate(); longPressTimer = nil
            playerLayer?.player.playbackRate = 1.0
            panStart = p
            panStartBrightness = UIScreen.main.brightness
            panStartVolume = currentVolume
            panStartTime = currentPosition
            panMode = .none
        case .changed:
            let dx = p.x - panStart.x
            let dy = p.y - panStart.y
            if panMode == .none {
                if abs(dx) > abs(dy) && abs(dx) > 12 {
                    panMode = .seek
                } else if abs(dy) > 12 {
                    // 与 KSPlayer 官方相反：用户要「左亮度、右音量」
                    panMode = p.x < view.bounds.width / 2 ? .brightness : .volume
                }
            }
            switch panMode {
            case .seek:
                let sensitivity = currentDuration / Double(max(view.bounds.width, 1)) * 1.5
                let target = (panStartTime + Double(dx) * sensitivity).clamped(to: 0...max(currentDuration - 0.1, 0))
                playerLayer?.seek(time: target)
                hud.show(text: "\(ChapterState.fmt(target)) / \(ChapterState.fmt(currentDuration))")
            case .brightness:
                let v = panStartBrightness - CGFloat(dy / view.bounds.height) * 1.2
                UIScreen.main.brightness = v.clamped(to: 0.05...1.0)
                hud.show(text: "☀️ 亮度 \(Int(UIScreen.main.brightness * 100))%", icon: .brightness, value: Float(UIScreen.main.brightness))
            case .volume:
                let v = panStartVolume - Float(dy / view.bounds.height) * 1.5
                setVolume(v.clamped(to: 0...1))
                hud.show(text: "🔊 音量 \(Int(currentVolume * 100))%", icon: .volume, value: currentVolume)
            case .none: break
            }
        case .ended, .cancelled:
            if panMode == .seek { saveProgress() }
            panMode = .none
            hud.hide()
        default: break
        }
    }

    var currentVolume: Float {
        volumeView.subviews.compactMap { $0 as? UISlider }.first?.value ?? 0.5
    }
    private func setVolume(_ v: Float) {
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(v, animated: false)
    }

    private func seekBy(_ delta: Double) {
        let target = (currentPosition + delta).clamped(to: 0...max(currentDuration - 0.1, 0))
        playerLayer?.seek(time: target)
        saveProgress()
    }

    // MARK: - 控件动作
    private func togglePlay() {
        // KSPlayer state 判断播放中
        if playerLayer?.state.isPlaying == true {
            playerLayer?.pause()
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            playerLayer?.play()
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }

    private func toggleControls() {
        controlsVisible.toggle()
        UIView.animate(withDuration: 0.2) {
            self.topBar.alpha = self.controlsVisible ? 1 : 0
            self.bottomBar.alpha = self.controlsVisible ? 1 : 0
        }
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self, self.playerLayer?.state.isPlaying == true else { return }
            UIView.animate(withDuration: 0.2) {
                self.topBar.alpha = 0
                self.bottomBar.alpha = 0
            }
            self.controlsVisible = false
        }
    }

    @objc private func onBack() { dismiss(animated: true) }
    @objc private func onPrev() { if index > 0 { index -= 1; saveProgress(); hud.hide(); loadCurrent() } }
    @objc private func onNext() { if index < videos.count - 1 { index += 1; saveProgress(); hud.hide(); loadCurrent() } }
    @objc private func onSlider(_ s: UISlider) {
        let target = Double(s.value) * currentDuration
        playerLayer?.seek(time: target)
    }
    @objc private func onSliderEnd() { saveProgress() }
    @objc private func onSpeed() {
        let all: [Float] = [1.0, 1.25, 1.5, 2.0]
        let cur = playerLayer?.player.playbackRate ?? 1.0
        let idx = all.firstIndex(where: { abs($0 - cur) < 0.01 }) ?? 0
        let next = all[(idx + 1) % all.count]
        playerLayer?.player.playbackRate = next
        speedButton.setTitle(String(format: "%.2gx", next), for: .normal)
        hud.show(text: "倍速 \(next)x")
    }
    @objc private func onLock() {
        isLocked.toggle()
        lockButton.setImage(UIImage(systemName: isLocked ? "lock.fill" : "lock.open.fill"), for: .normal)
        hud.show(text: isLocked ? "🔒 已锁定" : "🔓 已解锁")
    }
    @objc private func onFullscreen() {
        let app = UIApplication.shared.delegate as? AppDelegate
        if view.bounds.width < view.bounds.height {
            app?.orientationMask = .landscapeRight
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        } else {
            app?.orientationMask = .portrait
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }

    // MARK: - 进度保存
    private func saveProgress() {
        guard videos.indices.contains(index) else { return }
        let file = videos[index]
        var st = store.get(course: courseName).state(for: file.path)
        st.position = currentPosition
        st.duration = currentDuration
        st.status = .watching
        st.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        store.update(course: courseName, path: file.path, state: st)
        onStateChange?(file.path, currentPosition, currentDuration, false)
    }

    private func markDone() {
        guard videos.indices.contains(index), !didFinish else { return }
        didFinish = true
        let file = videos[index]
        var st = store.get(course: courseName).state(for: file.path)
        st.status = .done
        st.position = currentDuration
        st.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        store.update(course: courseName, path: file.path, state: st)
        onStateChange?(file.path, st.position, st.duration, true)
        hud.show(text: "✓ 已标记已看")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgress()
        Task { await store.flush(course: courseName) }
    }
}

// MARK: - KSPlayerLayerDelegate
extension KSPlayerViewController: KSPlayerLayerDelegate {
    func player(layer: KSPlayer.KSPlayerLayer, state: KSPlayer.KSPlayerState) {
        playButton.setImage(
            UIImage(systemName: state.isPlaying ? "pause.fill" : "play.fill"),
            for: .normal
        )
    }

    func player(layer: KSPlayer.KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        currentPosition = currentTime
        currentDuration = totalTime
        currentLabel.text = ChapterState.fmt(currentTime)
        totalLabel.text = ChapterState.fmt(totalTime)
        if totalTime > 0 {
            slider.value = Float(currentTime / totalTime)
            // 播到 95% 自动已看
            if currentTime / totalTime >= 0.95 { markDone() }
        }
    }

    func player(layer: KSPlayer.KSPlayerLayer, finish error: (any Error)?) {
        if error == nil { markDone() }
    }

    func playerDidEOF(layer: KSPlayer.KSPlayerLayer) { markDone() }
}

// MARK: - 手势代理：滑动优先于长按
extension KSPlayerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { !isLocked }
}
