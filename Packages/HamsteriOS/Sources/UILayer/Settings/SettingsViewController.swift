//
//  SettingsViewController.swift
//
//  Created by morse on 2023/6/12.
//

import HamsterKit
import HamsterUIKit
import OSLog
import ProgressHUD
import UIKit

protocol SettingsViewModelFactory {
  func makeSettingsViewModel() -> SettingsViewModel
}

public class SettingsViewController: NibLessViewController {
  // MARK: - properties

  private var settingsViewModel: SettingsViewModel
  private var rimeViewModel: RimeViewModel
  private var backupViewModel: BackupViewModel

  init(settingsViewModel: SettingsViewModel, rimeViewModel: RimeViewModel, backupViewModel: BackupViewModel) {
    self.settingsViewModel = settingsViewModel
    self.rimeViewModel = rimeViewModel
    self.backupViewModel = backupViewModel
    super.init()
  }
}

// MARK: override UIViewController

public extension SettingsViewController {
  override func loadView() {
    title = "输入法设置"
    view = SettingsRootView(settingsViewModel: settingsViewModel, rimeViewModel: rimeViewModel, backupViewModel: backupViewModel)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // App 内更新检查（公开仓库 Releases API，无 token；一天最多查一次、同一版本只提醒一次）。
    AppUpdateChecker.shared.checkAndPromptIfNeeded(from: self)
    Task {
      do {
        try await self.settingsViewModel.loadAppData()
      } catch {
        ProgressHUD.failed("导入数据异常：\(error.localizedDescription)", interaction: false, delay: 3)
        Logger.statistics.error("load app data error: \(error)")
      }
    }
  }
}
