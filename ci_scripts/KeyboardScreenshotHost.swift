// Standalone simulator-only screenshot host. This is not part of Hamster's Xcode project.
// A secure field intentionally forces iOS to use its system keyboard, not a third-party extension.
import UIKit

private let readyFilename = "hamster-system-keyboard-ready"

private func readyURL() -> URL {
  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent(readyFilename)
}

private func clearReady() {
  try? FileManager.default.removeItem(at: readyURL())
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    clearReady()
    let window = UIWindow(windowScene: scene)
    window.rootViewController = KeyboardHostController()
    self.window = window
    window.makeKeyAndVisible()
  }

  func sceneWillResignActive(_ scene: UIScene) { clearReady() }
  func sceneDidDisconnect(_ scene: UIScene) { clearReady() }
}

final class KeyboardHostController: UIViewController {
  private let field = UITextField()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let title = UILabel()
    title.text = "System keyboard — secure input"
    title.font = .preferredFont(forTextStyle: .title2)
    title.numberOfLines = 0
    title.accessibilityIdentifier = "keyboardHost.title"
    title.translatesAutoresizingMaskIntoConstraints = false
    field.placeholder = "Secure field (no text entered)"
    field.borderStyle = .roundedRect
    field.isSecureTextEntry = true
    field.keyboardType = .asciiCapable
    field.autocorrectionType = .no
    field.accessibilityIdentifier = "keyboardHost.secureField"
    field.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(title)
    view.addSubview(field)
    NSLayoutConstraint.activate([
      title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
      title.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      title.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      field.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
      field.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      field.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
    ])
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow(_:)),
                                           name: UIResponder.keyboardDidShowNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide(_:)),
                                           name: UIResponder.keyboardDidHideNotification, object: nil)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Allow the scene to finish becoming active before requesting the keyboard.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      _ = self?.field.becomeFirstResponder()
    }
  }

  @objc private func keyboardDidShow(_ notification: Notification) {
    guard field.isFirstResponder, field.isSecureTextEntry,
          UIApplication.shared.applicationState == .active,
          let window = view.window,
          let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
    let screen = window.screen.bounds
    let overlap = screen.intersection(frame)
    // Reject a small hardware-keyboard shortcut bar; this heuristic is not a pixel assertion.
    guard !overlap.isNull, overlap.width >= screen.width * 0.5,
          overlap.height >= min(180, screen.height * 0.2) else { return }
    do {
      try FileManager.default.createDirectory(at: readyURL().deletingLastPathComponent(),
                                              withIntermediateDirectories: true, attributes: nil)
      // The host may capture only after a genuine keyboard-did-show notification.
      try "secure-field-first-responder; keyboard-did-show\n".write(to: readyURL(), atomically: true, encoding: .utf8)
    } catch {
      NSLog("Could not write keyboard readiness marker: %@", String(describing: error))
    }
  }

  @objc private func keyboardDidHide(_ notification: Notification) { clearReady() }
}
