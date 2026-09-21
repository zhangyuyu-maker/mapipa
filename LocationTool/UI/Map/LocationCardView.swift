import UIKit

/// 底部位置信息卡片
/// 展示当前选中点的名称、经纬度，以及「设为模拟位置」「开始/停止模拟」按钮
final class LocationCardView: UIView {
    private let nameLabel = UILabel()
    private let addressLabel = UILabel()
    private let coordinateLabel = UILabel()
    private let statusLabel = UILabel()
    private let statusDot = UIView()
    let setMockButton = UIButton(type: .system)
    let startButton = UIButton(type: .system)

    var onSetMock: (() -> Void)?
    var onStartStop: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -2)

        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.text = "未选择位置"

        addressLabel.font = .systemFont(ofSize: 13)
        addressLabel.textColor = .secondaryLabel
        addressLabel.numberOfLines = 2

        coordinateLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        coordinateLabel.textColor = .secondaryLabel

        statusDot.layer.cornerRadius = 5
        statusDot.backgroundColor = .systemGray

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.text = "模拟定位：已停止"

        setMockButton.setTitle("设为模拟位置", for: .normal)
        setMockButton.configuration = .filled()
        setMockButton.isEnabled = false
        setMockButton.addTarget(self, action: #selector(setMockTapped), for: .touchUpInside)

        startButton.setTitle("开始模拟", for: .normal)
        startButton.configuration = .filled()
        startButton.tintColor = .systemGreen
        startButton.isEnabled = false
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        let infoStack = UIStackView(arrangedSubviews: [nameLabel, addressLabel, coordinateLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 2

        let statusStack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusStack.axis = .horizontal
        statusStack.spacing = 6
        statusStack.alignment = .center

        let buttonStack = UIStackView(arrangedSubviews: [setMockButton, startButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        let root = UIStackView(arrangedSubviews: [infoStack, statusStack, buttonStack])
        root.axis = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10)
        ])
    }

    // MARK: - 对外更新接口

    func update(point: LocationPoint?) {
        guard let point = point else {
            nameLabel.text = "未选择位置"
            addressLabel.text = nil
            coordinateLabel.text = nil
            setMockButton.isEnabled = false
            return
        }
        nameLabel.text = point.name ?? "已选择位置"
        addressLabel.text = point.address
        coordinateLabel.text = String(format: "%.6f, %.6f", point.latitude, point.longitude)
        setMockButton.isEnabled = true
    }

    func updateStatus(_ status: SimulationStatus) {
        switch status {
        case .stopped:
            statusDot.backgroundColor = .systemGray
            statusLabel.text = "模拟定位：已停止"
            startButton.setTitle("开始模拟", for: .normal)
            startButton.tintColor = .systemGreen
        case .running:
            statusDot.backgroundColor = .systemGreen
            statusLabel.text = "模拟定位：运行中"
            startButton.setTitle("停止模拟", for: .normal)
            startButton.tintColor = .systemRed
        }
    }

    func setStartEnabled(_ enabled: Bool) {
        startButton.isEnabled = enabled
    }

    @objc private func setMockTapped() { onSetMock?() }
    @objc private func startTapped() { onStartStop?() }
}
