//
//  File.swift
//
//
//  Created by morse on 2023/7/4.
//

import CommonCrypto
import Foundation
import os
import ZIPFoundation

/// FileManager 扩展
public extension FileManager {
  /// 创建文件夹
  /// override: 当目标文件夹存在时，是否覆盖
  /// dst: 目标文件夹URL
  static func createDirectory(override: Bool = false, dst: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: dst.path) {
      if override {
        try fm.removeItem(atPath: dst.path)
      } else {
        return
      }
    }
    try fm.createDirectory(
      at: dst,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  /// 拷贝文件夹
  /// override: 当目标文件夹存在时，是否覆盖
  /// src: 拷贝源 URL
  /// dst: 拷贝地址 URL
  static func copyDirectory(override: Bool = false, src: URL, dst: URL) throws {
    // 源和目标是同一目录时直接返回：否则 override 会先删掉目标，
    // 也就是把源自己删了（App Group 不可用退回沙盒时会出现这种情况）。
    guard src.standardizedFileURL != dst.standardizedFileURL else { return }
    let fm = FileManager.default
    if fm.fileExists(atPath: dst.path) {
      if override {
        try fm.removeItem(atPath: dst.path)
      } else {
        return
      }
    }

    if !fm.fileExists(atPath: dst.deletingLastPathComponent().path) {
      try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    try fm.copyItem(at: src, to: dst)
  }

  /// 增量复制
  /// 增量是指文件名相同且内容相同的文件会跳过，如果是目录，则会比较目录下的内容
  /// filterRegex: 正则表达式，用来过滤复制的文件，true: 需要过滤
  /// filterMatchBreak: 匹配后是否跳过 true 表示跳过匹配文件, 只拷贝非匹配的文件 false 表示只拷贝匹配文件
  static func incrementalCopy(
    src: URL,
    dst: URL,
    filterRegex: [String] = [],
    filterMatchBreak: Bool = true,
    override: Bool = true
  ) throws {
    let fm = FileManager.default
    // 递归获取全部文件
    guard let srcFiles = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
    guard let dstFiles = fm.enumerator(at: dst, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

    let dstFilesMapping = dstFiles.allObjects.compactMap { $0 as? URL }.reduce(into: [String: URL]()) { $0[$1.path.replacingOccurrences(of: dst.path, with: "")] = $1 }
    let srcPrefix = src.path

    while let file = srcFiles.nextObject() as? URL {
      // 正则过滤: true 表示正则匹配成功，false 表示没有匹配正则
      let match = !(filterRegex.first(where: { file.path.isMatch(regex: $0) }) ?? "").isEmpty

      // 匹配且需要跳过匹配项, 这是过滤的默认行为
      if match, filterMatchBreak {
        Logger.statistics.debug("filter filterRegex: \(filterRegex), filterMatchBreak: \(filterMatchBreak), file: \(file.path)")
        continue
      }

      // 不匹配且设置了不跳过匹配项，这是反向过滤行为，即只copy匹配过滤项文件
      if !filterRegex.isEmpty, !match, !filterMatchBreak {
        Logger.statistics.debug("filter filterRegex: \(filterRegex), match: \(match), filterMatchBreak: \(filterMatchBreak), file: \(file.path)")
        continue
      }

      let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      let relativePath = file.path.hasPrefix(srcPrefix) ? file.path.replacingOccurrences(of: srcPrefix, with: "") : file.path.replacingOccurrences(of: "/private" + srcPrefix, with: "")

      let dstFile = dstFilesMapping[relativePath] ?? dst.appendingPathComponent(relativePath, isDirectory: isDirectory)

      if fm.fileExists(atPath: dstFile.path) {
        // 目录不比较内容
        if isDirectory {
          continue
        }

        if fm.contentsEqual(atPath: file.path, andPath: dstFile.path) {
          continue // 文件已存在, 且内容相同，跳过
        }

        if override {
          try fm.removeItem(at: dstFile)
        }
      }

      if !fm.fileExists(atPath: dstFile.deletingLastPathComponent().path) {
        try FileManager.createDirectory(dst: dstFile.deletingLastPathComponent())
      }

      if isDirectory {
        try FileManager.createDirectory(dst: dstFile)
        continue
      }

      Logger.statistics.debug("incrementalCopy copy file: \(file.path) dst: \(dstFile.path)")
      try fm.copyItem(at: file, to: dstFile)
    }
  }
}

// MARK: zip/unzip

/// 添加 zip/unzip 逻辑
public extension FileManager {
  func unzip(_ data: Data, dst: URL) async throws {
    let tempZipURL = temporaryDirectory.appendingPathComponent("temp.zip")
    if fileExists(atPath: tempZipURL.path) {
      try removeItem(at: tempZipURL)
    }
    createFile(atPath: tempZipURL.path, contents: data)
    try await unzip(tempZipURL, dst: dst)
  }

  // 返回值
  // Bool 处理是否成功
  // Error: 处理失败的Error
  func unzip(_ zipURL: URL, dst: URL) async throws {
    var tempURL = zipURL

    // 检测是否为iCloudURL, 需要特殊处理
    if zipURL.path.contains("com~apple~CloudDocs") || zipURL.path.contains("iCloud~dev~fuxiao~app~hamsterapp") {
      // iCloud中的URL须添加安全访问资源语句，否则会异常：Operation not permitted
      // startAccessingSecurityScopedResource与stopAccessingSecurityScopedResource必须成对出现
      if !zipURL.startAccessingSecurityScopedResource() {
        throw "Zip文件读取权限受限"
      }

      let tempPath = temporaryDirectory.appendingPathComponent(zipURL.lastPathComponent)

      // 临时文件如果存在需要先删除
      if fileExists(atPath: tempPath.path) {
        try removeItem(at: tempPath)
      }

      try copyItem(atPath: zipURL.path, toPath: tempPath.path)

      // 停止读取url文件
      zipURL.stopAccessingSecurityScopedResource()

      tempURL = tempPath
    }

    // 读取ZIP内容
    guard let archive = Archive(url: tempURL, accessMode: .read) else {
      throw "读取Zip文件异常"
    }

    // 解压缩文件，已存在文件先删除在解压
    for entry in archive {
      let destinationEntryURL = dst.appendingPathComponent(entry.path)
      if fileExists(atPath: destinationEntryURL.path) {
        try removeItem(at: destinationEntryURL)
      }
      _ = try archive.extract(entry, to: destinationEntryURL, skipCRC32: true)
    }

    // 不在判断是否包含 schema 文件
    // 查找解压的文件夹里有没有名字包含schema.yaml 的文件
    // guard let _ = archive.filter({ $0.path.contains("schema.yaml") }).first else {
    //  throw "Zip文件未包含输入方案文件"
    // }

    // 解压前先删除原Rime目录
    // try removeItem(at: dst)
    // try unzipItem(at: tempURL, to: dst)
  }
}

// MARK: rime tempBackup

public extension FileManager {
  static var tempBackupDirectory: URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("HamsterBackup")
  }

  static var tempSharedSupportDirectory: URL {
    tempBackupDirectory.appendingPathComponent("RIME").appendingPathComponent(HamsterConstants.rimeSharedSupportPathName)
  }

  static var tempUserDataDirectory: URL {
    tempBackupDirectory.appendingPathComponent("RIME").appendingPathComponent(HamsterConstants.rimeUserPathName)
  }

  static var tempAppConfigurationYaml: URL {
    tempBackupDirectory.appendingPathComponent("hamster.yaml")
  }

  static var tempSwipePlist: URL {
    tempBackupDirectory.appendingPathComponent("swipe.plist")
  }
}

// MARK: SHA256

public extension FileManager {
  /// 计算文件 SHA256 的值
  func sha256(filePath path: String) -> String {
    guard let fileHandle = FileHandle(forReadingAtPath: path) else { return "" }
    defer { fileHandle.closeFile() }

    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    let bufferSize = 1024 * 1024
    while autoreleasepool(invoking: {
      let data = fileHandle.readData(ofLength: bufferSize)
      if !data.isEmpty {
        data.withUnsafeBytes { ptr in
          _ = CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(data.count))
        }
        return true
      } else {
        return false
      }
    }) {}

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)

    return hash.map { String(format: "%02hhx", $0) }.joined()
  }
}

// MARK: 应用内文件路径及操作

public extension FileManager {
  // AppGroup共享目录
  // 注意：AppGroup已变为Keyboard复制方案使用的中转站
  // App内部使用位置在沙盒 Documents 下
  static var shareURL: URL {
    // 运行时自动选组：先试写死的组，再按字母序试描述文件里的组，
    // 取第一个 containerURL 非 nil 的；全失败才退回沙盒。
    // 主 App 与键盘扩展用同一套逻辑，选到同一个组。
    if let groupURL = AppGroupResolver.resolvedGroupURL {
      return groupURL.appendingPathComponent("InputSchema")
    }
    Logger.statistics.warning("App Group 不可用，已退回沙盒目录部署；候选：\(AppGroupResolver.candidateGroups)")
    return sandboxDirectory
  }

  static var sandboxDirectory: URL {
    if let url = try? FileManager.default
      .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
      return url
    }
    return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
  }

  // AppGroup共享下: SharedSupport目录
  static var appGroupSharedSupportDirectoryURL: URL {
    shareURL.appendingPathComponent(
      HamsterConstants.rimeSharedSupportPathName, isDirectory: true
    )
  }

  // AppGroup共享下: userData目录
  static var appGroupUserDataDirectoryURL: URL {
    shareURL.appendingPathComponent(
      HamsterConstants.rimeUserPathName, isDirectory: true
    )
  }

  // 沙盒 Document 目录下备份目录
  static var appGroupBackupDirectory: URL {
    shareURL.appendingPathComponent("backups", isDirectory: true)
  }

  // AppGroup共享下：userData目录下: default.custom.yaml文件路径
  static var appGroupUserDataDefaultCustomYaml: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("default.custom.yaml")
  }

  // Sandbox下：userData目录下: default.custom.yaml文件路径
  static var sandboxUserDataDefaultCustomYaml: URL {
    sandboxUserDataDirectory.appendingPathComponent("default.custom.yaml")
  }

  // AppGroup共享下：userData目录下: installation.yaml文件路径
  static var appGroupInstallationYaml: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("installation.yaml")
  }

  // Sandbox下：userData目录下: installation.yaml文件路径
  static var sandboxInstallationYaml: URL {
    sandboxUserDataDirectory.appendingPathComponent("installation.yaml")
  }

  /// Sandbox/SharedSupport/hamster.yaml 文件
  static var hamsterConfigFileOnSandboxSharedSupport: URL {
    sandboxSharedSupportDirectory.appendingPathComponent("hamster.yaml")
  }

  /// Sandbox/Rime/hamster.yaml 文件
  static var hamsterConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.yaml")
  }

  /// Sandbox/Rime/hamster.custom.yaml 文件
  static var hamsterPatchConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.custom.yaml")
  }

  /// Sandbox/Rime/hamster.app.yaml 文件
  /// 用于存储应用配置
  /// 注意：此文件已废弃，应用操作产生的配置存储在 UserDefaults 中
  static var hamsterAppConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.app.yaml")
  }

  /// Sandbox/Rime/hamster.all.yaml 文件
  static var hamsterAllConfigFileOnUserData: URL {
    sandboxUserDataDirectory.appendingPathComponent("hamster.all.yaml")
  }

  /// Sandbox/Rime/build/hamster.yaml 文件
  static var hamsterConfigFileOnBuild: URL {
    sandboxUserDataDirectory.appendingPathComponent("/build/hamster.yaml")
  }

  /// AppGroup/Rime/build/hamster.yaml 文件
  static var hamsterConfigFileOnAppGroupBuild: URL {
    appGroupUserDataDirectoryURL.appendingPathComponent("/build/hamster.yaml")
  }

  // 沙盒 Document 目录下 ShareSupport 目录
  static var sandboxSharedSupportDirectory: URL {
    sandboxDirectory
      .appendingPathComponent(HamsterConstants.rimeSharedSupportPathName, isDirectory: true)
  }

  // 沙盒 Document 目录下 userData 目录
  static var sandboxUserDataDirectory: URL {
    sandboxDirectory
      .appendingPathComponent(HamsterConstants.rimeUserPathName, isDirectory: true)
  }

  // 沙盒 Document 目录下备份目录
  static var sandboxBackupDirectory: URL {
    sandboxDirectory.appendingPathComponent("backups", isDirectory: true)
  }

  // 沙盒 Document 目录下日志目录
  static var sandboxRimeLogDirectory: URL {
    sandboxDirectory.appendingPathComponent("RIMELogger", isDirectory: true)
  }

  // 安装包ShareSupport资源目录
  static var appSharedSupportDirectory: URL {
    Bundle.main.bundleURL
      .appendingPathComponent(
        HamsterConstants.rimeSharedSupportPathName, isDirectory: true
      )
  }

  /// 初始 AppGroup 共享目录下SharedSupport目录资源
  static func initAppGroupSharedSupportDirectory(override: Bool = false) throws {
    try initSharedSupportDirectory(override: override, dst: appGroupSharedSupportDirectoryURL)
  }

  /// 初始沙盒目录下 SharedSupport 目录资源
  static func initSandboxSharedSupportDirectory(override: Bool = false) throws {
    try initSharedSupportDirectory(override: override, dst: sandboxSharedSupportDirectory)
  }

  // 初始化 SharedSupport 目录资源
  private static func initSharedSupportDirectory(override: Bool = false, dst: URL) throws {
    let fm = FileManager()
    if fm.fileExists(atPath: dst.path) {
      if override {
        try fm.removeItem(atPath: dst.path)
      } else {
        return
      }
    }

    if !fm.fileExists(atPath: dst.path) {
      try fm.createDirectory(at: dst, withIntermediateDirectories: true, attributes: nil)
    }

    let src = appSharedSupportDirectory.appendingPathComponent(HamsterConstants.inputSchemaZipFile)

    guard fm.fileExists(atPath: src.path) else {
      throw "缺少内置方案：\(src.lastPathComponent) 不存在，请重新安装 App"
    }

    Logger.statistics.debug("unzip src: \(src), dst: \(dst)")

    // 解压缩输入方案zip文件
    try fm.unzipItem(at: src, to: dst)
  }

  // 初始化 AppGroup 共享目录下 UserData 目录资源
  static func initAppGroupUserDataDirectory(override: Bool = false) throws {
    try FileManager.createDirectory(
      override: override, dst: appGroupUserDataDirectoryURL
    )
  }

  // 初始化沙盒目录下 UserData 目录资源
  static func initSandboxUserDataDirectory(override: Bool = false, unzip: Bool = false) throws {
    try FileManager.createDirectory(
      override: override, dst: sandboxUserDataDirectory
    )

    if unzip {
      let src = appSharedSupportDirectory.appendingPathComponent(HamsterConstants.userDataZipFile)

      guard FileManager.default.fileExists(atPath: src.path) else {
        throw "缺少内置方案：\(src.lastPathComponent) 不存在，请重新安装 App"
      }

      // 解压缩输入方案zip文件
      try FileManager.default.unzipItem(at: src, to: sandboxUserDataDirectory)
    }
  }

  /// 初始化沙盒目录下 Backup 目录
  static func initSandboxBackupDirectory(override: Bool = false) throws {
    try FileManager.createDirectory(
      override: override, dst: sandboxBackupDirectory
    )
  }

  // 同步 AppGroup 共享目录下SharedSupport目录至沙盒目录
  static func syncAppGroupSharedSupportDirectoryToSandbox(override: Bool = false) throws {
    Logger.statistics.info("rime syncAppGroupSharedSupportDirectory: override \(override)")
    try FileManager.copyDirectory(override: override, src: appGroupSharedSupportDirectoryURL, dst: sandboxSharedSupportDirectory)
  }

  // 同步 AppGroup 共享目录下 UserData 目录至沙盒目录
  static func syncAppGroupUserDataDirectoryToSandbox(override: Bool = false) throws {
    Logger.statistics.info("rime syncAppGroupUserDataDirectory: override \(override)")
    try FileManager.copyDirectory(override: override, src: appGroupUserDataDirectoryURL, dst: sandboxUserDataDirectory)
  }

  // 同步 Sandbox 目录下 SharedSupport 目录至 AppGroup 目录
  static func syncSandboxSharedSupportDirectoryToAppGroup(override: Bool = false) throws {
    Logger.statistics.info("rime syncSandboxSharedSupportDirectoryToApGroup: override \(override)")
    try FileManager.copyDirectory(override: override, src: sandboxSharedSupportDirectory, dst: appGroupSharedSupportDirectoryURL)
  }

  /// 分块算一个文件的 SHA-256（不把整个文件读进内存，373 MB 的模型也能算）。
  static func sha256Hex(of url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)
    while true {
      guard let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
      chunk.withUnsafeBytes { CC_SHA256_Update(&context, $0.baseAddress, CC_LONG(chunk.count)) }
    }
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&digest, &context)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// 将沙盒 SharedSupport 同步到 App Group，但保留组里已有的语法模型文件。
  /// 其余文件与 copyDirectory(override: true) 的终态一致：组里多余的旧文件会被
  /// 清掉，沙盒里新增或改动的文件会被拷过去；只有 .gram 不参与这次同步，
  /// 由 syncGrammarModelToAppGroupIfNeeded 单独按 sha256 门控处理。
  static func syncSandboxSharedSupportDirectoryToAppGroupPreservingGrammar() throws {
    let fm = FileManager.default
    let src = sandboxSharedSupportDirectory
    let dst = appGroupSharedSupportDirectoryURL
    guard src.standardizedFileURL != dst.standardizedFileURL else { return }
    if !fm.fileExists(atPath: dst.path) {
      try fm.createDirectory(at: dst, withIntermediateDirectories: true)
    }
    // 清掉组里除语法模型外的全部旧内容（与 override 语义一致）。
    if let items = try? fm.contentsOfDirectory(atPath: dst.path) {
      for item in items where item != HamsterConstants.grammarModelFileName {
        try fm.removeItem(at: dst.appendingPathComponent(item))
      }
    }
    // 增量拷：内容相同的文件跳过；.gram 不参与。
    let gramPattern = NSRegularExpression.escapedPattern(for: HamsterConstants.grammarModelFileName) + "$"
    try FileManager.incrementalCopy(src: src, dst: dst, filterRegex: [gramPattern], filterMatchBreak: true)
  }

  /// 将语法模型（万象 .gram）同步到 App Group：只在组里缺失或 sha256 变了才拷；
  /// 关掉开关时删掉组里的模型。键盘直接读组里的路径，绝不复制进键盘沙盒。
  static func syncGrammarModelToAppGroupIfNeeded(enabled: Bool) throws {
    let fm = FileManager.default
    let src = sandboxSharedSupportDirectory.appendingPathComponent(HamsterConstants.grammarModelFileName)
    let dst = appGroupSharedSupportDirectoryURL.appendingPathComponent(HamsterConstants.grammarModelFileName)
    guard src.standardizedFileURL != dst.standardizedFileURL else { return }
    if !enabled {
      if fm.fileExists(atPath: dst.path) {
        Logger.statistics.info("rime grammar model disabled, removing from App Group")
        try fm.removeItem(at: dst)
      }
      return
    }
    guard fm.fileExists(atPath: src.path) else {
      Logger.statistics.warning("rime grammar model missing in sandbox SharedSupport, skipping sync")
      return
    }
    if fm.fileExists(atPath: dst.path),
       let srcHash = sha256Hex(of: src), let dstHash = sha256Hex(of: dst), srcHash == dstHash {
      Logger.statistics.info("rime grammar model already in App Group with same sha256, skipping copy")
      return
    }
    if fm.fileExists(atPath: dst.path) {
      try fm.removeItem(at: dst)
    }
    Logger.statistics.info("rime copying grammar model to App Group")
    try fm.copyItem(at: src, to: dst)
  }

  // 同步 Sandbox 目录下 UserData 目录至 AppGroup 目录
  static func syncSandboxUserDataDirectoryToAppGroup(override: Bool = false) throws {
    Logger.statistics.info("rime syncSandboxUserDataDirectoryToApGroup: override \(override)")
    try FileManager.copyDirectory(override: override, src: sandboxUserDataDirectory, dst: appGroupUserDataDirectoryURL)
  }

  /// 将组里主 App 部署好的 RIME 产物同步到键盘沙盒（仅键盘无完全访问时用）。
  /// 只读组目录：同步 build/（已编译的 .bin）、installation.yaml、default.custom.yaml；
  /// 不碰 user.yaml 与 *.userdb，键盘本地的学习数据留在沙盒。
  /// 组不可用时 shareURL 已退回沙盒，src == dst，直接返回。
  /// 用键盘本地签名判断是否需要同步，不依赖共享标记。
  /// 返回是否真的拷过文件：主 App 重新部署后 build、installation.yaml 或
  /// default.custom.yaml 的时间戳变了才拷，调用方据此决定要不要重启引擎。
  /// 注意：只比较 build 目录不够——换方案只改 default.custom.yaml，build 未必变，
  /// 那两个 yaml 也必须放进签名，否则换方案后键盘永远收不到。
  @discardableResult
  static func syncAppGroupRimeBuildToSandbox() throws -> Bool {
    let fm = FileManager.default
    let srcUserDir = appGroupUserDataDirectoryURL
    let dstUserDir = sandboxUserDataDirectory
    guard srcUserDir.standardizedFileURL != dstUserDir.standardizedFileURL else { return false }

    let srcBuild = srcUserDir.appendingPathComponent("build", isDirectory: true)
    guard fm.fileExists(atPath: srcBuild.path) else {
      throw "组里没有已部署的 RIME 产物（缺少 Rime/build），请先在主 App 里重新部署"
    }

    let signatureKey = "hamster.keyboard.rimeBuildSignature"
    let dstBuild = dstUserDir.appendingPathComponent("build", isDirectory: true)
    let dstHasBin = (try? fm.contentsOfDirectory(atPath: dstBuild.path))?.contains { $0.hasSuffix(".bin") } ?? false
    if let signature = buildSignature(of: srcUserDir),
       UserDefaults.standard.string(forKey: signatureKey) == signature, dstHasBin {
      return false
    }

    try copyDirectory(override: true, src: srcBuild, dst: dstBuild)
    for name in ["installation.yaml", "default.custom.yaml"] {
      let src = srcUserDir.appendingPathComponent(name)
      let dst = dstUserDir.appendingPathComponent(name)
      guard fm.fileExists(atPath: src.path) else { continue }
      if fm.fileExists(atPath: dst.path), fm.contentsEqual(atPath: src.path, andPath: dst.path) { continue }
      if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
      try fm.copyItem(at: src, to: dst)
    }
    if let signature = buildSignature(of: srcUserDir) {
      UserDefaults.standard.set(signature, forKey: signatureKey)
    }
    return true
  }

  /// 部署产物的本地签名：build 下每个文件的相对路径、大小、修改时间，
  /// 加上 installation.yaml 与 default.custom.yaml 的大小、修改时间。
  private static func buildSignature(of userDir: URL) -> String? {
    let fm = FileManager.default
    let buildDir = userDir.appendingPathComponent("build", isDirectory: true)
    guard let names = try? fm.contentsOfDirectory(atPath: buildDir.path) else { return nil }
    var parts: [String] = []
    for name in names.sorted() {
      guard let attrs = try? fm.attributesOfItem(atPath: buildDir.appendingPathComponent(name).path) else { continue }
      let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
      let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
      parts.append("\(name):\(size):\(Int(mtime))")
    }
    for name in ["installation.yaml", "default.custom.yaml"] {
      guard let attrs = try? fm.attributesOfItem(atPath: userDir.appendingPathComponent(name).path) else { continue }
      let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
      let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
      parts.append("\(name):\(size):\(Int(mtime))")
    }
    return parts.joined(separator: "|")
  }

  /// 拷贝 Sandbox 下 SharedSupport 目录至 AppGroup 下 SharedSupport 目录
  static func copySandboxSharedSupportDirectoryToAppGroup(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copySandboxSharedSupportDirectoryToAppGroupSharedSupportDirectory: fileRegex \(filterRegex)")
    try FileManager.incrementalCopy(src: sandboxSharedSupportDirectory, dst: appGroupSharedSupportDirectoryURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 Sandbox 下 UserData 目录至 AppGroup 下 UserData 目录
  static func copySandboxUserDataDirectoryToAppGroup(_ filterRegex: [String] = [], filterMatchBreak: Bool = true) throws {
    Logger.statistics.info("rime copySandboxUserDataDirectoryToAppGroupUserDirectory: filterRegex \(filterRegex)")
    try FileManager.incrementalCopy(src: sandboxUserDataDirectory, dst: appGroupUserDataDirectoryURL, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak)
  }

  /// 拷贝 AppGroup 下 SharedSupport 目录至 sandbox 下 SharedSupport 目录
  static func copyAppGroupSharedSupportDirectoryToSandbox(_ filterRegex: [String] = [], filterMatchBreak: Bool = true, override: Bool = true) throws {
    Logger.statistics.info("rime copyAppGroupSharedSupportDirectoryToSandboxSharedSupportDirectory")
    try FileManager.incrementalCopy(src: appGroupSharedSupportDirectoryURL, dst: sandboxSharedSupportDirectory, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak, override: override)
  }

  /// 拷贝 AppGroup 下 UserData 目录至 sandbox 下 UserData 目录
  static func copyAppGroupUserDirectoryToSandbox(_ filterRegex: [String] = [], filterMatchBreak: Bool = true, override: Bool = true) throws {
    Logger.statistics.info("rime copyAppGroupUserDirectoryToSandboxUserDataDirectory:")
    try FileManager.incrementalCopy(src: appGroupUserDataDirectoryURL, dst: sandboxUserDataDirectory, filterRegex: filterRegex, filterMatchBreak: filterMatchBreak, override: override)
  }

  /// 拷贝 AppGroup 下词库文件
  static func copyAppGroupUserDict(_ regex: [String] = []) throws {
    // TODO: 将AppGroup下词库文件copy至应用目录
    // 只copy用户词库文件
    // let regex = ["^.*[.]userdb.*$", "^.*[.]txt$"]
    // let regex = ["^.*[.]userdb.*$"]
    try copyAppGroupSharedSupportDirectoryToSandbox(regex, filterMatchBreak: false)
    try copyAppGroupUserDirectoryToSandbox(regex, filterMatchBreak: false)
  }
}
