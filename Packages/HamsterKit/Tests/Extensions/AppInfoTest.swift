import XCTest
@testable import HamsterKit

final class AppInfoTest: XCTestCase {
  func testVersionBuildAndCommitAreDisplayed() {
    XCTAssertEqual(
      AppInfo.displayVersion(version: "3.0.0", build: "42", commit: "1234abcd"),
      "版本 3.0.0 · 构建 42 · 提交 1234abcd"
    )
  }

  func testMissingOrUnexpandedBuildMetadataIsNotReportedAsActual() {
    XCTAssertEqual(
      AppInfo.displayVersion(version: nil, build: "", commit: "$(HAMSTER_GIT_COMMIT)"),
      "版本 未知 · 构建 未知 · 提交 未知"
    )
  }
}
