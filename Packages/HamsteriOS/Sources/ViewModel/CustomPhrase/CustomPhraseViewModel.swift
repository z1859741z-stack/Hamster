//
//  CustomPhraseViewModel.swift
//
//  常用语（RIME custom_phrase）：主 App 里增删改，JSON 存 App Group，
//  保存即自动触发 deployment()；键盘沿用现有的按 mtime 重检组产物，
//  下次弹出时重启引擎生效。
//  部署走 RIME 的 custom_phrase 翻译器（stabledb，直接读 custom_phrase.txt），
//  不走候选栏直出。部署不能碰键盘沙盒里的 userdb：deployment() 只写主 App
//  沙盒与组目录，键盘的 userdb 不在其中任何一步的写路径上。
//

import Combine
import Foundation
import HamsterKeyboardKit
import HamsterKit
import OSLog

public class CustomPhraseViewModel {
  public let rimeContext: RimeContext

  /// 当前词条（界面唯一事实来源；文件只在保存时读写）。
  public private(set) var entries: [OfflineKeyboardSnapshot.Entry] = []

  /// 部署状态文案，显示在页面底部。
  public private(set) var deployStatusText: String = "尚未部署。保存常用语后会自动部署。"

  private var reloadTableSubject = PassthroughSubject<Bool, Never>()
  public var reloadTablePublished: AnyPublisher<Bool, Never> {
    reloadTableSubject.eraseToAnyPublisher()
  }

  /// JSON 读改写的串行锁：防止两次保存交错读到同一个 snapshotVersion。
  private let saveLock = NSLock()

  /// 部署串行化：正在部署时再保存，只排队一次跟进部署（用最新文件）。
  private var deployTask: Task<Void, Never>?
  private var deployPending = false

  init(rimeContext: RimeContext) {
    self.rimeContext = rimeContext
    loadEntries()
  }

  /// 从组里读 JSON；没有文件时视为空列表。
  func loadEntries() {
    do {
      let snapshot = try OfflineKeyboardSnapshotReader(fileURL: FileManager.customPhrasesJSONURL).read()
      entries = snapshot.entries
    } catch {
      let nsError = error as NSError
      let missing = (nsError.domain == NSCocoaErrorDomain &&
                     (nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError)) ||
                    (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(POSIXErrorCode.ENOENT.rawValue))
      if !missing {
        Logger.statistics.error("load custom phrases error: \(error.localizedDescription)")
      }
      entries = []
    }
  }

  // MARK: - 增删改（保存即自动部署）

  /// 缩写只允许小写字母和数字（RIME 编码）；界面输入会自动转小写。
  static func normalizedCode(_ code: String) -> String? {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty,
          normalized.unicodeScalars.allSatisfy({ $0.isASCII && ($0.value >= 97 && $0.value <= 122 || $0.value >= 48 && $0.value <= 57) })
    else { return nil }
    return normalized
  }

  func addEntry(code: String, text: String) async throws {
    guard let normalizedCode = Self.normalizedCode(code) else {
      throw CustomPhraseError.invalidCode
    }
    let entry = try OfflineKeyboardSnapshot.Entry(text: text, code: normalizedCode)
    var newEntries = entries
    newEntries.append(entry)
    try persistEntries(newEntries)
    entries = newEntries
    requestDeploy()
  }

  func updateEntry(at index: Int, code: String, text: String) async throws {
    guard entries.indices.contains(index) else { return }
    guard let normalizedCode = Self.normalizedCode(code) else {
      throw CustomPhraseError.invalidCode
    }
    let entry = try OfflineKeyboardSnapshot.Entry(text: text, code: normalizedCode)
    var newEntries = entries
    newEntries[index] = entry
    try persistEntries(newEntries)
    entries = newEntries
    requestDeploy()
  }

  func deleteEntry(at index: Int) async {
    guard entries.indices.contains(index) else { return }
    var newEntries = entries
    newEntries.remove(at: index)
    do {
      try persistEntries(newEntries)
      entries = newEntries
    } catch {
      Logger.statistics.error("delete custom phrase error: \(error.localizedDescription)")
      reloadTableSubject.send(true)
      return
    }
    requestDeploy()
  }

  /// 把保存时的错误翻译成给用户看的中文。
  static func errorMessage(for error: Error) -> String {
    if let customError = error as? CustomPhraseError {
      return customError.errorDescription ?? "保存失败。"
    }
    if let snapshotError = error as? OfflineKeyboardSnapshotError {
      switch snapshotError {
      case .invalidEntryText:
        return "内容不能为空，也不能超过 256 字节。"
      case .invalidEntryCode:
        return "缩写不能为空，也不能超过 128 字节。"
      case .duplicateEntry:
        return "已经有一条相同的常用语了。"
      case .tooManyEntries:
        return "常用语太多了，最多 4096 条。"
      case .payloadTooLarge:
        return "常用语数据太大了。"
      default:
        return "保存失败，请重试。"
      }
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  /// 手动重新部署（部署失败后重试用）。
  func redeploy() {
    requestDeploy()
  }

  // MARK: - 持久化

  /// 把词条写进组里的 custom_phrases.json（原子替换，snapshotVersion 递增）。
  /// 只写 JSON；custom_phrase.txt 由 deployment() 里统一生成。
  private func persistEntries(_ newEntries: [OfflineKeyboardSnapshot.Entry]) throws {
    saveLock.lock()
    defer { saveLock.unlock() }
    let previous: OfflineKeyboardSnapshot?
    do {
      previous = try OfflineKeyboardSnapshotReader(fileURL: FileManager.customPhrasesJSONURL).read()
    } catch {
      let nsError = error as NSError
      let missing = (nsError.domain == NSCocoaErrorDomain &&
                     (nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError)) ||
                    (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(POSIXErrorCode.ENOENT.rawValue))
      guard missing else { throw error }
      previous = nil
    }
    let snapshot = try OfflineKeyboardSnapshot(
      snapshotVersion: (previous?.snapshotVersion ?? 0) + 1,
      resetEpoch: previous?.resetEpoch ?? 0,
      entries: newEntries
    )
    try OfflineKeyboardSnapshotWriter(fileURL: FileManager.customPhrasesJSONURL).write(snapshot)
  }

  // MARK: - 自动部署（串行 + 合并）

  private func requestDeploy() {
    if deployTask != nil {
      deployPending = true
      return
    }
    deployTask = Task { [weak self] in
      await self?.runDeployLoop()
    }
  }

  private func runDeployLoop() async {
    while true {
      let start = Date()
      await MainActor.run {
        self.deployStatusText = "正在部署，请稍候……"
        self.reloadTableSubject.send(true)
      }
      do {
        try await deployOnce()
        let elapsed = Date().timeIntervalSince(start)
        await MainActor.run {
          self.deployStatusText = String(format: "已部署，用时 %.1f 秒。键盘下次弹出时生效。", elapsed)
          self.reloadTableSubject.send(true)
        }
      } catch {
        Logger.statistics.error("custom phrase deploy error: \(error)")
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        await MainActor.run {
          self.deployStatusText = "部署失败：\(message)。可以点“重新部署”重试。"
          self.reloadTableSubject.send(true)
        }
      }
      if deployPending {
        deployPending = false
        continue
      }
      deployTask = nil
      return
    }
  }

  /// 跑一次 deployment()（后台线程，不卡界面），返回更新后的配置。
  /// 与 RIME 页的 rimeDeploy() 同一条部署路径，只是没有 ProgressHUD，
  /// 状态由本页底部文案显示。
  private func deployOnce() async throws {
    let configuration = HamsterAppDependencyContainer.shared.configuration
    let updated = try await Task.detached(priority: .userInitiated) { [rimeContext] in
      var config = configuration
      try rimeContext.deployment(configuration: &config)
      return config
    }.value
    HamsterAppDependencyContainer.shared.configuration = updated
  }
}

public enum CustomPhraseError: LocalizedError {
  case invalidCode

  public var errorDescription: String? {
    switch self {
    case .invalidCode:
      return "缩写只能用小写字母和数字，不能为空。"
    }
  }
}
