//
//  GeneralConfiguration.swift
//
//
//  Created by morse on 2023/6/30.
//

import Foundation

/// 应用通用配置
public struct GeneralConfiguration: Codable, Hashable {
  /// 编辑器：是否换行
  public var textEditorLineWrappingEnabled: Bool?

  public init(textEditorLineWrappingEnabled: Bool? = nil) {
    self.textEditorLineWrappingEnabled = textEditorLineWrappingEnabled
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.textEditorLineWrappingEnabled = try container.decodeIfPresent(Bool.self, forKey: .textEditorLineWrappingEnabled)
  }

  enum CodingKeys: CodingKey {
    case textEditorLineWrappingEnabled
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(self.textEditorLineWrappingEnabled, forKey: .textEditorLineWrappingEnabled)
  }
}
