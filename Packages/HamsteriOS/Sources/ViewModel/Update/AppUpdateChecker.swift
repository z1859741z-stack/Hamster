//
//  AppUpdateChecker.swift
//  Hamster
//
//  App 内更新检查：查公开仓库的 GitHub Releases latest，有新版就弹窗提示去 Release 页下载。
//  仓库是公开的，不用 token；绝不把任何 token 打进 App。
//  不做系统级 OTA，只在主 App 内弹窗。
//  注意：仓库现在还没有任何 Release，API 会返回 404、不弹窗——这是正常的，
//  等 v3.0.0-ethan.1 的 Release 建好后才有得比。
//

import Foundation
import UIKit

/// GitHub Releases latest 的最小响应体（只要 tag 名和 Release 页地址）。
private struct GitHubLatestRelease: Decodable {
  var tag_name: String
  var html_url: String
}

public final class AppUpdateChecker {
  public static let shared = AppUpdateChecker()

  /// Releases API（公开仓库，无需认证）。
  private static let latestReleaseURL = URL(string: "https://api.github.com/repos/z1859741z-stack/Hamster/releases/latest")!

  /// 同一版本只提醒一次：记下已弹过窗的 tag。
  private static let promptedTagKey = "com.ihsiao.apps.Hamster.AppUpdate.promptedTag"
  /// 检查节流：一天最多查一次。
  private static let lastCheckDateKey = "com.ihsiao.apps.Hamster.AppUpdate.lastCheckDate"
  private static let checkInterval: TimeInterval = 24 * 60 * 60

  /// 同一次启动内只查一次（首页 viewDidAppear 每次回首页都会触发）。
  private var checkedThisLaunch = false

  private init() {}

  /// 在首页出现时调。首次启动正在部署输入方案时不弹。
  @MainActor
  public func checkAndPromptIfNeeded(from viewController: UIViewController) {
    guard !checkedThisLaunch else { return }
    checkedThisLaunch = true
    // 首次启动正在部署输入方案，先不弹更新窗。
    guard !UserDefaults.standard.isFirstRunning else { return }
    // 一天最多查一次。
    if let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckDateKey) as? Date,
       Date().timeIntervalSince(lastCheck) < Self.checkInterval {
      return
    }

    Task.detached {
      let release = await Self.fetchLatestRelease()
      // 无论成败都记一次检查时间（仓库还没有 Release 时 API 返回 404，也是正常情况）。
      UserDefaults.standard.set(Date(), forKey: Self.lastCheckDateKey)
      guard let release else { return }
      guard Self.isNewerThanCurrent(tag: release.tag_name) else { return }
      // 同一版本只提醒一次。
      if UserDefaults.standard.string(forKey: Self.promptedTagKey) == release.tag_name { return }
      await MainActor.run {
        guard viewController.view.window != nil else { return }
        UserDefaults.standard.set(release.tag_name, forKey: Self.promptedTagKey)
        Self.presentUpdateAlert(from: viewController, release: release)
      }
    }
  }

  /// 取 latest Release；404（仓库还没有 Release）或网络失败都返回 nil，不弹。
  private static func fetchLatestRelease() async -> GitHubLatestRelease? {
    var request = URLRequest(url: latestReleaseURL)
    request.setValue("HamsterApp", forHTTPHeaderField: "User-Agent")
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
      return try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
    } catch {
      return nil
    }
  }

  /// tag 形如 v3.0.0-ethan.1：去 v 前缀、取横杠前的版本号核心，与当前版本做数字比较。
  static func isNewerThanCurrent(tag: String) -> Bool {
    // trimmingPrefix 要 iOS 16+，最低版本是 iOS 15.0，改用 hasPrefix + dropFirst。
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutV = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    let core = withoutV.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
    let remote = core.split(separator: ".").compactMap { Int($0) }
    let local = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
      .split(separator: ".").compactMap { Int($0) }
    guard !remote.isEmpty, !local.isEmpty else { return false }
    for (r, l) in zip(remote, local) {
      if r != l { return r > l }
    }
    return remote.count > local.count
  }

  @MainActor
  private static func presentUpdateAlert(from viewController: UIViewController, release: GitHubLatestRelease) {
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let alert = UIAlertController(
      title: "发现新版本 \(release.tag_name)",
      message: "当前版本 \(current)，最新版本 \(release.tag_name)。",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "去下载", style: .default) { _ in
      if let url = URL(string: release.html_url) {
        UIApplication.shared.open(url)
      }
    })
    alert.addAction(UIAlertAction(title: "稍后", style: .cancel))
    viewController.present(alert, animated: true)
  }
}
