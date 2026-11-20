import UIKit
import KSPlayer

extension KSPlayerViewController {

    var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    func buildUI() {
        // 顶部栏
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 52),
        ])

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(onBack), for: .touchUpInside)
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 1

        lockButton.setImage(UIImage(systemName: "lock.open.fill"), for: .normal)
        lockButton.tintColor = .white
        lockButton.addTarget(self, action: #selector(onLock), for: .touchUpInside)

        let topStack = UIStackView(arrangedSubviews: [backButton, titleLabel, UIView(), lockButton])
        topStack.axis = .horizontal
        topStack.spacing = 10
        topStack.alignment = .center
        topBar.addSubview(topStack)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14),
            topStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            topStack.topAnchor.constraint(equalTo: topBar.topAnchor),
            topStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
        ])

        // 底部栏
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.addSubview(bottomBar)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        currentLabel.text = "00:00"
        totalLabel.text = "00:00"
        currentLabel.textColor = .white
        totalLabel.textColor = .white
        currentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
        slider.thumbTintColor = .white
        slider.addTarget(self, action: #selector(onSlider(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(onSliderEnd), for: .touchUpInside)
        let progressRow = UIStackView(arrangedSubviews: [currentLabel, slider, totalLabel])
        progressRow.axis = .horizontal
        progressRow.spacing = 8
        progressRow.alignment = .center

        playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        prevButton.setImage(UIImage(systemName: "backward.end.fill"), for: .normal)
        nextButton.setImage(UIImage(systemName: "forward.end.fill"), for: .normal)
        fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        speedButton.setTitle("1.00x", for: .normal)
        [playButton, prevButton, nextButton, fullscreenButton, speedButton].forEach {
            $0.tintColor = .white
            $0.setTitleColor(.white, for: .normal)
        }
        playButton.addTarget(self, action: #selector(onPlayTap), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(onPrev), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(onNext), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(onFullscreen), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(onSpeed), for: .touchUpInside)
        speedButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)

        let spacer = UIView()
        let controlRow = UIStackView(arrangedSubviews: [prevButton, playButton, nextButton, spacer, speedButton, fullscreenButton])
        controlRow.axis = .horizontal
        controlRow.spacing = 20
        controlRow.alignment = .center

        let vStack = UIStackView(arrangedSubviews: [progressRow, controlRow])
        vStack.axis = .vertical
        vStack.spacing = 6
        bottomBar.addSubview(vStack)
        vStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 14),
            vStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14),
            vStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8),
            vStack.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        // HUD
        view.addSubview(hud)
        hud.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hud.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hud.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hud.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])

        scheduleHide()
    }

    @objc func onPlayTap() { togglePlay() }
}

// MARK: - 中央 HUD
final class PlayerHUD: UIView {
    private let label = UILabel()
    private let barBg = UIView()
    private let barFill = UIView()
    private var barFillRatio: NSLayoutConstraint!
    private var hideWork: DispatchWorkItem?

    enum Kind { case none, brightness, volume }

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 12
        isHidden = true

        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        barBg.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        barBg.layer.cornerRadius = 2
        barFill.backgroundColor = .white
        barFill.layer.cornerRadius = 2

        let stack = UIStackView(arrangedSubviews: [label, barBg])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        barBg.translatesAutoresizingMaskIntoConstraints = false
        barFill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            barBg.heightAnchor.constraint(equalToConstant: 4),
            barBg.widthAnchor.constraint(equalToConstant: 180),
            barFill.leadingAnchor.constraint(equalTo: barBg.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barBg.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barBg.bottomAnchor),
        ])
        barFillRatio = barFill.widthAnchor.constraint(equalTo: barBg.widthAnchor, multiplier: 0.5)
        barFillRatio.isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(text: String, icon: Kind = .none, value: Float = 0) {
        label.text = text
        barBg.isHidden = icon == .none
        if icon != .none {
            let ratio = CGFloat(value.clamped(to: 0...1))
            barFillRatio.isActive = false
            barFillRatio = barFill.widthAnchor.constraint(equalTo: barBg.widthAnchor, multiplier: ratio)
            barFillRatio.isActive = true
        }
        isHidden = false
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.isHidden = true }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }

    func hide() { isHidden = true }
}
