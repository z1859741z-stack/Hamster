//
//  SliderTableViewCell.swift
//
//  精简设置页的滑杆行（「键盘高度」80%–130%）：上面一行标题 + 当前数值，下面一根滑杆。
//  拖动时只刷新数值文字，松手后才写配置（避免拖动过程中反复写 App Group 的 plist）。
//

import HamsterUIKit
import UIKit

class SliderTableViewCell: NibLessTableViewCell {
  static let identifier = "SliderTableViewCell"

  public var settingItem: SettingItemModel? = nil

  private let titleLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private let valueLabel: UILabel = {
    let label = UILabel(frame: .zero)
    label.font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.labelFontSize, weight: .regular)
    label.textColor = .secondaryLabel
    label.textAlignment = .right
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var slider: UISlider = {
    let slider = UISlider(frame: .zero)
    slider.translatesAutoresizingMaskIntoConstraints = false
    slider.isContinuous = true
    slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
    slider.addTarget(self, action: #selector(sliderReleased(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    return slider
  }()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none

    contentView.addSubview(titleLabel)
    contentView.addSubview(valueLabel)
    contentView.addSubview(slider)

    let margins = contentView.layoutMarginsGuide
    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: margins.topAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),

      valueLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
      valueLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

      slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      slider.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      slider.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      slider.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
    ])
  }

  func updateWithSettingItem(_ item: SettingItemModel) {
    settingItem = item
    titleLabel.text = item.text
    slider.minimumValue = Float(item.minValue)
    slider.maximumValue = Float(item.maxValue)
    let value = item.sliderValue?() ?? item.minValue
    slider.value = Float(value)
    valueLabel.text = text(for: value)
  }

  private func snapped(_ raw: Float) -> Double {
    guard let item = settingItem else { return Double(raw) }
    let step = item.stepValue > 0 ? item.stepValue : 1
    let value = (Double(raw) / step).rounded() * step
    return min(max(value, item.minValue), item.maxValue)
  }

  private func text(for value: Double) -> String {
    settingItem?.sliderValueText?(value) ?? String(Int(value))
  }

  @objc private func sliderChanged(_ sender: UISlider) {
    valueLabel.text = text(for: snapped(sender.value))
  }

  @objc private func sliderReleased(_ sender: UISlider) {
    let value = snapped(sender.value)
    sender.setValue(Float(value), animated: true)
    valueLabel.text = text(for: value)
    settingItem?.valueChangeHandled?(value)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    titleLabel.text = ""
    valueLabel.text = ""
  }
}
