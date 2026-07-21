import UIKit

// Opaque cover (.plans/mobile/02 §4): brand blue + wordmark. Shown while locked AND on
// resign-active so the app-switcher snapshot never shows balances. The retry button
// appears only after a failed/cancelled auth.
final class LockScreenViewController: UIViewController {
    var onRetry: (() -> Void)?

    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x1C / 255.0, green: 0x7A / 255.0, blue: 0xDB / 255.0, alpha: 1)

        let logo = UILabel()
        logo.text = "azulzin"
        logo.textColor = .white
        logo.font = .systemFont(ofSize: 40, weight: .heavy)

        retryButton.setTitle(String(localized: "lock.retry"), for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        retryButton.layer.borderColor = UIColor.white.cgColor
        retryButton.layer.borderWidth = 1.5
        retryButton.layer.cornerRadius = 12
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
        retryButton.isHidden = true
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [logo, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 32
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func showRetry(_ show: Bool) {
        loadViewIfNeeded()
        retryButton.isHidden = !show
    }
}
