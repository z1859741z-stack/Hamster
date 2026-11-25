//
//  KeyboardButtonShadowStyle.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2021-09-09.
//  Copyright © 2021-2023 Daniel Saidi. All rights reserved.
//

import UIKit

/**
 This style defines the shadow of a system keyboard button.
 
 该样式定义了键盘按键的阴影。
 
 You can modify the ``standard`` style to change the default,
 global style of all system keyboard buttons.
 
 您可以修改 ``standard`` 样式，以更改所有键盘按键的默认全局样式。
 */
public struct KeyboardButtonShadowStyle: Equatable {
  /**
   The color of the shadow.
   
   阴影的颜色
   */
  public var color: UIColor
    
  /**
   The size of the shadow, in points.

   阴影的大小（单位 pt）。渲染时同时用作垂直偏移和模糊半径：
   系统式柔和阴影向下偏移 size、模糊半径 size，默认 1。
   */
  public var size: CGFloat
  
  /**
   Create a system keyboard button shadow style.
   
   创建键盘按键阴影样式。
     
   - Parameters:
     - color: The color of the shadow, by default `.standardButtonShadow`.
     - size: The size of the shadow, by default `1`.
   */
  public init(
    color: UIColor = HamsterUIColor.shared.standardButtonShadow,
    size: CGFloat = 1
  ) {
    self.color = color
    self.size = size
  }
}

public extension KeyboardButtonShadowStyle {
  /**
   This style applies no shadow.
   
   这种样式没有阴影。
   */
  static var noShadow: KeyboardButtonShadowStyle {
    KeyboardButtonShadowStyle(color: .clear)
  }
    
  /**
   This standard style mimics the native iOS style.

   This can be set to change the standard value everywhere.
   */
  static var standard = KeyboardButtonShadowStyle()
}
