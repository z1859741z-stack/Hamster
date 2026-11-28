//
//  DoubaoStyle.swift
//
//  「豆包风格」外观的取色与尺寸常量。
//  只仿外观与布局：所有数值由豆包输入法 iOS 版截图用 PIL 取色/量得（见各处注释），
//  不含豆包任何代码或素材；图标一律用 SF Symbols 或代码绘制。
//
//  浅色参考：ref4.jpg（无输入）、ref2.jpg（候选栏）；深色参考：ref3.jpg。
//  键盘底色不自己画：沿用近乎透明的背景，让系统键盘底色透上来
//  （实测浅色 225,226,230 与豆包截图的 225,226,230 一致，且不会和系统地球键那条出现分界）。
//

import UIKit

enum DoubaoStyle {
  // MARK: - 按键底色

  /// 字母键 / 空格 / ，。键 / 中英键：浅色纯白（ref4 取色 255,255,255）。
  static let lightKey = UIColor.white
  /// 字母键按下：浅色用功能键的灰。
  static let lightKeyPressed = rgb(198, 201, 208)
  /// 功能键（⇧ ⌫ 123 换行）：浅色 ref4 取色 198,201,208 = #C6C9D0。
  static let lightFunctionKey = rgb(198, 201, 208)
  /// 功能键按下：浅色变白（与系统键盘一致）。
  static let lightFunctionKeyPressed = UIColor.white

  /// 字母键：深色 ref3 取色 102,102,102 = #666666。
  static let darkKey = rgb(102, 102, 102)
  static let darkKeyPressed = rgb(61, 61, 61)
  /// 功能键：深色 ref3 取色 61,61,61 = #3D3D3D。
  static let darkFunctionKey = rgb(61, 61, 61)
  static let darkFunctionKeyPressed = rgb(102, 102, 102)

  /// 蓝色回车键（发送/搜索/前往/完成…）：ref4 取色 78,132,254 = #4E84FE。按下色为估值。
  static let returnBlue = rgb(78, 132, 254)
  static let returnBluePressed = rgb(58, 104, 214)

  // MARK: - 文字 / 图标

  /// 按键主文字：浅色纯黑（ref4 0,0,0），深色纯白。
  static func keyForeground(dark: Bool) -> UIColor { dark ? .white : .black }

  /// 中英键上的小「英」与弧形箭头：浅色 ref4 取色约 171,171,171。
  static func secondaryGlyph(dark: Bool) -> UIColor { dark ? rgb(170, 170, 170) : rgb(171, 171, 171) }

  /// ，。键上的小「。」：浅色 ref4 取色约 143,143,143。
  static func periodGlyph(dark: Bool) -> UIColor { dark ? rgb(185, 185, 185) : rgb(143, 143, 143) }

  /// 空格中间的声波图标：浅色 ref4 取色约 142,142,142。
  static func spaceWave(dark: Bool) -> UIColor { dark ? rgb(190, 190, 190) : rgb(142, 142, 142) }

  // MARK: - 阴影

  /// 按键底部细阴影：浅色在 225 的底色上压到约 192（≈ 黑 15%），约 1pt 硬边无模糊；深色 43→37（≈ 黑 14%），深色加重一点更明显。
  static func keyShadow(dark: Bool) -> UIColor { dark ? UIColor.black.withAlphaComponent(0.35) : UIColor.black.withAlphaComponent(0.15) }
  static let keyShadowOffset: CGFloat = 1.2

  // MARK: - 工具栏（未输入时）

  /// 圆形按钮 / 「点击说话」胶囊底色：浅色纯白（ref4），深色用字母键的灰（无深色参考图，估值）。
  static func toolbarButtonBackground(dark: Bool) -> UIColor { dark ? darkKey : .white }
  static func toolbarButtonPressedBackground(dark: Bool) -> UIColor { dark ? darkKeyPressed : lightKeyPressed }
  /// 工具栏图标与「点击说话」文字：浅色 ref4 取色约 117,117,117。
  static func toolbarForeground(dark: Bool) -> UIColor { dark ? rgb(215, 215, 215) : rgb(117, 117, 117) }

  /// 工具栏圆形按钮直径（ref4 90px ≈ 33pt）、胶囊宽（293px ≈ 107pt）、两侧边距（33px ≈ 12pt）、按钮间距（31px ≈ 11pt）。
  static let toolbarButtonDiameter: CGFloat = 33
  static let toolbarPillWidth: CGFloat = 107
  static let toolbarSideMargin: CGFloat = 12
  static let toolbarSpacing: CGFloat = 11

  // MARK: - 候选栏

  /// 候选字：ref2 量得约 20pt 黑色；首选放大到 24pt 并加一层浅色圆角高亮（ref2 首选的「放大镜」近似）。
  static let candidateFontSize: CGFloat = 20
  static let preferredCandidateFontSize: CGFloat = 24
  static func candidateText(dark: Bool) -> UIColor { dark ? .white : .black }
  static func preferredCandidateBackground(dark: Bool) -> UIColor {
    dark ? UIColor.white.withAlphaComponent(0.14) : UIColor.white.withAlphaComponent(0.6)
  }

  static func phoneticText(dark: Bool) -> UIColor { dark ? rgb(190, 190, 190) : rgb(110, 110, 110) }

  // MARK: - 辅助

  static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
    UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
  }
}
