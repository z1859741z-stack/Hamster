//
//  File.swift
//
//
//  Created by morse on 2023/7/4.
//

import Foundation

public enum AppInfo {
  static let infoDictionary = Bundle.main.infoDictionary ?? [:]

  public static let appVersion: String = {
    Self.displayVersion(
      version: Self.infoDictionary["CFBundleShortVersionString"] as? String,
      build: Self.infoDictionary["CFBundleVersion"] as? String,
      commit: Self.infoDictionary["HamsterGitCommit"] as? String
    )
  }()

  /// Keep absent local-build metadata explicit rather than inventing a commit.
  public static func displayVersion(version: String?, build: String?, commit: String?) -> String {
    let version = (version?.isEmpty == false) ? version! : "未知"
    let build = (build?.isEmpty == false) ? build! : "未知"
    let commit = (commit?.isEmpty == false && commit?.contains("$(") == false) ? commit! : "未知"
    return "版本 \(version) · 构建 \(build) · 提交 \(commit)"
  }

  public static let rimeVersion: String = {
    Self.infoDictionary["rimeVersion"] as? String ?? ""
  }()
}
