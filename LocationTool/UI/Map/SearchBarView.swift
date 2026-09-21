import UIKit

/// 顶部搜索栏
final class SearchBarView: UIView {
    let searchField = UITextField()
    let searchButton = UIButton(type: .system)
    let cancelButton = UIButton(type: .system)

    var onSearch: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemBackground

        searchField.placeholder = "搜索地点"
        searchField.borderStyle = .roundedRect
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.leftView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        searchField.leftViewMode = .always
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchButton.setTitle("搜索", for: .normal)
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        searchButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.isHidden = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [searchField, searchButton, cancelButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    @objc private func searchTapped() {
        searchField.resignFirstResponder()
        onSearch?(searchField.text ?? "")
    }

    @objc private func cancelTapped() {
        searchField.text = ""
        cancelButton.isHidden = true
        onCancel?()
    }

    func setCancelHidden(_ hidden: Bool) {
        cancelButton.isHidden = hidden
    }
}

extension SearchBarView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        searchTapped()
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        cancelButton.isHidden = false
    }
}
