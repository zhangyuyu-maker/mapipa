import UIKit

/// 路线模拟控制面板
/// 显示路线信息、速度滑块、循环开关、进度与控制按钮
/// 通过回调与外部交互，不直接依赖 RouteManager / MapService
final class RouteCardView: UIView {
    // MARK: - 回调
    var onSpeedChange: ((Double) -> Void)?
    var onLoopChange: ((Bool) -> Void)?
    var onClear: (() -> Void)?
    var onStart: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onStop: (() -> Void)?

    // MARK: - 子视图
    private let infoLabel = UILabel()
    private let speedLabel = UILabel()
    private let speedSlider = UISlider()
    private let loopLabel = UILabel()
    private let loopSwitch = UISwitch()
    private let progressView = UIProgressView()
    private let progressLabel = UILabel()
    private let buttonStack = UIStackView()
    private let clearButton = UIButton(type: .system)
    private let startPauseButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)

    // MARK: - 状态
    private var isRunning: Bool = false
    private var isPaused: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 布局

    private func setupView() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let container = UIStackView(arrangedSubviews: [
            infoRow(), speedRow(), loopRow(),
            progressRow(), buttonRow()
        ])
        container.axis = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func infoRow() -> UIView {
        infoLabel.font = .systemFont(ofSize: 13, weight: .medium)
        infoLabel.textColor = .label
        infoLabel.numberOfLines = 0
        infoLabel.text = "路线：未添加点"
        return infoLabel
    }

    private func speedRow() -> UIView {
        speedLabel.font = .systemFont(ofSize: 12)
        speedLabel.textColor = .secondaryLabel
        speedLabel.text = "速度：18 km/h"

        speedSlider.minimumValue = 1
        speedSlider.maximumValue = 30   // m/s, 约 3.6-108 km/h
        speedSlider.value = 5
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [speedLabel, speedSlider])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        updateSpeedLabel()
        return row
    }

    private func loopRow() -> UIView {
        loopLabel.font = .systemFont(ofSize: 12)
        loopLabel.textColor = .secondaryLabel
        loopLabel.text = "循环路线"
        loopSwitch.isOn = false
        loopSwitch.addTarget(self, action: #selector(loopToggled), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [loopLabel, loopSwitch])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    private func progressRow() -> UIView {
        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = .secondaryLabel
        progressLabel.text = "进度：0% · 0 m / 0 m"
        progressView.progress = 0

        let row = UIStackView(arrangedSubviews: [progressView, progressLabel])
        row.axis = .vertical
        row.spacing = 4
        return row
    }

    private func buttonRow() -> UIView {
        configureButton(clearButton, title: "清空", color: .systemGray, icon: "trash")
        configureButton(startPauseButton, title: "开始", color: .systemGreen, icon: "play.fill")
        configureButton(stopButton, title: "停止", color: .systemRed, icon: "stop.fill")

        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8
        buttonStack.addArrangedSubview(clearButton)
        buttonStack.addArrangedSubview(startPauseButton)
        buttonStack.addArrangedSubview(stopButton)

        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        startPauseButton.addTarget(self, action: #selector(startPauseTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)

        updateButtonStates()
        return buttonStack
    }

    private func configureButton(_ b: UIButton, title: String, color: UIColor, icon: String) {
        b.setTitle(title, for: .normal)
        b.tintColor = color
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = color.withAlphaComponent(0.12)
        b.layer.cornerRadius = 10
        let img = UIImage(systemName: icon)
        b.setImage(img, for: .normal)
        b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
    }

    // MARK: - 事件

    @objc private func speedChanged() {
        updateSpeedLabel()
        onSpeedChange?(Double(speedSlider.value))
    }

    @objc private func loopToggled() {
        onLoopChange?(loopSwitch.isOn)
    }

    @objc private func clearTapped() {
        onClear?()
    }

    @objc private func startPauseTapped() {
        if isRunning && !isPaused {
            onPause?()
        } else if isPaused {
            onResume?()
        } else {
            onStart?()
        }
    }

    @objc private func stopTapped() {
        onStop?()
    }

    // MARK: - 外部更新

    func updateRouteInfo(pointCount: Int, totalDistance: Double, estimatedDuration: TimeInterval) {
        if pointCount == 0 {
            infoLabel.text = "路线：未添加点（点击地图添加）"
        } else if pointCount == 1 {
            infoLabel.text = "路线：\(pointCount) 个点（至少需要 2 个点）"
        } else {
            infoLabel.text = "路线：\(pointCount) 个点 · \(formatDistance(totalDistance)) · 约 \(formatDuration(estimatedDuration))"
        }
    }

    func updateProgress(_ progress: RouteProgress) {
        progressView.progress = Float(progress.progress)
        progressLabel.text = "进度：\(Int(progress.progress * 100))% · \(formatDistance(progress.elapsedDistance)) / \(formatDistance(progress.totalDistance)) · 段 \(progress.segmentIndex + 1)/\(progress.totalSegments)"
    }

    func updateStatus(_ status: RouteStatus) {
        isRunning = (status == .running || status == .paused)
        isPaused = (status == .paused)
        updateButtonStates()
    }

    func currentSpeed() -> Double {
        Double(speedSlider.value)
    }

    func currentLoop() -> Bool {
        loopSwitch.isOn
    }

    func resetProgress() {
        progressView.progress = 0
        progressLabel.text = "进度：0% · 0 m / 0 m"
    }

    // MARK: - 私有

    private func updateSpeedLabel() {
        let ms = Double(speedSlider.value)
        let kmh = ms * 3.6
        speedLabel.text = "速度：\(Int(kmh)) km/h"
    }

    private func updateButtonStates() {
        if !isRunning {
            startPauseButton.setTitle("开始", for: .normal)
            startPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            startPauseButton.tintColor = .systemGreen
            startPauseButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        } else if isPaused {
            startPauseButton.setTitle("继续", for: .normal)
            startPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            startPauseButton.tintColor = .systemGreen
            startPauseButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        } else {
            startPauseButton.setTitle("暂停", for: .normal)
            startPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            startPauseButton.tintColor = .systemOrange
            startPauseButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        }
        stopButton.isEnabled = isRunning
        stopButton.alpha = isRunning ? 1.0 : 0.4
    }

    private func formatDistance(_ m: Double) -> String {
        if m < 1000 { return "\(Int(m)) m" }
        return String(format: "%.2f km", m / 1000)
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return "\(h)时\(m)分" }
        if m > 0 { return "\(m)分\(sec)秒" }
        return "\(sec)秒"
    }
}
