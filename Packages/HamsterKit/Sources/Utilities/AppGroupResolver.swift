//
//  AppGroupResolver.swift
//
//  运行时自动选 App Group：重签证书不带原 group 时，主 App 与键盘扩展
//  各自读自己 bundle 里的 embedded.mobileprovision，从描述文件的
//  application-groups 里挑一个真正能用的组，保证两端选到同一个组。
//  全都失败才退回沙盒方案（见 FileManager.shareURL）。
//

import Foundation
import OSLog

/// 运行时 App Group 选择器（主 App 与键盘扩展共用，HamsterKit 内）。
public enum AppGroupResolver {
  /// 写死的首选组名（原 entitlements 里的组）。
  public static let preferredGroupName = HamsterConstants.appGroupName

  /// 描述文件里声明的组（embedded.mobileprovision → Entitlements → com.apple.security.application-groups）。
  /// 没有描述文件（如模拟器 / 本地直编）时为空。
  public static var provisionedGroups: [String] {
    readProvisionedGroups()
  }

  /// 候选顺序：写死的组优先，其余按字母排序、去重。
  public static var candidateGroups: [String] {
    var candidates = [preferredGroupName]
    for group in provisionedGroups.sorted() where group != preferredGroupName {
      candidates.append(group)
    }
    return candidates
  }

  /// 选中的组（名 + 容器 URL），进程内只算一次。
  /// 逐个试 containerURL，取第一个非 nil 的。
  private static let resolved: (name: String, url: URL)? = {
    for name in candidateGroups {
      if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: name) {
        Logger.statistics.info("App Group 已选：\(name)")
        return (name, url)
      }
    }
    Logger.statistics.warning("无可用 App Group，已退回沙盒；候选：\(candidateGroups)")
    return nil
  }()

  /// 选中的组名；全失败时为 nil（退回沙盒）。
  public static var resolvedGroupName: String? {
    resolved?.name
  }

  /// 选中的组容器 URL；全失败时为 nil（退回沙盒）。
  public static var resolvedGroupURL: URL? {
    resolved?.url
  }

  /// 是否有可用组。
  public static var isAvailable: Bool {
    resolved != nil
  }

  /// 关于页展示用：组名 + 是否可用。
  public static var displayText: String {
    if let name = resolved?.name {
      return "\(name)（可用）"
    }
    return "不可用，已退回沙盒"
  }

  /// 读 Bundle.main 里的 embedded.mobileprovision（CMS 包着的 plist，
  /// 截取 <?xml 到 </plist> 解析），取 Entitlements 里的 application-groups。
  /// 扩展读的是自己 bundle 里的描述文件，与主 App 用同一套逻辑。
  private static func readProvisionedGroups() -> [String] {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url),
          let xmlStart = data.range(of: Data("<?xml".utf8)),
          let xmlEnd = data.range(of: Data("</plist>".utf8))
    else {
      return []
    }
    let plistData = data.subdata(in: xmlStart.lowerBound..<xmlEnd.upperBound)
    guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
          let entitlements = plist["Entitlements"] as? [String: Any],
          let groups = entitlements["com.apple.security.application-groups"] as? [String]
    else {
      return []
    }
    return groups
  }
}
