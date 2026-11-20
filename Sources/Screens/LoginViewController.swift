import UIKit

final class LoginViewController: UIViewController {

    private let serverField = UITextField()
    private let userField = UITextField()
    private let passField = UITextField()
    private let loginButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "刷题课堂"
        view.backgroundColor = .systemBackground
        buildUI()
        serverField.text = AppConfig.serverURL
        userField.text = AppConfig.username
        passField.text = AppConfig.password
    }

    private func buildUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
        ])

        let hint = UILabel()
        hint.text = "登录 Alist 后即可开始刷题。地址与课程目录已内置，只需填账号密码。"
        hint.numberOfLines = 0
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabel
        stack.addArrangedSubview(hint)

        serverField.placeholder = "Alist 地址"
        serverField.borderStyle = .roundedRect
        serverField.autocapitalizationType = .none
        serverField.keyboardType = .URL
        userField.placeholder = "账号"
        userField.borderStyle = .roundedRect
        userField.autocapitalizationType = .none
        passField.placeholder = "密码"
        passField.borderStyle = .roundedRect
        passField.isSecureTextEntry = true
        [serverField, userField, passField].forEach { stack.addArrangedSubview($0) }

        loginButton.setTitle("登录", for: .normal)
        loginButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        loginButton.backgroundColor = .systemBlue
        loginButton.setTitleColor(.white, for: .normal)
        loginButton.layer.cornerRadius = 10
        loginButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
        loginButton.addTarget(self, action: #selector(doLogin), for: .touchUpInside)
        stack.addArrangedSubview(loginButton)
    }

    @objc private func doLogin() {
        let server = serverField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let user = userField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let pass = passField.text ?? ""
        guard !server.isEmpty, !user.isEmpty, !pass.isEmpty else {
            alert("请填写完整"); return
        }
        AppConfig.serverURL = server
        loginButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await AlistService.shared.login(username: user, password: pass)
                AppConfig.token = token
                AppConfig.username = user
                AppConfig.password = pass
                await MainActor.run {
                    (UIApplication.shared.delegate as? AppDelegate)?.switchToHome()
                }
            } catch {
                await MainActor.run {
                    self.loginButton.isEnabled = true
                    self.alert("登录失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func alert(_ msg: String) {
        let ac = UIAlertController(title: "提示", message: msg, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default))
        present(ac, animated: true)
    }
}
