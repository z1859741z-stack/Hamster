//
//  SimplePreferencesViewController.swift
//
//  精简设置页：候选个数、触感开关+强度、中文标点全/半角、Emoji 候选开关。
//

import HamsterUIKit
import UIKit

public class SimplePreferencesViewController: NibLessViewController {
  public let viewModel: SimplePreferencesViewModel

  init(viewModel: SimplePreferencesViewModel) {
    self.viewModel = viewModel
    super.init()
  }

  override public func loadView() {
    title = "偏好设置"
    view = SimplePreferencesRootView(viewModel: viewModel)
  }
}
