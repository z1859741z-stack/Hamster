//
//  CustomPhraseViewController.swift
//
//  常用语页：每条是“缩写 + 内容”，增删改后写进 App Group 的 JSON，
//  保存即自动触发 deployment()；键盘下次弹出时生效。
//  部署状态与用时显示在页面底部（实测计时，不编数字）。
//

import Combine
import HamsterUIKit
import UIKit

public class CustomPhraseViewController: NibLessViewController {
  public let customPhraseViewModel: CustomPhraseViewModel

  private var subscriptions = Set<AnyCancellable>()

  private lazy var tableView: UITableView = {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "CustomPhraseCell")
    tableView.register(ButtonTableViewCell.self, forCellReuseIdentifier: ButtonTableViewCell.identifier)
    tableView.delegate = self
    tableView.dataSource = self
    return tableView
  }()

  init(customPhraseViewModel: CustomPhraseViewModel) {
    self.customPhraseViewModel = customPhraseViewModel
    super.init()
    combine()
  }

  func combine() {
    customPhraseViewModel.reloadTablePublished
      .receive(on: DispatchQueue.main)
      .sink { [unowned self] _ in
        self.tableView.reloadData()
      }
      .store(in: &subscriptions)
  }

  override public func loadView() {
    title = "常用语"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .add, target: self, action: #selector(addPhrase)
    )
    view = tableView
  }

  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    tableView.reloadData()
  }

  // MARK: - 增改弹窗

  @objc func addPhrase() {
    presentEditAlert(title: "添加常用语", code: "", text: "") { [weak self] code, text in
      guard let self = self else { return }
      Task {
        do {
          try await self.customPhraseViewModel.addEntry(code: code, text: text)
          await MainActor.run { self.tableView.reloadData() }
        } catch {
          await MainActor.run { self.presentErrorAlert(message: CustomPhraseViewModel.errorMessage(for: error)) }
        }
      }
    }
  }

  func editPhrase(at index: Int) {
    let entry = customPhraseViewModel.entries[index]
    presentEditAlert(title: "编辑常用语", code: entry.code ?? "", text: entry.text) { [weak self] code, text in
      guard let self = self else { return }
      Task {
        do {
          try await self.customPhraseViewModel.updateEntry(at: index, code: code, text: text)
          await MainActor.run { self.tableView.reloadData() }
        } catch {
          await MainActor.run { self.presentErrorAlert(message: CustomPhraseViewModel.errorMessage(for: error)) }
        }
      }
    }
  }

  private func presentEditAlert(
    title: String, code: String, text: String,
    onSave: @escaping (String, String) -> Void
  ) {
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "缩写（小写字母和数字），如 dz"
      textField.text = code
      textField.autocapitalizationType = .none
      textField.autocorrectionType = .no
    }
    alert.addTextField { textField in
      textField.placeholder = "内容，如 我的地址是……"
      textField.text = text
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
      let code = alert.textFields?[0].text ?? ""
      let text = alert.textFields?[1].text ?? ""
      onSave(code, text)
    })
    present(alert, animated: true)
  }

  private func presentErrorAlert(message: String) {
    let alert = UIAlertController(title: "保存失败", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }
}

// MARK: - UITableViewDataSource / UITableViewDelegate

extension CustomPhraseViewController: UITableViewDataSource, UITableViewDelegate {
  public func numberOfSections(in tableView: UITableView) -> Int {
    2
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if section == 0 {
      return customPhraseViewModel.entries.isEmpty ? 1 : customPhraseViewModel.entries.count
    }
    return 1
  }

  public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    section == 0 ? "常用语" : nil
  }

  public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    if section == 0 {
      return "在键盘里输入缩写，就能打出对应内容。保存后自动部署，键盘下次弹出时生效。"
    }
    return customPhraseViewModel.deployStatusText
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if indexPath.section == 1 {
      let cell = tableView.dequeueReusableCell(withIdentifier: ButtonTableViewCell.identifier, for: indexPath)
      guard let cell = cell as? ButtonTableViewCell else { return cell }
      cell.updateWithSettingItem(SettingItemModel(
        text: "重新部署",
        type: .button,
        buttonAction: { [weak self] in
          self?.customPhraseViewModel.redeploy()
        }
      ))
      return cell
    }

    let cell = tableView.dequeueReusableCell(withIdentifier: "CustomPhraseCell", for: indexPath)
    if customPhraseViewModel.entries.isEmpty {
      var config = cell.defaultContentConfiguration()
      config.text = "暂无常用语，点右上角 + 添加"
      config.textProperties.color = .secondaryLabel
      cell.contentConfiguration = config
      cell.selectionStyle = .none
      return cell
    }

    let entry = customPhraseViewModel.entries[indexPath.row]
    var config = cell.defaultContentConfiguration()
    config.text = entry.text
    config.secondaryText = entry.code.map { "缩写：\($0)" } ?? ""
    cell.contentConfiguration = config
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if indexPath.section == 0, !customPhraseViewModel.entries.isEmpty {
      editPhrase(at: indexPath.row)
    }
  }

  public func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    guard indexPath.section == 0, !customPhraseViewModel.entries.isEmpty else { return nil }
    let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
      guard let self = self else { return }
      Task {
        await self.customPhraseViewModel.deleteEntry(at: indexPath.row)
        await MainActor.run { self.tableView.reloadData() }
        completion(true)
      }
    }
    return UISwipeActionsConfiguration(actions: [delete])
  }
}
