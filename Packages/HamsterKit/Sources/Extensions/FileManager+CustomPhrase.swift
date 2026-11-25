import Foundation

/// 常用语（RIME custom_phrase）的文件接线。
///
/// RIME 侧的 custom_phrase 翻译器是 stabledb：直接读一个 .txt 文件，
/// 引擎按 user_data_dir → shared_data_dir 的顺序解析（见 librime service.cc
/// CreateResourceResolver：root 是 user_data_dir，fallback 是 shared_data_dir）。
/// 所以词条文件要同时出现在主 App 沙盒的 SharedSupport 与 userData 两处：
/// 无完全访问时键盘的 user_data_dir 是键盘自己沙盒（没有这文件），
/// 引擎回落到组 SharedSupport（键盘的 shared_data_dir）；有完全访问时
/// 键盘的 user_data_dir 就是组 Rime/，主 App userData 同步过去的那份生效。
public extension FileManager {
  /// 常用语 JSON（源数据）的路径：App Group 的 InputSchema 目录。
  static var customPhrasesJSONURL: URL {
    shareURL.appendingPathComponent("custom_phrases.json")
  }

  /// 按组里的 custom_phrases.json 重新生成 custom_phrase.txt。
  /// 以刚解压的内置文件为底（保留雾凇自带的短语），把用户词条追加在后；
  /// 写到主 App 沙盒的 SharedSupport 与 userData 两处，覆盖内置文件。
  /// 没有词条文件或词条为空时什么都不做（保留内置文件）。
  /// 只动主 App 沙盒，不碰键盘沙盒的 Rime/（词频不丢）。
  /// 调用方：deployment()（SharedSupport 刚刷新完之后）、restRime()。
  static func regenerateCustomPhraseFile() throws {
    let snapshot: OfflineKeyboardSnapshot
    do {
      snapshot = try OfflineKeyboardSnapshotReader(fileURL: customPhrasesJSONURL).read()
    } catch {
      // 没有常用语文件：保留内置 custom_phrase.txt。
      return
    }
    // 界面要求每条都有缩写；code 为空的条目写进 txt 也会被 RIME 跳过，这里直接滤掉。
    let userLines = snapshot.entries.compactMap { entry -> String? in
      guard let code = entry.code, !code.isEmpty else { return nil }
      // txt 格式：内容<Tab>缩写。快照已保证内容与缩写里没有控制字符（含 Tab/换行）。
      return "\(entry.text)\t\(code)"
    }
    guard !userLines.isEmpty else { return }

    let fileName = "custom_phrase.txt"
    // 底本只从 SharedSupport 取：deployment() 与 restRime() 在调这里之前
    // 都刚刷新过 SharedSupport，那份一定是干净的内置文件。
    // 不能拿各目录现有的文件当底本——userData 那份部署时不会被刷新，
    // 里面已经有上一轮追加的用户词条，再 append 一次就会越部署越多。
    let stockURL = sandboxSharedSupportDirectory.appendingPathComponent(fileName)
    var stock: String
    if let content = try? String(contentsOf: stockURL, encoding: .utf8), !content.isEmpty {
      stock = content
    } else {
      stock = "# Rime table\n# coding: utf-8\n#\n# 此行之后不能写注释\n"
    }
    if !stock.hasSuffix("\n") { stock += "\n" }
    let content = stock + userLines.joined(separator: "\n") + "\n"
    for directory in [sandboxSharedSupportDirectory, sandboxUserDataDirectory] {
      try content.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
    }
  }
}
