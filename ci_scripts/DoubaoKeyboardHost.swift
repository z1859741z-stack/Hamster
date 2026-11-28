// Standalone simulator-only host for screenshots of the Hamster keyboard (豆包风格对照用).
// Not part of Hamster's Xcode project; compiled with swiftc by ci_scripts/doubao-sim-shots.sh.
// A normal (non-secure) text field becomes first responder on launch so iOS shows the
// currently selected keyboard. Launch argument `-returnKeyType search|send|default`.
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = HostController()
    self.window = window
    window.makeKeyAndVisible()
  }
}

final class HostController: UIViewController {
  private let field = UITextField()

  private var returnKeyType: UIReturnKeyType {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "-returnKeyType"), index + 1 < args.count else { return .search }
    switch args[index + 1] {
    case "send": return .send
    case "default": return .default
    case "go": return .go
    case "done": return .done
    default: return .search
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? .black : UIColor(red: 240 / 255, green: 241 / 255, blue: 243 / 255, alpha: 1) }
    field.placeholder = "豆包风格对照"
    field.borderStyle = .roundedRect
    field.returnKeyType = returnKeyType
    field.autocorrectionType = .no
    field.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(field)
    NSLayoutConstraint.activate([
      field.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
      field.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      field.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    field.becomeFirstResponder()
  }
}
