//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

/**
 键盘工具栏

 用于显示：
 1. 候选文字，包含横向部分文字显示及下拉显示全部文字
 2. 常用功能视图
 */
class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()

  /// 常用功能项: 仓输入法App
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "r.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(openHamsterAppTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(openHamsterAppTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)

    return button
  }()

  /// 解散键盘 Button
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  // MARK: - 豆包风格工具栏（未输入时）

  /// 豆包风格是否生效（iPhone 非浮动）。
  private var isDoubaoToolbar: Bool {
    keyboardContext.isDoubaoStyleEnabled && keyboardContext.deviceType == .phone && !keyboardContext.isKeyboardFloating
  }

  /// 左侧圆形「⌘」按钮：打开仓输入法 App（与原工具栏的应用图标按钮同一动作）。
  lazy var doubaoMenuButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "command"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .regular), forImageIn: .normal)
    button.layer.cornerRadius = DoubaoStyle.toolbarButtonDiameter / 2
    button.accessibilityLabel = "仓输入法设置"
    button.addTarget(self, action: #selector(doubaoButtonTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(openHamsterAppTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(doubaoButtonTouchEnd(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    return button
  }()

  /// 「🎙 点击说话」胶囊：本版离线不支持语音，点按只在候选栏位置短暂提示。
  lazy var doubaoVoiceButton: UIControl = {
    let control = UIControl(frame: .zero)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.layer.cornerRadius = DoubaoStyle.toolbarButtonDiameter / 2
    control.accessibilityLabel = "点击说话"

    let stack = UIStackView(arrangedSubviews: [doubaoMicImageView, doubaoVoiceLabel])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 5
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    control.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: control.centerXAnchor, constant: -1),
      stack.centerYAnchor.constraint(equalTo: control.centerYAnchor),
    ])

    control.addTarget(self, action: #selector(doubaoButtonTouchDown(_:)), for: .touchDown)
    control.addTarget(self, action: #selector(doubaoVoiceTouchUpAction), for: .touchUpInside)
    control.addTarget(self, action: #selector(doubaoButtonTouchEnd(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    return control
  }()

  lazy var doubaoMicImageView: UIImageView = {
    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    let view = UIImageView(image: UIImage(systemName: "mic", withConfiguration: config))
    view.contentMode = .center
    return view
  }()

  lazy var doubaoVoiceLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.text = "点击说话"
    label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
    return label
  }()

  /// 最右圆形「∨」按钮：收起键盘。
  lazy var doubaoDismissButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: 15, weight: .medium), forImageIn: .normal)
    button.layer.cornerRadius = DoubaoStyle.toolbarButtonDiameter / 2
    button.accessibilityLabel = "收起键盘"
    button.addTarget(self, action: #selector(doubaoButtonTouchDown(_:)), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(doubaoButtonTouchEnd(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    return button
  }()

  /// 候选栏位置的短暂提示（如「离线版不支持语音」）。
  lazy var doubaoToastLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.textAlignment = .center
    label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
    label.alpha = 0
    label.isUserInteractionEnabled = false
    return label
  }()

  /// 提示序号：连点时只让最后一次的隐藏生效。
  private var doubaoToastSerial = 0

  // TODO: 常用功能栏
  lazy var commonFunctionBar: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选文字视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )
    return view
  }()

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    // KeyboardToolbarView 为 candidateBarStyle 样式根节点, 这里生成一次，减少计算次数
    self.style = appearance.candidateBarStyle
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupSubview()

    combine()
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      setupAppearance()
      candidateBarView.setStyle(self.style)
    }
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    if isDoubaoToolbar {
      commonFunctionBar.addSubview(doubaoMenuButton)
      commonFunctionBar.addSubview(doubaoVoiceButton)
      commonFunctionBar.addSubview(doubaoDismissButton)
      addSubview(doubaoToastLabel)
      return
    }
    if keyboardContext.displayAppIconButton {
      commonFunctionBar.addSubview(iconButton)
    }
    if keyboardContext.displayKeyboardDismissButton {
      commonFunctionBar.addSubview(dismissKeyboardButton)
    }
  }

  override func activateViewConstraints() {
    var constraints: [NSLayoutConstraint] = [
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
    ]

    if isDoubaoToolbar {
      // ref4：圆形按钮直径约 33pt，两侧边距约 12pt，⌘ 与胶囊间距约 11pt；按钮中心比工具栏正中略低约 2pt。
      let d = DoubaoStyle.toolbarButtonDiameter
      let centerOffset: CGFloat = keyboardContext.interfaceOrientation.isLandscape ? 0 : 2
      constraints.append(contentsOf: [
        doubaoMenuButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor, constant: DoubaoStyle.toolbarSideMargin),
        doubaoMenuButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor, constant: centerOffset),
        doubaoMenuButton.widthAnchor.constraint(equalToConstant: d),
        doubaoMenuButton.heightAnchor.constraint(equalToConstant: d),

        doubaoVoiceButton.leadingAnchor.constraint(equalTo: doubaoMenuButton.trailingAnchor, constant: DoubaoStyle.toolbarSpacing),
        doubaoVoiceButton.centerYAnchor.constraint(equalTo: doubaoMenuButton.centerYAnchor),
        doubaoVoiceButton.widthAnchor.constraint(equalToConstant: DoubaoStyle.toolbarPillWidth),
        doubaoVoiceButton.heightAnchor.constraint(equalToConstant: d),

        doubaoDismissButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor, constant: -DoubaoStyle.toolbarSideMargin),
        doubaoDismissButton.centerYAnchor.constraint(equalTo: doubaoMenuButton.centerYAnchor),
        doubaoDismissButton.widthAnchor.constraint(equalToConstant: d),
        doubaoDismissButton.heightAnchor.constraint(equalToConstant: d),

        doubaoToastLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: centerOffset),
        doubaoToastLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        doubaoToastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
      ])
      NSLayoutConstraint.activate(constraints)
      return
    }

    if keyboardContext.displayAppIconButton {
      constraints.append(contentsOf: [
        iconButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
        iconButton.heightAnchor.constraint(equalTo: iconButton.widthAnchor),
        iconButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: iconButton.bottomAnchor),
        iconButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    if keyboardContext.displayKeyboardDismissButton {
      constraints.append(contentsOf: [
        dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        dismissKeyboardButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
        dismissKeyboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: dismissKeyboardButton.bottomAnchor),
        dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    NSLayoutConstraint.activate(constraints)
  }

  override func setupAppearance() {
    self.style = appearance.candidateBarStyle
    if isDoubaoToolbar {
      let dark = keyboardContext.hasDarkColorScheme
      let background = DoubaoStyle.toolbarButtonBackground(dark: dark)
      let foreground = DoubaoStyle.toolbarForeground(dark: dark)
      for view in [doubaoMenuButton, doubaoVoiceButton, doubaoDismissButton] as [UIView] {
        view.backgroundColor = background
        view.tintColor = foreground
      }
      doubaoMicImageView.tintColor = foreground
      doubaoVoiceLabel.textColor = foreground
      doubaoToastLabel.textColor = foreground
      return
    }
    if keyboardContext.displayAppIconButton {
      iconButton.tintColor = style.toolbarButtonFrontColor
    }
    if keyboardContext.displayKeyboardDismissButton {
      dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    }
  }

  func combine() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }

        // 检测是否启用内嵌编码
        guard !keyboardContext.enableEmbeddedInputMode else { return }
        if self.keyboardContext.keyboardType.isChineseNineGrid {
          // Debug
          // self.phoneticArea.text = inputKeys + " | " + self.rimeContext.t9UserInputKey
          candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
        } else {
          candidateBarView.phoneticLabel.text = $0
        }

        let userInputKey = rimeContext.userInputKey
        if !userInputKey.isEmpty, self.doubaoToastLabel.superview != nil {
          self.doubaoToastSerial += 1
          self.doubaoToastLabel.alpha = 0
          self.commonFunctionBar.alpha = 1
        }
        self.commonFunctionBar.isHidden = !userInputKey.isEmpty
        self.candidateBarView.isHidden = userInputKey.isEmpty
        if !candidateBarView.isHidden, candidateBarView.superview == nil {
          candidateBarView.setStyle(self.style)
          addSubview(candidateBarView)
          candidateBarView.fillSuperview()
        }
      }
      .store(in: &subscriptions)
  }

  @objc func doubaoButtonTouchDown(_ sender: UIView) {
    sender.backgroundColor = DoubaoStyle.toolbarButtonPressedBackground(dark: keyboardContext.hasDarkColorScheme)
  }

  @objc func doubaoButtonTouchEnd(_ sender: UIView) {
    sender.backgroundColor = DoubaoStyle.toolbarButtonBackground(dark: keyboardContext.hasDarkColorScheme)
  }

  /// 点击说话：离线版不支持语音，只在候选栏位置短暂提示，不报错、不联网。
  @objc func doubaoVoiceTouchUpAction() {
    actionHandler.handle(.press, on: .character(""))
    showDoubaoToast("离线版不支持语音")
  }

  func showDoubaoToast(_ text: String) {
    doubaoToastSerial += 1
    let serial = doubaoToastSerial
    doubaoToastLabel.text = text
    UIView.animate(withDuration: 0.15) {
      self.commonFunctionBar.alpha = 0
      self.doubaoToastLabel.alpha = 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
      guard let self = self, self.doubaoToastSerial == serial else { return }
      UIView.animate(withDuration: 0.25) {
        self.commonFunctionBar.alpha = 1
        self.doubaoToastLabel.alpha = 0
      }
    }
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func openHamsterAppTouchDownAction() {
    iconButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func openHamsterAppTouchUpAction() {
    iconButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
    actionHandler.handle(.release, on: .url(URL(string: "hamster://dev.fuxiao.app.hamster/main"), id: "openHamster"))
  }

  @objc func touchCancel() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    iconButton.backgroundColor = style.toolbarButtonBackgroundColor
  }
}
