//
//  SimplePreferencesRootView.swift
//
//  精简设置页的表：Toggle + Stepper 两种 cell，复用现有设置表的渲染方式。
//

import Combine
import HamsterUIKit
import UIKit

public class SimplePreferencesRootView: NibLessView {
  private let viewModel: SimplePreferencesViewModel

  lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(ToggleTableViewCell.self, forCellReuseIdentifier: ToggleTableViewCell.identifier)
    tableView.register(StepperTableViewCell.self, forCellReuseIdentifier: StepperTableViewCell.identifier)
    tableView.register(SliderTableViewCell.self, forCellReuseIdentifier: SliderTableViewCell.identifier)
    tableView.register(SettingTableViewCell.self, forCellReuseIdentifier: SettingTableViewCell.identifier)
    return tableView
  }()

  public init(frame: CGRect = .zero, viewModel: SimplePreferencesViewModel) {
    self.viewModel = viewModel
    super.init(frame: frame)
    // 豆包风格 / 液态玻璃互斥：一个打开时另一个自动关，刷新表让开关同步。
    viewModel.reloadHandler = { [weak self] in
      DispatchQueue.main.async {
        self?.tableView.reloadData()
      }
    }
    constructViewHierarchy()
    activateViewConstraints()
  }

  override public func constructViewHierarchy() {
    addSubview(tableView)
    tableView.delegate = self
    tableView.dataSource = self
  }

  override public func activateViewConstraints() {
    tableView.fillSuperview()
  }

  override public func didMoveToWindow() {
    super.didMoveToWindow()
    if let _ = window {
      tableView.reloadData()
    }
  }
}

extension SimplePreferencesRootView: UITableViewDataSource {
  public func numberOfSections(in tableView: UITableView) -> Int {
    viewModel.settings.count
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return viewModel.settings[section].items.count
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let settingItem = viewModel.settings[indexPath.section].items[indexPath.row]
    if settingItem.displayAsSlider {
      let cell = tableView.dequeueReusableCell(withIdentifier: SliderTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? SliderTableViewCell else { return cell }
      cell.updateWithSettingItem(settingItem)
      return cell
    }
    if settingItem.type == .step {
      let cell = tableView.dequeueReusableCell(withIdentifier: StepperTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? StepperTableViewCell else { return cell }
      cell.updateWithSettingItem(settingItem)
      return cell
    }

    let cell = tableView.dequeueReusableCell(withIdentifier: ToggleTableViewCell.identifier, for: indexPath)
    guard let cell = cell as? ToggleTableViewCell else { return cell }
    cell.updateWithSettingItem(settingItem)
    return cell
  }

  public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    viewModel.settings[section].title
  }

  public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
    guard let footer = viewModel.settings[section].footer else { return nil }
    return TableFooterView(footer: footer)
  }
}

extension SimplePreferencesRootView: UITableViewDelegate {
  public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: false)
  }
}
