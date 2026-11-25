//
//  CandidateWordsView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import UIKit

/**
 候选栏视图
 */
public class CandidateBarView: NibLessView {
  /// 候选区状态
  public enum State {
    /// 展开
    case expand
    /// 收起
    case collapse

    func isCollapse() -> Bool {
      return self == .collapse
    }
  }

  private var style: CandidateBarStyle
  private var actionHandler: KeyboardActionHandler
  private var keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var subscriptions = Set<AnyCancellable>()

  /// TODO(临时诊断)：定位后删除。候选栏顶部一行小字。
  lazy var diagnosticLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .left
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    label.font = .systemFont(ofSize: 10)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 拼音Label
  lazy var phoneticLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.textAlignment = .left
    label.numberOfLines = 1
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.5
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  /// 划动分页的候选文字区域
  lazy var candidatesArea: CandidateWordsCollectionView = {
    let view = CandidateWordsCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext)
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 手动分页的候选文字区域
  lazy var candidatesPagingArea: CandidatesPagingCollectionView = {
    let view = CandidatesPagingCollectionView(
      style: style,
      keyboardContext: keyboardContext,
      actionHandler: actionHandler,
      rimeContext: rimeContext)
    view.backgroundColor = .clear
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 状态图片视图
  lazy var stateImageView: UIImageView = {
    let view = UIImageView(frame: .zero)
    view.contentMode = .center
    view.translatesAutoresizingMaskIntoConstraints = false
    view.image = stateImage(.collapse)
    return view
  }()

  /// 竖线
  lazy var verticalLine: UIView = {
    let view = UIView(frame: .zero)
    view.backgroundColor = .secondarySystemFill
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选区展开或收起控制按钮
  lazy var controlStateView: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .clear
    view.addSubview(stateImageView)
    view.addSubview(verticalLine)

    NSLayoutConstraint.activate([
      verticalLine.topAnchor.constraint(equalTo: view.topAnchor, constant: 3),
      view.bottomAnchor.constraint(equalTo: verticalLine.bottomAnchor, constant: 3),
      view.leadingAnchor.constraint(equalTo: verticalLine.leadingAnchor),
      verticalLine.widthAnchor.constraint(equalToConstant: 1),

      stateImageView.leadingAnchor.constraint(equalTo: verticalLine.trailingAnchor),
      stateImageView.topAnchor.constraint(equalTo: view.topAnchor),
      stateImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stateImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])

    // 添加状态控制
    view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(changeState)))
    return view
  }()

  // MARK: - 计算属性

  /// 布局配置
  private var layoutConfig: KeyboardLayoutConfiguration {
    .standard(for: keyboardContext)
  }

  init(style: CandidateBarStyle, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.style = style
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupContentView()

    // TODO(临时诊断)：定位后删除
    diagnosticLabel.text = rimeContext.diagnosticText
    rimeContext.diagnosticTextPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.diagnosticLabel.text = $0 }
      .store(in: &subscriptions)
  }

  func setupContentView() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  /// 构建视图层次
  override public func constructViewHierarchy() {
    // TODO(临时诊断)：定位后删除
    addSubview(diagnosticLabel)
    // 非内嵌模式添加拼写区域
    if !keyboardContext.enableEmbeddedInputMode {
      addSubview(phoneticLabel)
    }
    if keyboardContext.swipePaging {
      addSubview(candidatesArea)
      addSubview(controlStateView)
    } else {
      addSubview(candidatesPagingArea)
    }
  }

  /// 激活视图约束
  override public func activateViewConstraints() {
    let buttonInsets = layoutConfig.buttonInsets
    let codingAreaHeight: CGFloat = keyboardContext.heightOfCodingArea
    let controlStateHeight: CGFloat = keyboardContext.heightOfToolbar - (keyboardContext.enableEmbeddedInputMode ? 0 : codingAreaHeight)
    let candidatesView = keyboardContext.swipePaging ? candidatesArea : candidatesPagingArea

    // TODO(临时诊断)：定位后删除。诊断行占顶部 16pt，下方内容整体下移。
    NSLayoutConstraint.activate([
      diagnosticLabel.topAnchor.constraint(equalTo: topAnchor),
      diagnosticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
      diagnosticLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right),
      diagnosticLabel.heightAnchor.constraint(equalToConstant: 16)
    ])

    /// 内嵌模式
    if keyboardContext.enableEmbeddedInputMode {
      if keyboardContext.swipePaging {
        NSLayoutConstraint.activate([
          candidatesView.topAnchor.constraint(equalTo: diagnosticLabel.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: controlStateView.leadingAnchor),

          controlStateView.heightAnchor.constraint(equalTo: controlStateView.widthAnchor, multiplier: 1.0),
          controlStateView.topAnchor.constraint(equalTo: topAnchor),
          controlStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
          controlStateView.heightAnchor.constraint(equalToConstant: controlStateHeight)
        ])
      } else {
        NSLayoutConstraint.activate([
          candidatesView.topAnchor.constraint(equalTo: diagnosticLabel.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right)
        ])
      }
    } else {
      if keyboardContext.swipePaging {
        NSLayoutConstraint.activate([
          phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
          phoneticLabel.topAnchor.constraint(equalTo: diagnosticLabel.bottomAnchor),
          phoneticLabel.heightAnchor.constraint(equalToConstant: codingAreaHeight),

          candidatesView.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: controlStateView.leadingAnchor),

          controlStateView.heightAnchor.constraint(equalTo: controlStateView.widthAnchor, multiplier: 1.0),
          controlStateView.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor),
          controlStateView.trailingAnchor.constraint(equalTo: trailingAnchor),
          controlStateView.heightAnchor.constraint(equalToConstant: controlStateHeight)
        ])
      } else {
        NSLayoutConstraint.activate([
          phoneticLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          phoneticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
          phoneticLabel.topAnchor.constraint(equalTo: diagnosticLabel.bottomAnchor),
          phoneticLabel.heightAnchor.constraint(equalToConstant: codingAreaHeight),

          candidatesView.topAnchor.constraint(equalTo: phoneticLabel.bottomAnchor),
          candidatesView.bottomAnchor.constraint(equalTo: bottomAnchor),
          candidatesView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonInsets.left),
          candidatesView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -buttonInsets.right)
        ])
      }
    }
  }

  override public func setupAppearance() {
    phoneticLabel.font = style.phoneticTextFont
    phoneticLabel.textColor = style.phoneticTextColor
    stateImageView.tintColor = style.candidateTextColor

    if keyboardContext.swipePaging {
      candidatesArea.setupStyle(style)
    } else {
      candidatesPagingArea.setupStyle(style)
    }
  }

  func setStyle(_ style: CandidateBarStyle) {
    self.style = style
    setupAppearance()
  }

  @objc func changeState() {
    let state: State = keyboardContext.candidatesViewState.isCollapse() ? .expand : .collapse
    stateImageView.image = stateImage(state)
    verticalLine.isHidden = state == .expand
    keyboardContext.candidatesViewState = state
  }

  // 状态图片
  func stateImage(_ state: State) -> UIImage? {
    let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
    return state == .collapse
      ? UIImage(systemName: "chevron.down", withConfiguration: config)
      : UIImage(systemName: "chevron.up", withConfiguration: config)
  }
}
