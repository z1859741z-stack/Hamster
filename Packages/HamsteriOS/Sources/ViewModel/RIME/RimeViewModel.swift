//
//  RimeViewModel.swift
//  Hamster
//
//  Created by morse on 2023/6/15.
//

import Combine
import Foundation
import HamsterKeyboardKit
import HamsterKit
import OSLog
import ProgressHUD
import UIKit

public class RimeViewModel {
  public let rimeContext: RimeContext

  private let rimeRestSubject = PassthroughSubject<() -> Void, Never>()
  public var rimeRestPublished: AnyPublisher<() -> Void, Never> {
    rimeRestSubject.eraseToAnyPublisher()
  }

  private let openRimeLoggerViewSubject = PassthroughSubject<Bool, Never>()
  public var openRimeLoggerViewPublished: AnyPublisher<Bool, Never> {
    openRimeLoggerViewSubject.eraseToAnyPublisher()
  }

  private lazy var stdoutHandle = FileHandle.standardOutput
  private lazy var readStderrPipe: Pipe = {
    let pipe = Pipe()
    setvbuf(stderr, nil, _IONBF, 0)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    return pipe
  }()

  deinit {
    try? stdoutHandle.close()
  }

  // 简繁切换键值
  public var keyValueOfSwitchSimplifiedAndTraditional: String {
    get {
      HamsterAppDependencyContainer.shared.configuration.rime?.keyValueOfSwitchSimplifiedAndTraditional ?? ""
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.rime?.keyValueOfSwitchSimplifiedAndTraditional = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.rime?.keyValueOfSwitchSimplifiedAndTraditional = newValue
    }
  }

  // 是否覆盖词库文件
  // 非造词用户保持默认值 true
  public var overrideDictFiles: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.rime?.overrideDictFiles ?? true
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.rime?.overrideDictFiles = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.rime?.overrideDictFiles = newValue
    }
  }

  // 是否启用语法模型（万象）。默认开；切换后要点「重新部署」才生效。
  public var grammarModelEnabled: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.rime?.grammarModelEnabled ?? true
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.rime?.grammarModelEnabled = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.rime?.grammarModelEnabled = newValue
    }
  }

  lazy var settings: [SettingSectionModel] = [
    .init(
      title: "简繁切换",
      footer: "配置文件中`switches`简繁转换选项的配置名称，仓用于中文简体与繁体之间快速切换。",
      items: [
        .init(
          icon: UIImage(systemName: "square.and.pencil"),
          placeholder: "简繁切换键值",
          type: .textField,
          textValue: { [unowned self] in keyValueOfSwitchSimplifiedAndTraditional },
          textHandled: { [unowned self] in
            keyValueOfSwitchSimplifiedAndTraditional = $0
          }
        ),
      ]
    ),
    .init(
      footer: "如果您未使用自造词功能，请保持保持默认开启状态。",
      items: [
        .init(
          text: "部署时覆盖键盘词库文件",
          type: .toggle,
          toggleValue: { [unowned self] in overrideDictFiles },
          toggleHandled: { [unowned self] in
            overrideDictFiles = $0
          }
        ),
      ]
    ),
    .init(
      footer: "语法模型（万象）参与整句断词与候选排序。切换后点下面的「重新部署」才生效；关掉可以与不带模型的效果对比。",
      items: [
        .init(
          text: "启用语法模型（万象）",
          type: .toggle,
          toggleValue: { [unowned self] in grammarModelEnabled },
          toggleHandled: { [unowned self] in
            grammarModelEnabled = $0
          }
        ),
      ]
    ),
    .init(
      items: [
        .init(
          text: "RIME 日志",
          accessoryType: .disclosureIndicator,
          type: .navigation,
          navigationAction: { [unowned self] in
            openRimeLoggerViewSubject.send(true)
          }
        ),
      ]
    ),
    .init(
      items: [
        .init(
          text: "重新部署",
          type: .button,
          buttonAction: { [unowned self] in
            Task {
              await rimeDeploy()
              reloadTableSubject.send(true)
            }
          },
          favoriteButton: .rimeDeploy
        ),
      ]
    ),
    .init(items: [
      .init(
        text: "RIME重置",
        textTintColor: .systemRed,
        type: .button,
        buttonAction: { [unowned self] in
          rimeRestSubject.send { [unowned self] in
            Task {
              await rimeRest()
              reloadTableSubject.send(true)
            }
          }
        }
      ),
    ]),
  ]

  private var reloadTableSubject = PassthroughSubject<Bool, Never>()
  public var reloadTablePublished: AnyPublisher<Bool, Never> {
    reloadTableSubject.eraseToAnyPublisher()
  }

  init(rimeContext: RimeContext) {
    self.rimeContext = rimeContext
  }
}

public extension RimeViewModel {
  /// RIME 日志记录
  private func rimeLogger() -> (FileHandle?, URL) {
    let fileName = DateFormatter.tempFileNameStyle.string(from: Date()) + ".log"
    let loggerDirectory = FileManager.sandboxRimeLogDirectory

    try? FileManager.createDirectory(override: false, dst: loggerDirectory)

    // 日志文件最多保存 10 个，排序删除最早的文件
    if let urls = try? FileManager.default.contentsOfDirectory(
      at: loggerDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ), urls.count >= 10, let url = urls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).last {
      try? FileManager.default.removeItem(at: url)
    }

    // 创建日志文件
    let filePath = loggerDirectory.appendingPathComponent(fileName)
    FileManager.default.createFile(atPath: filePath.path, contents: nil)
    let fileHandle = try? FileHandle(forWritingTo: filePath)

    // listening on the readabilityHandler
    readStderrPipe.fileHandleForReading.readabilityHandler = { [unowned self] handle in
      let data = handle.availableData
      try? fileHandle?.write(contentsOf: data)
      try? stdoutHandle.write(contentsOf: data)
    }

    return (fileHandle, filePath)
  }

  /// 关闭 RIME Logger 日志
  private func closeRimeLogger(_ fileHandle: FileHandle?) {
    readStderrPipe.fileHandleForReading.readabilityHandler = { [unowned self] handle in
      let data = handle.availableData
      try? stdoutHandle.write(contentsOf: data)
    }
    try? fileHandle?.close()
  }

  /// 检测 RIME Logger 日志是否存在异常
  func checkRimeLogger(_ fileURL: URL) async {
    var errorLines = [String]()
    guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else { return }
    guard let data = try? fileHandle.readToEnd() else { return }
    guard let str = String(data: data, encoding: .utf8) else { return }
    let lines = str.split(separator: "\n").map { String($0) }
    for (index, line) in lines.enumerated() {
      if line.isMatch(regex: ".*[1-9] failure.*") {
        errorLines.append("\(index + 1)")
      }
    }
    try? fileHandle.close()

    if !errorLines.isEmpty {
      await ProgressHUD.banner("RIME日志存在异常", "请检查 \(fileURL.lastPathComponent)，第 \(errorLines.joined(separator: ",")) 行。", delay: 5)
    }
  }

  /// RIME 部署
  func rimeDeploy() async {
    let (fileHandle, filePath) = rimeLogger()
    await ProgressHUD.animate("RIME部署中, 请稍候……", AnimationType.circleRotateChase, interaction: false)
    var hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration
    do {
      try rimeContext.deployment(configuration: &hamsterConfiguration)
      await checkRimeLogger(filePath)
      HamsterAppDependencyContainer.shared.configuration = hamsterConfiguration
      await ProgressHUD.success("部署成功", interaction: false, delay: 1.5)
    } catch {
      // try? FileHandle.standardError.write(contentsOf: error.localizedDescription.data(using: .utf8) ?? Data())
      Logger.statistics.error("rime deploy error: \(error)")
      await ProgressHUD.failed(error, interaction: false, delay: 5)
    }
    closeRimeLogger(fileHandle)
  }
  /// Rime重置
  func rimeRest() async {
    await ProgressHUD.animate("RIME重置中, 请稍候……", interaction: false)
    do {
      // 重置会把配置恢复默认（语法模型开关回到默认开），所以先把当前值传进去。
      try rimeContext.restRime(grammarModelEnabled: grammarModelEnabled)

      // 重置应用配置
      HamsterAppDependencyContainer.shared.resetHamsterConfiguration()

      // 重新读取 Hamster.yaml 生成 configuration
      let hamsterConfiguration = try HamsterConfigurationRepositories.shared.loadFromYAML(FileManager.hamsterConfigFileOnSandboxSharedSupport)

      // 保存配置至 build/hamster.yaml
      // try? HamsterConfigurationRepositories.shared.saveToYAML(config: configuration, path: FileManager.hamsterConfigFileOnBuild)
  //    try? HamsterConfigurationRepositories.shared.saveToJSON(
  //      config: configuration,
  //      path: FileManager.sandboxUserDataDirectory.appendingPathComponent("/build/hamster.json")
  //    )
      try? HamsterConfigurationRepositories.shared.saveToPropertyList(
        config: hamsterConfiguration,
        path: FileManager.sandboxUserDataDirectory.appendingPathComponent("/build/hamster.plist")
      )

      HamsterAppDependencyContainer.shared.configuration = hamsterConfiguration

      HamsterAppDependencyContainer.shared.applicationConfiguration = HamsterConfiguration(
        general: GeneralConfiguration(),
        toolbar: KeyboardToolbarConfiguration(),
        keyboard: KeyboardConfiguration(),
        rime: RimeConfiguration(),
        swipe: KeyboardSwipeConfiguration(),
        keyboards: nil
      )

      // TODO: 内置雾凇方案，将默认选择方案改为雾凇拼音
      let rimeSchema = RimeSchema(schemaId: "rime_ice", schemaName: "雾凇拼音")
      rimeContext.selectSchemas = [rimeSchema]
      rimeContext.currentSchema = rimeSchema

      /// 在另存一份用于应用配置还原
      try HamsterConfigurationRepositories.shared.saveToUserDefaultsOnDefault(hamsterConfiguration)

      await ProgressHUD.success("重置成功", interaction: false, delay: 1.5)
    } catch {
      Logger.statistics.error("rimeRest() error: \(error)")
      await ProgressHUD.failed("重置失败", interaction: false, delay: 3)
    }
  }
}
