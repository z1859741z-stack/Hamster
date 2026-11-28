//
//  SpaceContentView.swift
//
//
//  Created by morse on 2023/8/10.
//

import Combine
import HamsterUIKit
import UIKit

class SpaceContentView: NibLessView {
  private let keyboardContext: KeyboardContext
  private let rimeContext: RimeContext
  private let item: KeyboardLayoutItem
  private var spaceText: String
  private var style: KeyboardButtonStyle
  private var oldBounds: CGRect = .zero
  /// 是否首次加载空格
  private var firstLoadingSpace = true
  private var subscriptions = Set<AnyCancellable>()

  private lazy var loadingLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .center
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.2
    if keyboardContext.keyboardType.isCustom {
      label.text = item.key?.label.loadingText ?? ""
      if keyboardContext.showCurrentInputSchemaNameOnLoadingTextForSpaceButton, let text = rimeContext.currentSchema?.schemaName {
        label.text = text
      }
    } else {
      label.text = keyboardContext.loadingTextForSpaceButton
      if keyboardContext.showCurrentInputSchemaNameOnLoadingTextForSpaceButton, let text = rimeContext.currentSchema?.schemaName {
        label.text = text
      }
    }
    return label
  }()

  private lazy var textView: TextContentView = {
    var spaceText = ""
    if keyboardContext.keyboardType.isCustom {
      spaceText = item.key?.label.text ?? ""
      if keyboardContext.showCurrentInputSchemaNameForSpaceButton, let text = rimeContext.currentSchema?.schemaName {
        spaceText = text
      }
    } else {
      spaceText = keyboardContext.labelTextForSpaceButton
      if keyboardContext.showCurrentInputSchemaNameForSpaceButton, let text = rimeContext.currentSchema?.schemaName {
        spaceText = text
      }
    }

    // 数字键盘不显示
    if keyboardContext.keyboardType.isNumber {
      spaceText = self.spaceText
    }

    let textView = TextContentView(
      keyboardContext: keyboardContext,
      item: item,
      style: style,
      text: spaceText,
      isInputAction: true
    )
    return textView
  }()

  /// 豆包风格：空格中间显示声波小图标（中文模式不显示文字，ref4）。
  private var isDoubaoWaveApplicable: Bool {
    keyboardContext.isDoubaoStyleEnabled
      && keyboardContext.deviceType == .phone
      && !keyboardContext.keyboardType.isCustom
      && !keyboardContext.keyboardType.isNumber
      && !keyboardContext.showCurrentInputSchemaNameForSpaceButton
  }

  private lazy var waveView: DoubaoGlyphView = {
    DoubaoGlyphView(kind: .spaceWave, primaryColor: style.foregroundColor ?? .label, isDark: keyboardContext.hasDarkColorScheme)
  }()

  /// 中文 26 键 + 中文模式显示声波、隐藏文字；英文（含中文键盘切到英文模式）显示 "space"。
  private func updateDoubaoWave() {
    guard isDoubaoWaveApplicable else { return }
    let showWave = keyboardContext.keyboardType.isChinesePrimaryKeyboard && !rimeContext.asciiMode
    waveView.isHidden = !showWave
    textView.isHidden = showWave
  }

  var isShowLoadingText: Bool {
    if keyboardContext.keyboardType.isNumber || !keyboardContext.enableLoadingTextForSpaceButton {
      return false
    }
    return true
  }

  init(keyboardContext: KeyboardContext, rimeContext: RimeContext, item: KeyboardLayoutItem, style: KeyboardButtonStyle, spaceText: String) {
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.item = item
    self.style = style
    self.spaceText = spaceText

    super.init(frame: .zero)

    setupView()
    combine()
  }

  func setupView() {
    if isDoubaoWaveApplicable {
      addSubview(waveView)
      updateDoubaoWave()
    }
    /// 数字键盘不显示加载文字
    if !isShowLoadingText {
      addSubview(textView)
      return
    }

    loadingLabel.textColor = style.foregroundColor
    loadingLabel.font = style.font
    loadingLabel.alpha = showLoadingTextAlphaValue
    addSubview(loadingLabel)

    textView.alpha = showTextViewAlphaValue
    addSubview(textView)
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    guard self.bounds != oldBounds else { return }
    self.oldBounds = self.bounds
    /// 数字键盘不显示加载文字
    if isShowLoadingText {
      loadingLabel.frame = oldBounds
    }
    textView.frame = oldBounds
    if waveView.superview != nil {
      waveView.frame = oldBounds
    }
  }

  override func setupAppearance() {
    if waveView.superview != nil {
      waveView.update(primaryColor: style.foregroundColor ?? .label, isDark: keyboardContext.hasDarkColorScheme)
    }
    loadingLabel.textColor = style.foregroundColor
    textView.setStyle(style)
  }

  func setStyle(_ style: KeyboardButtonStyle) {
    guard self.style != style else { return }
    self.style = style
    setupAppearance()
  }

  var showLoadingTextAlphaValue: CGFloat {
    guard firstLoadingSpace else { return 0 }
    return isShowLoadingText ? 1 : 0
  }

  var showTextViewAlphaValue: CGFloat {
    guard firstLoadingSpace else { return 1 }
    return isShowLoadingText ? 0 : 1
  }

  func combine() {
    rimeContext.$optionState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        guard let optionState = $0 else { return }
        guard !self.firstLoadingSpace else { return }
        self.loadingLabel.alpha = 1
        self.loadingLabel.text = optionState
        self.textView.alpha = 0
        loadingAnimate()
      }
      .store(in: &subscriptions)

    // 空格字跟随中/英切换：中文键盘 + 英文模式时显示 "space"
    rimeContext.$asciiMode
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.updateSpaceText()
        self?.updateDoubaoWave()
      }
      .store(in: &subscriptions)
  }

  /// 按当前中/英状态刷新空格键文字：中文键盘 + 英文模式（asciiMode）显示 "space"，其余走 labelTextForSpaceButton。
  /// 自定义键盘、数字键盘、显示方案名模式下不改（沿用建好时的文字）。
  private func updateSpaceText() {
    guard !keyboardContext.keyboardType.isCustom,
          !keyboardContext.keyboardType.isNumber,
          !keyboardContext.showCurrentInputSchemaNameForSpaceButton else { return }
    let text = (keyboardContext.keyboardType.isChinese && rimeContext.asciiMode)
      ? "space"
      : keyboardContext.labelTextForSpaceButton
    textView.setTextValue(text)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    guard let _ = window else { return }
    if firstLoadingSpace {
      if isShowLoadingText {
        loadingAnimate()
      }
    }
  }

  func loadingAnimate() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      guard let self = self else { return }
      UIView.animate(withDuration: 0.35) {
        self.loadingLabel.alpha = 0
        self.loadingLabel.text = nil
        self.rimeContext.optionState = nil
        self.textView.alpha = 1
        self.firstLoadingSpace = false
      }
    }
  }
}
