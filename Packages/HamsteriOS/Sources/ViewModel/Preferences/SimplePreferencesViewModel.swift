//
//  SimplePreferencesViewModel.swift
//
//  精简设置页：四项偏好（候选个数、触感开关+强度、中文标点全/半角、Emoji 候选开关）
//  + 一个调试开关（显示弹出耗时，默认关）。
//  四项都走现有双写通道（configuration + applicationConfiguration），
//  靠 didSet 异步写进 App Group 的 build/hamster.plist；键盘每次出现时重读。
//  不适用方案 A 或已废弃功能的设置项：逐项核对过，没有残留行可删——
//  CloudInputSchema/UploadInputSchema 是 Package.swift 里 exclude 的死文件，
//  无 UI 入口；按键音没有设置行；iCloud 设置页第②步已删。
//

import Foundation
import HamsterKeyboardKit
import HamsterKit
import UIKit

public class SimplePreferencesViewModel {
  // MARK: - 候选个数（沿用现有项，50–500）

  public var maximumNumberOfCandidateWords: Int {
    get {
      HamsterAppDependencyContainer.shared.configuration.rime?.maximumNumberOfCandidateWords ?? 100
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.rime?.maximumNumberOfCandidateWords = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.rime?.maximumNumberOfCandidateWords = newValue
    }
  }

  // MARK: - 触感开关 + 强度（沿用现有项；强度默认值已统一成 3，与 hamster.yaml 一致）

  public var enableHapticFeedback: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.enableHapticFeedback ?? false
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.enableHapticFeedback = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.keyboard?.enableHapticFeedback = newValue
    }
  }

  public var hapticFeedbackIntensity: Int {
    get {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.hapticFeedbackIntensity ?? 3
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.hapticFeedbackIntensity = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.keyboard?.hapticFeedbackIntensity = newValue
    }
  }

  // MARK: - 中文标点全/半角（新增；默认开=全角，即现行行为）

  public var fullShapePunctuation: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.rime?.fullShapePunctuation ?? true
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.rime?.fullShapePunctuation = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.rime?.fullShapePunctuation = newValue
    }
  }

  // MARK: - Emoji 候选开关（新增；默认开，与 rime_ice 方案 emoji 的 reset: 1 一致）

  public var emojiCandidateEnabled: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.rime?.emojiCandidateEnabled ?? true
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.rime?.emojiCandidateEnabled = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.rime?.emojiCandidateEnabled = newValue
    }
  }

  // MARK: - 显示弹出耗时（调试开关，默认关）

  public var showPopupLatency: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.showPopupLatency ?? false
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.showPopupLatency = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.keyboard?.showPopupLatency = newValue
    }
  }

  // MARK: - 液态玻璃样式（新增；默认关，仅 iOS 26+ 可用）

  /// 是否 iOS 26 及以上（液态玻璃要 UIGlassEffect，只在 iOS 26+ 有）。
  public static var supportsLiquidGlass: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  public var liquidGlassStyle: Bool {
    get {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.liquidGlassStyle ?? false
    }
    set {
      HamsterAppDependencyContainer.shared.configuration.keyboard?.liquidGlassStyle = newValue
      HamsterAppDependencyContainer.shared.applicationConfiguration.keyboard?.liquidGlassStyle = newValue
    }
  }

  // MARK: - 设置表

  public lazy var settings: [SettingSectionModel] = [
    .init(title: "候选", items: [
      .init(
        text: "候选个数",
        type: .step,
        textValue: { [unowned self] in String(maximumNumberOfCandidateWords) },
        minValue: 50,
        maxValue: 500,
        stepValue: 50,
        valueChangeHandled: { [unowned self] in
          maximumNumberOfCandidateWords = Int($0)
        }),
    ]),
    .init(title: "触感", items: [
      .init(
        text: "触感反馈",
        type: .toggle,
        toggleValue: { [unowned self] in enableHapticFeedback },
        toggleHandled: { [unowned self] in
          enableHapticFeedback = $0
        }),
      .init(
        text: "触感强度",
        type: .step,
        textValue: { [unowned self] in String(hapticFeedbackIntensity) },
        minValue: 0,
        maxValue: 4,
        stepValue: 1,
        valueChangeHandled: { [unowned self] in
          hapticFeedbackIntensity = Int($0)
        }),
    ]),
    .init(
      title: "标点与 Emoji",
      footer: "中文标点：开启时，中文数字/符号层的标点走 RIME 全角转换；关闭时始终用半角（英文模式下本来就是半角）。Emoji：关闭后，输入法不再把 Emoji 作为候选项。",
      items: [
        .init(
          text: "中文标点用全角",
          type: .toggle,
          toggleValue: { [unowned self] in fullShapePunctuation },
          toggleHandled: { [unowned self] in
            fullShapePunctuation = $0
          }),
        .init(
          text: "Emoji 候选",
          type: .toggle,
          toggleValue: { [unowned self] in emojiCandidateEnabled },
          toggleHandled: { [unowned self] in
            emojiCandidateEnabled = $0
          }),
      ]),
    .init(
      title: "外观",
      footer: "液态玻璃样式：开启后按键和候选栏用系统液态玻璃底，尽量贴近系统键盘。需要 iOS 26 及以上，低版本上开关不可用。键盘每次弹出时重读本开关。",
      items: [
        .init(
          text: "液态玻璃样式",
          type: .toggle,
          toggleValue: { [unowned self] in liquidGlassStyle },
          toggleHandled: { [unowned self] in
            liquidGlassStyle = $0
          },
          isEnabled: Self.supportsLiquidGlass),
      ]),
    .init(
      title: "调试",
      footer: "开启后，键盘每次弹出时会在键盘内显示“弹出耗时 x ms”（从弹出到可打字的时间），约 3 秒后消失；关闭后完全不显示。默认关闭。",
      items: [
        .init(
          text: "显示弹出耗时",
          type: .toggle,
          toggleValue: { [unowned self] in showPopupLatency },
          toggleHandled: { [unowned self] in
            showPopupLatency = $0
          }),
      ]),
  ]

  init() {}
}
