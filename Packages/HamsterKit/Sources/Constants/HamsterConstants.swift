//
//  HamsterConstants.swift
//
//
//  Created by morse on 2023/7/3.
//

import Foundation

/// Hamster 应用常量
public enum HamsterConstants {
  /// AppGroup ID
  public static let appGroupName = "group.dev.fuxiao.app.Hamster"

  /// keyboard Bundle ID
  public static let keyboardBundleID = "dev.fuxiao.app.Hamster.HamsterKeyboard"

  /// 跳转至系统添加键盘URL
  public static let addKeyboardPath = "app-settings:root=General&path=Keyboard/KEYBOARDS"

  // MARK: 与Squirrel.app保持一致

  /// RIME 预先构建的数据目录中
  public static let rimeSharedSupportPathName = "SharedSupport"

  /// RIME UserData目录
  public static let rimeUserPathName = "Rime"

  /// RIME 内置输入方案及配置zip包
  public static let inputSchemaZipFile = "SharedSupport.zip"

  /// 仓内置方案 zip 包
  public static let userDataZipFile = "rime-ice.zip"

  /// 语法模型（万象）文件：octagram 插件运行时从 SharedSupport 里只读加载。
  /// 373 MB 的二进制文件，主 App 只在缺失或 sha256 变了才拷进 App Group，
  /// 键盘直接读组里的路径，绝不复制进键盘沙盒。
  public static let grammarModelFileName = "wanxiang-lts-zh-hans.gram"

  /// 语法模型补丁文件：rime_ice 的 .custom.yaml，引用上面的模型。
  public static let grammarModelSchemaPatchFileName = "rime_ice.custom.yaml"

  /// APP URL
  /// 注意: 此值需要与info.plist中的参数保持一致
  public static let appURL = "hamster://dev.fuxiao.app.hamster"
}
