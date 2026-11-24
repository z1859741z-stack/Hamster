import AppIntents
@available(iOS 16.0, *)
struct RimeSyncIntent: AppIntent {
  static var title: LocalizedStringResource = "RIME 同步"
  static var openAppWhenRun: Bool { false }
  static var description = IntentDescription("仓输入法 - 离线版本不支持 RIME 同步")
  func perform() async throws -> some ReturnsValue & ProvidesDialog {
    .result(dialog: .init("离线版本不支持 RIME 同步"))
  }
}
