import UIKit

/// 左侧历史定位列表视图
///
/// 显示最近的历史定位记录 (按 createdAt DESC 排序):
/// - 列表区域最多显示 5 条高度, 超过可上下滑动
/// - 单击: 切换到该定位 (不新增历史记录)
/// - 长按: 弹出删除确认
final class LocationHistoryView: UIView {
    // MARK: - 回调
    /// 单击历史记录: 切换到该定位 (不新增历史)
    var onSelect: ((LocationHistoryItem) -> Void)?
    /// 长按历史记录: 弹出删除确认 (由控制器处理弹窗与 API 调用)
    var onLongPress: ((LocationHistoryItem) -> Void)?

    // MARK: - UI
    private let titleLabel = UILabel()
    private let tableView = UITableView()
    private let emptyLabel = UILabel()

    // MARK: - 数据
    private var items: [LocationHistoryItem] = []

    // MARK: - 布局常量
    private let itemHeight: CGFloat = 56
    /// 列表区域最多显示的行数 (超过则内部滚动)
    private let maxVisibleRows = 5

    // MARK: - 初始化
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        // 标题
        titleLabel.text = "历史定位"
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // 列表 (内部可滚动, 超过 5 条时上下滑动)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HistoryCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isScrollEnabled = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        addSubview(tableView)

        // 长按手势 (弹出删除确认)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.6
        tableView.addGestureRecognizer(longPress)

        // 空状态
        emptyLabel.text = "暂无历史定位"
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    // MARK: - 数据更新
    func updateItems(_ newItems: [LocationHistoryItem]) {
        items = newItems
        tableView.reloadData()
        let isEmpty = items.isEmpty
        emptyLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }

    /// 列表可见区域高度 (标题 + 最多 5 行)
    var contentHeight: CGFloat {
        let titleSection: CGFloat = 10 + 20 + 6  // top + title + spacing
        return titleSection + CGFloat(maxVisibleRows) * itemHeight
    }

    // MARK: - 长按
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point) else { return }
        let item = items[indexPath.row]
        onLongPress?(item)
    }

    // MARK: - 时间格式化
    /// 今天: HH:mm
    /// 昨天: 昨天 HH:mm
    /// 更早: N天前
    private func formatTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }

        let calendar = Calendar.current
        let now = Date()
        let calendarNow = calendar.startOfDay(for: now)
        let calendarDate = calendar.startOfDay(for: date)
        let dayDiff = calendar.dateComponents([.day], from: calendarDate, to: calendarNow).day ?? 0

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")

        switch dayDiff {
        case 0:
            // 今天: 只显示时间
            timeFormatter.dateFormat = "HH:mm"
            return timeFormatter.string(from: date)
        case 1:
            // 昨天: 昨天 HH:mm
            timeFormatter.dateFormat = "HH:mm"
            return "昨天 \(timeFormatter.string(from: date))"
        default:
            // 更早: N天前
            return "\(dayDiff)天前"
        }
    }
}

// MARK: - UITableViewDataSource
extension LocationHistoryView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.name
        content.secondaryText = formatTime(item.createdAt)
        content.textProperties.font = .systemFont(ofSize: 14, weight: .medium)
        content.textProperties.numberOfLines = 1
        content.secondaryTextProperties.font = .systemFont(ofSize: 11)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        return cell
    }
}

// MARK: - UITableViewDelegate
extension LocationHistoryView: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        onSelect?(item)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        itemHeight
    }
}
