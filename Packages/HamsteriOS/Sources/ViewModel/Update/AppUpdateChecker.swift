//
//  AppUpdateChecker.swift
//  Hamster
//
//  App 内更新检查：查公开仓库的 GitHub Releases latest，有新版就弹窗提示去 Release 页下载。
//  仓库是公开的，不用 token；绝不把任何 token 打进 App。
//  不做系统级 OTA，只在主 App 内弹窗。
//  比较逻辑：先比版本号核心；版本号相同再比 build 号（从 Release 的 IPA 文件名里解析 bN）。
//  以后只升 build 也要能弹。tag 里没有 bN 时（旧 tag），只按版本号比。
//

import Foundation
import UIKit

/// GitHub Releases latest 的最小响应体（只要 tag 名、Release 页地址和附件名）。
private struct GitHubLatestRelease: Decodable {
  var tag_name: String
  var html_url: String
  var assets: [GitHubReleaseAsset]?
}

private struct GitHubReleaseAsset: Decodable {
  var name: String
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

  /// 同一次启动内只自动查一次（首页 viewDidAppear 每次回首页都会触发）。
  private var checkedThisLaunch = false

  /// 手动检查进行中：正在查时再点版本号不重复弹。
  private var manualCheckInFlight = false

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
      guard Self.isNewerThanCurrent(tag: release.tag_name, assetNames: release.assets?.map(\.name) ?? []) else { return }
      // 同一版本只提醒一次。
      if UserDefaults.standard.string(forKey: Self.promptedTagKey) == release.tag_name { return }
      await MainActor.run {
        guard viewController.view.window != nil else { return }
        UserDefaults.standard.set(release.tag_name, forKey: Self.promptedTagKey)
        Self.presentUpdateAlert(from: viewController, release: release)
      }
    }
  }

  /// 点版本号手动查：有新版弹「发现新版」；已是最新版提示「已是最新」；网络失败也提示。
  /// 不受一天一次限制；正在查时再点不重复弹。
  @MainActor
  public func checkManually(from viewController: UIViewController) {
    guard !manualCheckInFlight else { return }
    manualCheckInFlight = true

    Task.detached { [weak self] in
      let release = await Self.fetchLatestRelease()
      await MainActor.run {
        self?.manualCheckInFlight = false
        guard viewController.view.window != nil else { return }
        guard let release else {
          Self.presentSimpleAlert(from: viewController, title: "检查失败", message: "检查失败，请稍后再试。")
          return
        }
        if Self.isNewerThanCurrent(tag: release.tag_name, assetNames: release.assets?.map(\.name) ?? []) {
          Self.presentUpdateAlert(from: viewController, release: release)
        } else {
          Self.presentSimpleAlert(from: viewController, title: "已是最新", message: "当前已是最新版本。")
        }
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

  /// 先比版本号核心；版本号相同再比 build 号（从 Release 的 IPA 文件名里解析 bN）。
  /// tag 形如 v3.0.1-ethan.2；IPA 文件名形如 Hamster-v3.0.1-b25-<hash>-unsigned.ipa。
  static func isNewerThanCurrent(tag: String, assetNames: [String] = []) -> Bool {
    let remote = versionNumbers(of: versionCore(of: tag))
    let local = versionNumbers(of: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    guard !remote.isEmpty, !local.isEmpty else { return false }
    for (r, l) in zip(remote, local) {
      if r != l { return r > l }
    }
    if remote.count != local.count { return remote.count > local.count }
    // 版本号相同：再比 build 号；文件名里没有 bN 时只按版本号比（不算新版）。
    guard let remoteBuild = buildNumber(fromAssetNames: assetNames) else { return false }
    let localBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    return remoteBuild > localBuild
  }

  /// tag 去 v 前缀、取横杠前的版本号核心，如 v3.0.1-ethan.2 → 3.0.1。
  private static func versionCore(of tag: String) -> String {
    // trimmingPrefix 要 iOS 16+，最低版本是 iOS 15.0，改用 hasPrefix + dropFirst。
    let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutV = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    return withoutV.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
  }

  private static func versionNumbers(of version: String) -> [Int] {
    version.split(separator: ".").compactMap { Int($0) }
  }

  /// 从 Release 附件文件名解析 build 号：Hamster-v3.0.1-b25-<hash>-unsigned.ipa → 25。
  /// 文件名里没有 bN 时返回 nil。
  private static func buildNumber(fromAssetNames names: [String]) -> Int? {
    for name in names {
      var searchFrom = name.startIndex
      while let range = name.range(of: "-b", range: searchFrom..<name.endIndex) {
        var end = range.upperBound
        while end < name.endIndex, name[end].isNumber { end = name.index(after: end) }
        if end > range.upperBound, let build = Int(name[range.upperBound..<end]) {
          return build
        }
        searchFrom = range.upperBound
      }
    }
    return nil
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

  @MainActor
  private static func presentSimpleAlert(from viewController: UIViewController, title: String, message: String) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确定", style: .default))
    viewController.present(alert, animated: true)
  }
}
