//
//  DoubaoGlyphView.swift
//
//  豆包风格按键上的自绘图形：「，。」键、空格中间的声波图标、「中/英」切换键。
//  全部用 Core Graphics 代码绘制（位置、尺寸按 ref4.jpg 量得），不使用任何豆包素材。
//

import UIKit

final class DoubaoGlyphView: UIView {
  enum Kind: Equatable {
    /// 「，。」键：上小「。」下「，」（英文键盘为上「.」下「,」）。
    case commaPeriod(chinese: Bool)
    /// 空格键中间的声波小图标（5 根竖条）。
    case spaceWave
    /// 「中/英」切换键：大字是当前语言，小字是另一种语言，中间两段弧形箭头。
    case chineseEnglish(chineseActive: Bool)
  }

  let kind: Kind
  private var primaryColor: UIColor
  private var isDark: Bool

  init(kind: Kind, primaryColor: UIColor, isDark: Bool) {
    self.kind = kind
    self.primaryColor = primaryColor
    self.isDark = isDark
    super.init(frame: .zero)
    isOpaque = false
    backgroundColor = .clear
    contentMode = .redraw
    isUserInteractionEnabled = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(primaryColor: UIColor, isDark: Bool) {
    guard primaryColor != self.primaryColor || isDark != self.isDark else { return }
    self.primaryColor = primaryColor
    self.isDark = isDark
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    let bounds = self.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }
    switch kind {
    case .commaPeriod(let chinese):
      drawCommaPeriod(in: bounds, chinese: chinese)
    case .spaceWave:
      drawSpaceWave(in: bounds)
    case .chineseEnglish(let chineseActive):
      drawChineseEnglish(in: bounds, chineseActive: chineseActive)
    }
  }

  // MARK: - 「，。」

  /// ref4：「。」圆心约在键高 0.33 处、直径约 4pt；「，」头部圆心约在 0.59 处，尾巴到约 0.74。
  private func drawCommaPeriod(in bounds: CGRect, chinese: Bool) {
    let w = bounds.width
    let h = bounds.height
    let unit = min(h / 47, 1.25)

    // 上：句号
    let periodCenter = CGPoint(x: w / 2, y: h * 0.33)
    let periodColor = DoubaoStyle.periodGlyph(dark: isDark)
    if chinese {
      let ring = UIBezierPath(arcCenter: periodCenter, radius: 2.1 * unit, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      ring.lineWidth = 1.1 * unit
      periodColor.setStroke()
      ring.stroke()
    } else {
      let dot = UIBezierPath(arcCenter: periodCenter, radius: 1.5 * unit, startAngle: 0, endAngle: .pi * 2, clockwise: true)
      periodColor.setFill()
      dot.fill()
    }

    // 下：逗号（圆头 + 向左下弯的尾巴）
    let r = 2.0 * unit
    let head = CGPoint(x: w / 2, y: h * 0.59)
    primaryColor.setFill()
    UIBezierPath(arcCenter: head, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
    let tail = UIBezierPath()
    tail.move(to: CGPoint(x: head.x + r * 0.55, y: head.y))
    tail.addQuadCurve(
      to: CGPoint(x: head.x - r * 0.9, y: head.y + r * 3.4),
      controlPoint: CGPoint(x: head.x + r * 1.0, y: head.y + r * 2.2))
    tail.lineWidth = r * 1.05
    tail.lineCapStyle = .round
    primaryColor.setStroke()
    tail.stroke()
  }

  // MARK: - 空格声波

  /// ref4：5 根竖条，宽约 3pt、中心距约 5pt，高约 4.7 / 6.9 / 13.5 / 7.6 / 4.0pt。
  private func drawSpaceWave(in bounds: CGRect) {
    let heights: [CGFloat] = [4.7, 6.9, 13.5, 7.6, 4.0]
    let barWidth: CGFloat = 2.9
    let pitch: CGFloat = 5
    let totalWidth = pitch * CGFloat(heights.count - 1) + barWidth
    let startX = bounds.midX - totalWidth / 2
    DoubaoStyle.spaceWave(dark: isDark).setFill()
    for (i, height) in heights.enumerated() {
      let rect = CGRect(x: startX + CGFloat(i) * pitch, y: bounds.midY - height / 2, width: barWidth, height: height)
      UIBezierPath(roundedRect: rect, cornerRadius: barWidth / 2).fill()
    }
  }

  // MARK: - 中/英

  /// ref4：「中」约 15pt 中粗、中心在 (0.30w, 0.39h)；「英」约 10.5pt 灰色、中心在 (0.66w, 0.66h)；
  /// 右上「┐」弧线约 x 0.61–0.75、y 0.36–0.46；左下「└」弧线约 x 0.24–0.42、y 0.65–0.74。
  private func drawChineseEnglish(in bounds: CGRect, chineseActive: Bool) {
    let w = bounds.width
    let h = bounds.height
    let secondary = DoubaoStyle.secondaryGlyph(dark: isDark)

    let bigText = chineseActive ? "中" : "英"
    let smallText = chineseActive ? "英" : "中"
    drawCentered(bigText, font: .systemFont(ofSize: 15, weight: .semibold), color: primaryColor, center: CGPoint(x: w * 0.30, y: h * 0.39))
    drawCentered(smallText, font: .systemFont(ofSize: 10.5, weight: .regular), color: secondary, center: CGPoint(x: w * 0.66, y: h * 0.66))

    let lineWidth: CGFloat = 1.1
    let radius = min(w, h) * 0.07

    let topRight = UIBezierPath()
    let trStart = CGPoint(x: w * 0.61, y: h * 0.36)
    let trCorner = CGPoint(x: w * 0.75, y: h * 0.36)
    let trEnd = CGPoint(x: w * 0.75, y: h * 0.46)
    topRight.move(to: trStart)
    topRight.addLine(to: CGPoint(x: trCorner.x - radius, y: trCorner.y))
    topRight.addQuadCurve(to: CGPoint(x: trCorner.x, y: trCorner.y + radius), controlPoint: trCorner)
    topRight.addLine(to: trEnd)

    let bottomLeft = UIBezierPath()
    let blStart = CGPoint(x: w * 0.24, y: h * 0.65)
    let blCorner = CGPoint(x: w * 0.24, y: h * 0.74)
    let blEnd = CGPoint(x: w * 0.42, y: h * 0.74)
    bottomLeft.move(to: blStart)
    bottomLeft.addLine(to: CGPoint(x: blCorner.x, y: blCorner.y - radius))
    bottomLeft.addQuadCurve(to: CGPoint(x: blCorner.x + radius, y: blCorner.y), controlPoint: blCorner)
    bottomLeft.addLine(to: blEnd)

    secondary.setStroke()
    for path in [topRight, bottomLeft] {
      path.lineWidth = lineWidth
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      path.stroke()
    }
  }

  private func drawCentered(_ text: String, font: UIFont, color: UIColor, center: CGPoint) {
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = attributed.size()
    attributed.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
  }
}
