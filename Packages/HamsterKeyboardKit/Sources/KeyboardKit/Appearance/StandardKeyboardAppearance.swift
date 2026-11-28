//
//  StandardKeyboardAppearance.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2021-01-10.
//  Copyright © 2021-2023 Daniel Saidi. All rights reserved.
//

import CoreGraphics
import UIKit

/**
 This standard appearance returns styles that replicates the
 look of a native system keyboard.

 该标准外观返回的样式与本地系统键盘的外观相同。

 You can inherit this class and override any open properties
 and functions to customize the appearance. For instance, to
 change the background color of inpout keys only, you can do
 it like this:

 您可以继承该类，并覆盖任何 open 的属性和函数来定制外观。例如，如果只想更改按键的背景颜色，可以这样做：

 ```swift
 class MyAppearance: StandardKeyboardAppearance {

     override func buttonStyle(
         for action: KeyboardAction,
         isPressed: Bool
     ) -> KeyboardButtonStyle {
         let style = super.buttonStyle(for: action, isPressed: isPressed)
         if !action.isInputAction { return style }
         style.backgroundColor = .red
         return style
     }
 }
 ```

 All buttons will be affected if you only return a new style.
 Sometimes that is what you want, but most often perhaps not.

 如果只返回新样式，所有按钮都会受到影响。有时这是你想要的，但大多数情况下可能不是。
 */
open class StandardKeyboardAppearance: KeyboardAppearance {
  private lazy var hamsterUIColor = HamsterUIColor.shared
  private lazy var hamsterUIImage = HamsterUIImage.shared

  /// 输入法配色方案缓存
  private var cacheHamsterKeyboardColor: [UIUserInterfaceStyle: HamsterKeyboardColor?] = [:]

  /// The keyboard context to use.
  ///
  /// 要使用的键盘上下文。
  public let keyboardContext: KeyboardContext

  // MARK: - Keyboard 键盘样式

  /// The background style to apply to the entire keyboard.
  ///
  /// 应用于整个键盘的背景样式。
  open var backgroundStyle: KeyboardBackgroundStyle {
    var style = KeyboardBackgroundStyle.standard
    // 回到 b14 的做法：近乎透明，让真正的系统键盘底色透出来。
    // 6bbfcaa 接的 standardKeyboardBackground 资产是液态玻璃之前的平板色（浅色 0.835/0.839/0.867），
    // 和 iOS 27 实际渲染的系统键盘底色对不上，和下方系统地球键/麦克风条之间出现明显分界；
    // 扩展里按 hasDarkColorScheme 定向解析也复现不了系统那条的材质，透明是最稳的。
    style.backgroundColor = UIColor.white.withAlphaComponent(0.001)

    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      style.backgroundColor = hamsterColor.backColor
    }

    return style
  }

  /// 非标准键盘样式
  open var nonStandardKeyboardStyle: NonStandardKeyboardStyle {
    let pressedBackgroundColor: UIColor = keyboardContext.hasDarkColorScheme ? hamsterUIColor.standardButtonBackground(for: keyboardContext) : .white
    let foregroundColor = hamsterUIColor.standardButtonForeground(for: keyboardContext)

    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      return NonStandardKeyboardStyle(
        backgroundColor: hamsterColor.buttonBackColor,
        pressedBackgroundColor: pressedBackgroundColor,
        foregroundColor: hamsterColor.buttonFrontColor,
        pressedForegroundColor: foregroundColor,
        borderColor: hamsterColor.borderColor,
        shadowColor: hamsterUIColor.standardButtonShadow,
        cornerRadius: hamsterColor.cornerRadius
      )
    }

    let backColor = hamsterUIColor.standardDarkButtonBackground(for: keyboardContext)
    return NonStandardKeyboardStyle(
      backgroundColor: backColor,
      pressedBackgroundColor: pressedBackgroundColor,
      foregroundColor: foregroundColor,
      pressedForegroundColor: foregroundColor,
      borderColor: .clear,
      shadowColor: hamsterUIColor.standardButtonShadow,
      cornerRadius: keyboardLayoutConfiguration.buttonCornerRadius
    )
  }

  /// The foreground color to apply to the entire keyboard.
  ///
  /// 应用于整个键盘的前景色。
  open var foregroundColor: UIColor? {
    nil
  }

  /// The edge insets to apply to the entire keyboard.
  ///
  /// 应用于整个键盘的边缘嵌入。
  open var keyboardEdgeInsets: UIEdgeInsets {
    switch keyboardContext.deviceType {
    case .pad: return UIEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
    case .phone:
      if keyboardContext.screenSize.isEqual(to: .iPhoneProMaxScreenPortrait, withTolerance: 10) {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
      } else {
        return UIEdgeInsets(top: 0, left: 0, bottom: -2, right: 0)
      }
    default: return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
  }

  /// The keyboard layout configuration to use.
  ///
  /// 要使用的键盘布局配置。
  open var keyboardLayoutConfiguration: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

  // MARK: - Buttons

  /// The button image to use for a certain action, if any.
  ///
  /// 用于特定操作的按钮图像（如果有）。
  open func buttonImage(for action: KeyboardAction) -> UIImage? {
    // 液态玻璃（iOS 26 样式）：换行键和系统一样显示 ↵ 图标。
    if isLiquidGlassEnabled, case .primary = action { return UIImage(systemName: "return.left") }
    return action.standardButtonImage(for: keyboardContext)
  }

  /// The content scale factor to use for a certain action.
  ///
  /// 用于特定操作的图像比例因子。
  open func buttonImageScaleFactor(for action: KeyboardAction) -> CGFloat {
    switch keyboardContext.deviceType {
    case .pad: return 1.2
    default: return 1
    }
  }

  /// 仓输入法配色
  open func hamsterColor() -> HamsterKeyboardColor? {
    guard keyboardContext.hamsterConfiguration?.keyboard?.enableColorSchema ?? false else { return nil }

    // 配色缓存
    if let cacheHamsterKeyboardColor = cacheHamsterKeyboardColor[keyboardContext.traitCollection.userInterfaceStyle] {
      return cacheHamsterKeyboardColor
    }

    var schemaName: String? = nil
    if keyboardContext.hasDarkColorScheme {
      schemaName = keyboardContext.hamsterConfiguration?.keyboard?.useColorSchemaForDark
    } else {
      schemaName = keyboardContext.hamsterConfiguration?.keyboard?.useColorSchemaForLight
    }

    guard let schema = keyboardContext.hamsterConfiguration?.keyboard?.colorSchemas?.first(where: { $0.schemaName == schemaName }) else { return nil }

    let hamsterColor = HamsterKeyboardColor(colorSchema: schema, userInterfaceStyle: keyboardContext.colorScheme)
    self.cacheHamsterKeyboardColor[keyboardContext.traitCollection.userInterfaceStyle] = hamsterColor
    return hamsterColor
  }

  /// 键盘背景色
  open func keyboardBackgroundColor() -> UIColor {
    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      return hamsterColor.backColor
    }

    return hamsterUIColor.clearInteractable
  }

  /// 默认拼写区文字大小
  open var phoneticTextFontSize: CGFloat {
    12
  }

  /// 候选栏样式
  open var candidateBarStyle: CandidateBarStyle {
    var phoneticTextFontSize: CGFloat = phoneticTextFontSize
    if let size = keyboardContext.hamsterConfiguration?.toolbar?.codingAreaFontSize {
      phoneticTextFontSize = CGFloat(size)
    }
    let phoneticTextFont = UIFont.systemFont(ofSize: phoneticTextFontSize)

    var candidateTextFont: UIFont = KeyboardFont.title3.font
    var candidateCommentFont: UIFont = KeyboardFont.caption2.font
    var candidateLabelFont: UIFont = KeyboardFont.caption2.font
    if let toolbarConfig = keyboardContext.hamsterConfiguration?.toolbar {
      if let candidateTextFontSize = toolbarConfig.candidateWordFontSize {
        candidateTextFont = UIFont.systemFont(ofSize: CGFloat(candidateTextFontSize))
      }
      if let candidateCommentFontSize = toolbarConfig.candidateCommentFontSize {
        candidateCommentFont = UIFont.systemFont(ofSize: CGFloat(candidateCommentFontSize))
      }

      if let candidateLabelFontSize = toolbarConfig.candidateLabelFontSize {
        candidateLabelFont = UIFont.systemFont(ofSize: CGFloat(candidateLabelFontSize))
      }
    }

    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      return CandidateBarStyle(
        phoneticTextColor: hamsterColor.textColor,
        phoneticTextFont: phoneticTextFont,
        preferredCandidateTextColor: hamsterColor.hilitedCandidateTextColor,
        preferredCandidateCommentTextColor: hamsterColor.hilitedCommentTextColor,
        preferredCandidateBackgroundColor: hamsterColor.hilitedCandidateBackColor,
        preferredCandidateLabelColor: hamsterColor.hilitedCandidateLabelColor,
        candidateTextColor: hamsterColor.candidateTextColor,
        candidateCommentTextColor: hamsterColor.commentTextColor,
        candidateLabelColor: hamsterColor.labelColor,
        candidateLabelFont: candidateLabelFont,
        candidateTextFont: candidateTextFont,
        candidateCommentFont: candidateCommentFont,
        toolbarButtonFrontColor: hamsterColor.buttonFrontColor,
        toolbarButtonBackgroundColor: .clear,
        toolbarButtonPressedBackgroundColor: hamsterColor.buttonPressedBackColor
      )
    }

    // 豆包风格候选栏：候选字约 20pt 黑色，首选放大 24pt + 浅色圆角高亮（ref2）。
    if isDoubaoStyleEnabled {
      let dark = keyboardContext.hasDarkColorScheme
      let textColor = DoubaoStyle.candidateText(dark: dark)
      let configuredSize = keyboardContext.hamsterConfiguration?.toolbar?.candidateWordFontSize
      // yaml 默认 18 视为“没改过”，用豆包的 20；用户改成别的值时尊重用户。
      let size: CGFloat = (configuredSize == nil || configuredSize == 18) ? DoubaoStyle.candidateFontSize : CGFloat(configuredSize!)
      var style = CandidateBarStyle(
        phoneticTextColor: DoubaoStyle.phoneticText(dark: dark),
        phoneticTextFont: UIFont.systemFont(ofSize: 13),
        preferredCandidateTextColor: textColor,
        preferredCandidateCommentTextColor: textColor,
        preferredCandidateBackgroundColor: DoubaoStyle.preferredCandidateBackground(dark: dark),
        preferredCandidateLabelColor: textColor,
        candidateTextColor: textColor,
        candidateCommentTextColor: DoubaoStyle.phoneticText(dark: dark),
        candidateLabelColor: textColor,
        candidateLabelFont: candidateLabelFont,
        candidateTextFont: UIFont.systemFont(ofSize: size),
        candidateCommentFont: candidateCommentFont,
        toolbarButtonFrontColor: DoubaoStyle.toolbarForeground(dark: dark),
        toolbarButtonBackgroundColor: .clear,
        toolbarButtonPressedBackgroundColor: DoubaoStyle.toolbarButtonPressedBackground(dark: dark)
      )
      style.preferredCandidateTextFont = UIFont.systemFont(ofSize: size + (DoubaoStyle.preferredCandidateFontSize - DoubaoStyle.candidateFontSize), weight: .medium)
      style.preferredCandidateCornerRadius = 12
      return style
    }

    let foregroundColor = hamsterUIColor.standardButtonForeground(for: keyboardContext)
    return CandidateBarStyle(
      phoneticTextColor: foregroundColor,
      phoneticTextFont: phoneticTextFont,
      preferredCandidateTextColor: foregroundColor,
      preferredCandidateCommentTextColor: foregroundColor,
      preferredCandidateBackgroundColor: hamsterUIColor.standardButtonBackground(for: keyboardContext),
      preferredCandidateLabelColor: foregroundColor,
      candidateTextColor: foregroundColor,
      candidateCommentTextColor: foregroundColor,
      candidateLabelColor: foregroundColor,
      candidateLabelFont: candidateLabelFont,
      candidateTextFont: candidateTextFont,
      candidateCommentFont: candidateCommentFont,
      toolbarButtonFrontColor: .secondaryLabel,
      toolbarButtonBackgroundColor: .clear,
      toolbarButtonPressedBackgroundColor: .secondarySystemFill
    )
  }

  /// The button style to use for a certain action.
  ///
  /// 在给定的 `isPressed` 状态下，用于特定 `action` 的按键样式。
  open func buttonStyle(for action: KeyboardAction, isPressed: Bool) -> KeyboardButtonStyle {
    let swipeFont = UIFont.systemFont(ofSize: 8)

    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      return KeyboardButtonStyle(
        backgroundColor: buttonBackgroundColor(for: action, isPressed: isPressed, hamsterColor: hamsterColor),
        foregroundColor: buttonForegroundColor(for: action, isPressed: isPressed, hamsterColor: hamsterColor),
        swipeForegroundColor: buttonSwipeForegroundColor(for: action, hamsterColor: hamsterColor),
        font: buttonFont(for: action, hamsterColor: hamsterColor),
        swipeFont: swipeFont,
        cornerRadius: buttonCornerRadius(for: action, hamsterColor: hamsterColor),
        border: buttonBorderStyle(for: action, hamsterColor: hamsterColor),
        shadow: buttonShadowStyle(for: action, hamsterColor: hamsterColor)
      )
    }

    return KeyboardButtonStyle(
      backgroundColor: buttonBackgroundColor(for: action, isPressed: isPressed),
      foregroundColor: buttonForegroundColor(for: action, isPressed: isPressed),
      swipeForegroundColor: UIColor.secondaryLabel,
      font: buttonFont(for: action),
      swipeFont: swipeFont,
      // cornerRadius: buttonCornerRadius(for: action),
      cornerRadius: isDoubaoStyleEnabled ? keyboardLayoutConfiguration.buttonCornerRadius : (isLiquidGlassEnabled ? Self.glassCornerRadius : 5),
      border: buttonBorderStyle(for: action),
      shadow: buttonShadowStyle(for: action)
    )
  }

  open func buttonStyle(for key: Key, isPressed: Bool) -> KeyboardButtonStyle {
    let swipeFont = UIFont.systemFont(ofSize: 8)
    let action = key.action

    // 开启键盘配色
    if let hamsterColor = hamsterColor() {
      return KeyboardButtonStyle(
        backgroundColor: buttonBackgroundColor(for: action, isPressed: isPressed, hamsterColor: hamsterColor),
        foregroundColor: buttonForegroundColor(for: action, isPressed: isPressed, hamsterColor: hamsterColor),
        swipeForegroundColor: buttonSwipeForegroundColor(for: action, hamsterColor: hamsterColor),
        font: buttonFont(for: key, hamsterColor: hamsterColor),
        swipeFont: swipeFont,
        cornerRadius: buttonCornerRadius(for: action, hamsterColor: hamsterColor),
        border: buttonBorderStyle(for: action, hamsterColor: hamsterColor),
        shadow: buttonShadowStyle(for: action, hamsterColor: hamsterColor)
      )
    }

    return KeyboardButtonStyle(
      backgroundColor: buttonBackgroundColor(for: action, isPressed: isPressed),
      foregroundColor: buttonForegroundColor(for: action, isPressed: isPressed),
      swipeForegroundColor: UIColor.secondaryLabel,
      font: buttonFont(for: key),
      swipeFont: swipeFont,
      cornerRadius: buttonCornerRadius(for: action),
      border: buttonBorderStyle(for: action),
      shadow: buttonShadowStyle(for: action)
    )
  }

  /// The button text to use for a certain action, if any.
  ///
  /// 用于特定操作的按钮文本（如果有）。
  open func buttonText(for action: KeyboardAction) -> String? {
    action.standardButtonText(for: keyboardContext)
  }

  // MARK: - Callouts

  /**
   The callout style to apply to action and input callouts.

   应用于操作和输入呼出的呼出样式。
   */
  open var calloutStyle: KeyboardCalloutStyle {
    var style = KeyboardCalloutStyle.standard
    // 豆包风格：按键弹泡与字母键同色、同圆角。
    if isDoubaoStyleEnabled {
      let dark = keyboardContext.hasDarkColorScheme
      style.backgroundColor = dark ? DoubaoStyle.darkKey : DoubaoStyle.lightKey
      style.textColor = DoubaoStyle.keyForeground(dark: dark)
      style.buttonCornerRadius = keyboardLayoutConfiguration.buttonCornerRadius
      style.cornerRadius = 12
      style.borderColor = UIColor.black.withAlphaComponent(dark ? 0.4 : 0.12)
      style.shadowColor = UIColor.black.withAlphaComponent(0.15)
    }
    return style
  }

  /// The style to apply to ``ActionCallout`` views.
  ///
  /// 应用于 ``ActionCallout`` 视图的样式。
  open var actionCalloutStyle: KeyboardActionCalloutStyle {
    var style = KeyboardActionCalloutStyle.standard
    style.callout = calloutStyle
    return style
  }

  /// The style to apply to ``InputCallout`` views.
  ///
  /// 应用于 ``InputCallout`` 视图的样式。
  open var inputCalloutStyle: KeyboardInputCalloutStyle {
    var style = KeyboardInputCalloutStyle.standard
    style.callout = calloutStyle
    return style
  }

  // MARK: - Autocomplete

  /// The style to apply to ``AutocompleteToolbar`` views.
  ///
  /// 应用于 ``AutocompleteToolbar`` 视图的样式。
  public var autocompleteToolbarStyle: AutocompleteToolbarStyle {
    return .standard
  }

  // MARK: - initialisation

  /**
   Create a standard keyboard appearance intance.

   - Parameters:
     - keyboardContext: The keyboard context to use.
   */
  public init(keyboardContext: KeyboardContext) {
    self.keyboardContext = keyboardContext
  }

  // MARK: - Overridable Button Style Components 可覆盖的按钮样式组件

  /// The background color to use for a certain action.
  ///
  /// 根据给定 `isPressed` 状态， 用于特定操作的背景颜色。
  open func buttonBackgroundColor(for action: KeyboardAction, isPressed: Bool) -> UIColor {
    if let color = doubaoButtonBackgroundColor(for: action, isPressed: isPressed) { return color }
    // 液态玻璃（iOS 26 样式）：照 iOS 26 系统键盘真机截图取色（IMG_1218 深色 / IMG_1219 浅色）：
    // 所有按键（字母键和 shift/删除/123/换行/空格）同一个颜色，浅色纯白、深色 #444444；
    // 按下深色 #686868（真机取色），浅色 #C8CBD2（截图里被气泡挡住，估值）。
    // 透明占位类按键（none、字符边距、emoji）不改。玻璃关、自定义配色方案不走这里，和 b24 一样。
    if isLiquidGlassEnabled, action.buttonBackgroundColorForAllStates == nil {
      let dark = keyboardContext.hasDarkColorScheme
      if isPressed { return dark ? Self.glassDarkPressed : Self.glassLightPressed }
      return dark ? Self.glassDarkKey : .white
    }
    return action.buttonBackgroundColor(for: keyboardContext, isPressed: isPressed)
  }

  private static let glassDarkKey = UIColor(red: 0x44 / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
  private static let glassDarkPressed = UIColor(red: 0x68 / 255, green: 0x68 / 255, blue: 0x68 / 255, alpha: 1)
  private static let glassLightPressed = UIColor(red: 0xC8 / 255, green: 0xCB / 255, blue: 0xD2 / 255, alpha: 1)
  /// iOS 26 系统键盘按键圆角（截图量约 8.5pt）。
  private static let glassCornerRadius: CGFloat = 8.5

  /// 液态玻璃（iOS 26 样式）是否开启：开关开且系统 iOS 26+（配置每次弹出前重读）。
  private var isLiquidGlassEnabled: Bool {
    keyboardContext.isLiquidGlassEnabled
  }

  // MARK: - 豆包风格

  /// 豆包风格是否开启（默认开；自定义配色方案开着时不生效）。
  private var isDoubaoStyleEnabled: Bool {
    keyboardContext.isDoubaoStyleEnabled
  }

  /// 豆包风格下这个按键是不是「白键」（字母、空格、，。、中英切换等），否则是灰色功能键。
  private func isDoubaoLightKey(_ action: KeyboardAction) -> Bool {
    switch action {
    case .space: return true
    case .shift: return action.isUppercasedShiftAction
    case .keyboardType(let type):
      if action.isClassifySymbolicOfLight { return true }
      // 中/英切换键在 26 键主键盘上是白键（ref4）；数字/符号层上的「返回」类按键仍是灰色功能键。
      let onPrimary = keyboardContext.keyboardType.isChinesePrimaryKeyboard || keyboardContext.keyboardType.isAlphabetic
      return onPrimary && (type.isAlphabetic || type.isChinesePrimaryKeyboard)
    default:
      break
    }
    if action.isSystemAction || action.isSymbolOfDarkAction || action.isCharacterOfDarkAction || action.isCleanSpellingArea {
      return false
    }
    return true
  }

  /// 豆包风格按键底色（ref4 / ref3 取色，见 DoubaoStyle）。不适用时返回 nil。
  private func doubaoButtonBackgroundColor(for action: KeyboardAction, isPressed: Bool) -> UIColor? {
    guard isDoubaoStyleEnabled, action.buttonBackgroundColorForAllStates == nil else { return nil }
    let dark = keyboardContext.hasDarkColorScheme
    // 回车：输入框指定了动作（发送/搜索/前往/完成…）时蓝色；普通换行（.return）是灰色「换行」（ref3）。
    if case .primary(let type) = action, !type.isSystemAction {
      return isPressed ? DoubaoStyle.returnBluePressed : DoubaoStyle.returnBlue
    }
    if isDoubaoLightKey(action) {
      if dark { return isPressed ? DoubaoStyle.darkKeyPressed : DoubaoStyle.darkKey }
      return isPressed ? DoubaoStyle.lightKeyPressed : DoubaoStyle.lightKey
    }
    if dark { return isPressed ? DoubaoStyle.darkFunctionKeyPressed : DoubaoStyle.darkFunctionKey }
    return isPressed ? DoubaoStyle.lightFunctionKeyPressed : DoubaoStyle.lightFunctionKey
  }

  open func buttonBackgroundColor(for action: KeyboardAction, isPressed: Bool, hamsterColor: HamsterKeyboardColor) -> UIColor {
    return action.buttonBackgroundColor(for: keyboardContext, isPressed: isPressed, hamsterColor: hamsterColor)
  }

  /// The border style to use for a certain action.
  ///
  /// 用于特定操作的边框样式。
  open func buttonBorderStyle(for action: KeyboardAction) -> KeyboardButtonBorderStyle {
    switch action {
    case .emoji, .emojiCategory, .none: return .noBorder
    default: return .standard
    }
  }

  open func buttonBorderStyle(for action: KeyboardAction, hamsterColor: HamsterKeyboardColor) -> KeyboardButtonBorderStyle {
    switch action {
    case .emoji, .emojiCategory, .none: return .noBorder
    default: return KeyboardButtonBorderStyle(color: hamsterColor.borderColor, size: 1)
    }
  }

  /// The corner radius to use for a certain action.
  ///
  /// 用于特定操作的圆角半径。
  open func buttonCornerRadius(for action: KeyboardAction) -> CGFloat {
    if isDoubaoStyleEnabled { return keyboardLayoutConfiguration.buttonCornerRadius }
    if isLiquidGlassEnabled { return Self.glassCornerRadius }
    return keyboardLayoutConfiguration.buttonCornerRadius
  }

  open func buttonCornerRadius(for action: KeyboardAction, hamsterColor: HamsterKeyboardColor) -> CGFloat {
    hamsterColor.cornerRadius
  }

  /// The font to use for a certain action.
  ///
  /// 用于特定操作的字体。
  open func buttonFont(for action: KeyboardAction) -> UIFont {
    let size = buttonFontSize(for: action)
    guard let weight = buttonFontWeight(for: action) else { return getCacheFont(size: size, weight: nil) }
    return getCacheFont(size: size, weight: weight)
  }

  open func buttonFont(for key: Key) -> UIFont {
    let size = buttonFontSize(for: key)
    guard let weight = buttonFontWeight(for: key) else { return UIFont.systemFont(ofSize: size) }
    return UIFont.systemFont(ofSize: size, weight: weight)
  }

  // TODO: 暂不支持自定义字体
  var cacheFont = [String: UIFont]()
  func getCacheFont(size: CGFloat, weight: UIFont.Weight?) -> UIFont {
    let key = "size:\(size),weight:\(weight?.rawValue ?? 0)"
    if let value = cacheFont[key] {
      return value
    }
    if let weight = weight {
      let font = UIFont.systemFont(ofSize: size, weight: weight)
      cacheFont[key] = font
      return font
    }
    let font = UIFont.systemFont(ofSize: size)
    cacheFont[key] = font
    return font
  }

  open func buttonFont(for action: KeyboardAction, hamsterColor: HamsterKeyboardColor) -> UIFont {
    let size = buttonFontSize(for: action)
    guard let weight = buttonFontWeight(for: action) else { return getCacheFont(size: size, weight: nil) }
    return getCacheFont(size: size, weight: weight)
  }

  open func buttonFont(for key: Key, hamsterColor: HamsterKeyboardColor) -> UIFont {
    let size = buttonFontSize(for: key)
    guard let weight = buttonFontWeight(for: key) else { return getCacheFont(size: size, weight: nil) }
    return getCacheFont(size: size, weight: weight)
  }

  /// The font size to use for a certain action.
  ///
  /// 用于特定操作的字体大小。
  open func buttonFontSize(for action: KeyboardAction) -> CGFloat {
    if action.isShortCommand {
      return 16
    }
    // 豆包风格：「123」约 17pt，回车文字约 16pt（ref4 量得）。
    if isDoubaoStyleEnabled, keyboardContext.deviceType == .phone {
      if case .keyboardType = action { return 17 }
      if action.isPrimaryAction { return 16 }
    }
    if let override = buttonFontSizePadOverride(for: action) { return override }
    if let override = buttonFontSizeActionOverride(for: action) { return override }
    if action == .returnLastKeyboard || action == .cleanSpellingArea {
      return 16
    }
    let text = buttonText(for: action) ?? ""
    if action.isInputAction && text.isLowercased { return 26 }
    if action.isSystemAction || action.isPrimaryAction { return 16 }
    return 23
  }

  open func buttonFontSize(for key: Key) -> CGFloat {
    let action = key.action

    if action.isShortCommand {
      return 16
    }

    // patch: 自定义键盘中 symbol 类型且 char 非单个字母的情况，比如 .com / http 等
    if action.isSymbol && key.labelText.count > 1 {
      return 14
    }

    if let override = buttonFontSizePadOverride(for: action) { return override }
    if let override = buttonFontSizeActionOverride(for: action) { return override }
    if action == .returnLastKeyboard || action == .cleanSpellingArea {
      return 16
    }
    let text = key.labelText
    if action.isInputAction && text.isLowercased {
      return 26
    }
    if action.isSystemAction || action.isPrimaryAction { return 16 }
    return 23
  }

  /// The font size to override for a certain action.
  ///
  /// 用于特定操作需要覆盖的字体大小。
  func buttonFontSizeActionOverride(for action: KeyboardAction) -> CGFloat? {
    switch action {
    case .keyboardType(let type): return buttonFontSize(for: type)
    case .space: return 16
    default: return nil
    }
  }

  /// The font size to override for a certain iPad action.
  ///
  /// 在 iPad 上执行特定操作时需要覆盖的字体大小。
  func buttonFontSizePadOverride(for action: KeyboardAction) -> CGFloat? {
    guard keyboardContext.deviceType == .pad else { return nil }
    let isLandscape = keyboardContext.interfaceOrientation.isLandscape
    guard isLandscape else { return nil }
    if action.isAlphabeticKeyboardTypeAction { return 22 }
    if action.isKeyboardTypeAction(.numeric) { return 22 }
    if action.isKeyboardTypeAction(.symbolic) { return 20 }
    return nil
  }

  /// The font size to use for a certain keyboard type.
  ///
  /// 用于特定键盘类型的字体大小。
  open func buttonFontSize(for keyboardType: KeyboardType) -> CGFloat {
    switch keyboardType {
    case .alphabetic: return 15
    case .numeric: return 16
    case .symbolic: return 14
    default: return 14
    }
  }

  /// The font weight to use for a certain action.
  ///
  /// 用于特定操作的字体粗细。
  open func buttonFontWeight(for action: KeyboardAction) -> UIFont.Weight? {
    switch action {
    case .backspace: return .regular
    case .character(let char): return char.isLowercased ? .light : nil
    case .symbol(let symbol): return symbol.char.isLowercased ? .light : nil
    // default: return buttonImage(for: action) != nil ? .light : nil
    default: return nil
    }
  }

  open func buttonFontWeight(for key: Key) -> UIFont.Weight? {
    let action = key.action
    switch action {
    case .backspace: return .regular
    case .character(let char): return char.isLowercased ? .light : nil
    case .symbol(let symbol): return symbol.char.isLowercased ? .light : nil
    // default: return buttonImage(for: action) != nil ? .light : nil
    default: return nil
    }
  }

  /// The foreground color to use for a certain action.
  ///
  /// 用于特定操作的按键前景色。
  open func buttonForegroundColor(for action: KeyboardAction, isPressed: Bool) -> UIColor {
    if isDoubaoStyleEnabled, action.buttonForegroundColorForAllStates == nil {
      if case .primary(let type) = action, !type.isSystemAction { return .white }
      return DoubaoStyle.keyForeground(dark: keyboardContext.hasDarkColorScheme)
    }
    return action.buttonForegroundColor(for: keyboardContext, isPressed: isPressed)
  }

  open func buttonForegroundColor(for action: KeyboardAction, isPressed: Bool, hamsterColor: HamsterKeyboardColor) -> UIColor {
    action.buttonForegroundColor(for: keyboardContext, isPressed: isPressed, hamsterColor: hamsterColor)
  }

  open func buttonSwipeForegroundColor(for action: KeyboardAction, hamsterColor: HamsterKeyboardColor) -> UIColor {
    action.buttonSwipeForegroundColor(for: keyboardContext, hamsterColor: hamsterColor)
  }

  /// The shadow style to use for a certain action.
  ///
  /// 用于特定操作的按键阴影样式。
  open func buttonShadowStyle(for action: KeyboardAction) -> KeyboardButtonShadowStyle {
    // iOS 26 系统键盘按键没有底部阴影。
    if isLiquidGlassEnabled { return .noShadow }
    // 豆包风格：底部约 1pt 硬边细阴影（ref4：225 的底色压到约 192）。
    if isDoubaoStyleEnabled {
      switch action {
      case .characterMargin, .emoji, .emojiCategory, .none: return .noShadow
      default: return KeyboardButtonShadowStyle(color: DoubaoStyle.keyShadow(dark: keyboardContext.hasDarkColorScheme), size: DoubaoStyle.keyShadowOffset)
      }
    }
    switch action {
    case .characterMargin: return .noShadow
    case .emoji, .emojiCategory: return .noShadow
    case .none: return .noShadow
    default: return .standard
    }
  }

  // TODO: 自定义阴影配色
  open func buttonShadowStyle(for action: KeyboardAction, hamsterColor: HamsterKeyboardColor) -> KeyboardButtonShadowStyle {
    switch action {
    case .characterMargin: return .noShadow
    case .emoji, .emojiCategory: return .noShadow
    case .none: return .noShadow
    default: return .standard
    }
  }
}

extension KeyboardAction {
  /// 所有状态的按键背景颜色
  var buttonBackgroundColorForAllStates: UIColor? {
    switch self {
    case .none: return .clear
    case .characterMargin: return HamsterUIColor.shared.clearInteractable
    case .emoji: return HamsterUIColor.shared.clearInteractable
    case .emojiCategory: return HamsterUIColor.shared.clearInteractable
    default: return nil
    }
  }

  /// 给定 `isPressed` 状态下，根据 `context`，获取按键背景色
  func buttonBackgroundColor(for context: KeyboardContext, isPressed: Bool = false) -> UIColor {
    if let color = buttonBackgroundColorForAllStates { return color }
    return isPressed ?
      buttonBackgroundColorForPressedState(for: context) :
      buttonBackgroundColorForIdleState(for: context)
  }

  func buttonBackgroundColor(for context: KeyboardContext, isPressed: Bool = false, hamsterColor: HamsterKeyboardColor) -> UIColor {
    if let color = buttonBackgroundColorForAllStates { return color }
    return isPressed ? hamsterColor.buttonPressedBackColor : hamsterColor.buttonBackColor
  }

  /// 按键空闲状态的背景颜色
  func buttonBackgroundColorForIdleState(for context: KeyboardContext) -> UIColor {
    // 数字九宫格分类符号按键颜色调整
    if isClassifySymbolicOfLight {
      return HamsterUIColor.shared.standardButtonBackground(for: context)
    }
    if isUppercasedShiftAction { return buttonBackgroundColorForPressedState(for: context) }
    if isSystemAction || isSymbolOfDarkAction || isCharacterOfDarkAction || isCleanSpellingArea {
      return HamsterUIColor.shared.standardDarkButtonBackground(for: context)
    }
    if isPrimaryAction { return UIColor.systemBlue }
    if isUppercasedShiftAction { return HamsterUIColor.shared.standardButtonBackground(for: context) }
    return HamsterUIColor.shared.standardButtonBackground(for: context)
  }

  /// 按键按下状态的背景颜色
  func buttonBackgroundColorForPressedState(for context: KeyboardContext) -> UIColor {
    // 数字九宫格分类符号按键颜色调整
    if isClassifySymbolicOfLight {
      return context.hasDarkColorScheme ? HamsterUIColor.shared.standardButtonBackground(for: context) : .white
    }

    if isSystemAction || isSymbolOfDarkAction || isCharacterOfDarkAction || isCleanSpellingArea {
      return context.hasDarkColorScheme ? HamsterUIColor.shared.standardButtonBackground(for: context) : .white
    }
    if isPrimaryAction { return context.hasDarkColorScheme ? HamsterUIColor.shared.standardDarkButtonBackground(for: context) : .white }
    if isUppercasedShiftAction { return HamsterUIColor.shared.standardDarkButtonBackground(for: context) }
    return HamsterUIColor.shared.standardDarkButtonBackground(for: context)
  }

  /// 全部状态下按键的前景色
  var buttonForegroundColorForAllStates: UIColor? {
    switch self {
    case .none: return .clear
    case .characterMargin: return HamsterUIColor.shared.clearInteractable
    default: return nil
    }
  }

  /// 根据 `isPressed` 状态，`context` 获取按键前景色
  func buttonForegroundColor(for context: KeyboardContext, isPressed: Bool = false) -> UIColor {
    if let color = buttonForegroundColorForAllStates { return color }
    return isPressed ?
      buttonForegroundColorForPressedState(for: context) :
      buttonForegroundColorForIdleState(for: context)
  }

  func buttonForegroundColor(for context: KeyboardContext, isPressed: Bool = false, hamsterColor: HamsterKeyboardColor) -> UIColor {
    if let color = buttonForegroundColorForAllStates { return color }
    return isPressed ? hamsterColor.buttonPressedFrontColor : hamsterColor.buttonFrontColor
  }

  func buttonSwipeForegroundColor(for context: KeyboardContext, hamsterColor: HamsterKeyboardColor) -> UIColor {
    if let color = buttonForegroundColorForAllStates { return color }
    return hamsterColor.buttonSwipeFrontColor
  }

  /// 空闲状态下按键的前景色
  func buttonForegroundColorForIdleState(for context: KeyboardContext) -> UIColor {
    let standard = HamsterUIColor.shared.standardButtonForeground(for: context)
    if isSystemAction { return standard }
    if isPrimaryAction { return .white }
    return standard
  }

  /// 按下状态下按键的前景色
  func buttonForegroundColorForPressedState(for context: KeyboardContext) -> UIColor {
    let standard = HamsterUIColor.shared.standardButtonForeground(for: context)
    if isSystemAction { return standard }
    if isPrimaryAction { return context.hasDarkColorScheme ? .white : standard }
    return standard
  }
}
