import Foundation
import XCTest
@testable import HamsterKit

final class OfflineKeyboardSnapshotTest: XCTestCase {
  private typealias Snapshot = OfflineKeyboardSnapshot
  private typealias SnapshotError = OfflineKeyboardSnapshotError

  func testDefaultsAndRoundTrip() throws {
    let entry = try Snapshot.Entry(text: "你好👩‍💻", code: "nihao")
    let snapshot = try Snapshot(
      snapshotVersion: 4,
      resetEpoch: 2,
      entries: [entry],
      preferences: Snapshot.Preferences(suggestionsEnabled: false, localLearningEnabled: true)
    )
    XCTAssertEqual(try Snapshot.decodeJSON(snapshot.encodeJSON()), snapshot)

    let defaults = try Snapshot()
    XCTAssertEqual(defaults.formatVersion, Snapshot.currentFormatVersion)
    XCTAssertEqual(defaults.markers, Snapshot.Markers())
    XCTAssertTrue(defaults.entries.isEmpty)
    XCTAssertTrue(defaults.preferences.suggestionsEnabled)
    XCTAssertFalse(defaults.preferences.localLearningEnabled)
    XCTAssertEqual(try Snapshot.decodeJSON(defaults.encodeJSON()), defaults)
  }

  func testSharedFormatContainsNoFrequencyData() throws {
    let snapshot = try Snapshot(entries: [Snapshot.Entry(text: "词", code: "ci")])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.encodeJSON()) as? [String: Any])
    XCTAssertEqual(Set(object.keys), Set(["formatVersion", "snapshotVersion", "resetEpoch", "entries", "preferences"]))
    let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
    let first = try XCTUnwrap(entries.first)
    XCTAssertEqual(Set(first.keys), Set(["text", "code"]))
    let preferences = try XCTUnwrap(object["preferences"] as? [String: Any])
    XCTAssertEqual(Set(preferences.keys), Set(["suggestionsEnabled", "localLearningEnabled"]))
  }

  func testMissingOptionalFieldsUseDefaultsButMarkersAreRequired() throws {
    let minimal = Data(#"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":0}"#.utf8)
    XCTAssertEqual(try Snapshot.decodeJSON(minimal), try Snapshot())
    let partialPreferences = Data(#"{"formatVersion":1,"snapshotVersion":3,"resetEpoch":7,"preferences":{"localLearningEnabled":true}}"#.utf8)
    let result = try Snapshot.decodeJSON(partialPreferences)
    XCTAssertEqual(result.preferences, Snapshot.Preferences(localLearningEnabled: true))

    for json in [
      #"{"snapshotVersion":0,"resetEpoch":0}"#,
      #"{"formatVersion":1,"resetEpoch":0}"#,
      #"{"formatVersion":1,"snapshotVersion":0}"#,
      #"{"formatVersion":1,"snapshotVersion":-1,"resetEpoch":0}"#,
      #"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":null}"#,
      #"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":0,"entries":null}"#,
      #"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":0,"preferences":null}"#,
      #"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":0,"preferences":{"localLearningEnabled":null}}"#,
    ] {
      XCTAssertThrowsError(try Snapshot.decodeJSON(Data(json.utf8)), json)
    }
  }

  func testUnsupportedFormatIsRejectedAtConstructionAndDecode() throws {
    XCTAssertThrowsError(try Snapshot(formatVersion: 2)) {
      XCTAssertEqual($0 as? SnapshotError, .unsupportedFormatVersion(2))
    }
    let future = Data(#"{"formatVersion":2,"snapshotVersion":0,"resetEpoch":0}"#.utf8)
    XCTAssertThrowsError(try Snapshot.decodeJSON(future)) {
      XCTAssertEqual($0 as? SnapshotError, .unsupportedFormatVersion(2))
    }
    let old = Data(#"{"formatVersion":0,"snapshotVersion":0,"resetEpoch":0}"#.utf8)
    XCTAssertThrowsError(try Snapshot.decodeJSON(old)) {
      XCTAssertEqual($0 as? SnapshotError, .unsupportedFormatVersion(0))
    }
  }

  func testEntryLimitsUseUTF8BytesAndDoNotTrimInput() throws {
    let text = String(repeating: "a", count: Snapshot.Entry.maximumTextBytes)
    let code = String(repeating: "b", count: Snapshot.Entry.maximumCodeBytes)
    XCTAssertEqual(try Snapshot.Entry(text: text, code: code).text, text)
    XCTAssertEqual(try Snapshot.Entry(text: " 你好 ").text, " 你好 ")
    XCTAssertNoThrow(try Snapshot.Entry(text: String(repeating: "你", count: 85)))
    XCTAssertThrowsError(try Snapshot.Entry(text: String(repeating: "你", count: 86))) {
      XCTAssertEqual($0 as? SnapshotError, .invalidEntryText)
    }
    XCTAssertThrowsError(try Snapshot.Entry(text: text + "a")) {
      XCTAssertEqual($0 as? SnapshotError, .invalidEntryText)
    }
    XCTAssertThrowsError(try Snapshot.Entry(text: "词", code: code + "b")) {
      XCTAssertEqual($0 as? SnapshotError, .invalidEntryCode)
    }
  }

  func testEmptyWhitespaceAndControlCharactersAreRejected() throws {
    for text in ["", "  ", "\n", "a\u{0000}b", "a\u{0085}b"] {
      XCTAssertThrowsError(try Snapshot.Entry(text: text)) {
        XCTAssertEqual($0 as? SnapshotError, .invalidEntryText)
      }
    }
    for code in ["", "  ", "a\tb"] {
      XCTAssertThrowsError(try Snapshot.Entry(text: "词", code: code)) {
        XCTAssertEqual($0 as? SnapshotError, .invalidEntryCode)
      }
    }
    // Zero-width joiners are valid and important to emoji and some scripts.
    XCTAssertNoThrow(try Snapshot.Entry(text: "👩‍💻"))
  }

  func testEntryCountAndDuplicatesAreValidated() throws {
    let entries = try (0..<Snapshot.maximumEntries).map { try Snapshot.Entry(text: "词\($0)") }
    XCTAssertNoThrow(try Snapshot(entries: entries))
    XCTAssertThrowsError(try Snapshot(entries: entries + [Snapshot.Entry(text: "额外")])) {
      XCTAssertEqual($0 as? SnapshotError, .tooManyEntries)
    }
    let same = try Snapshot.Entry(text: "词", code: "ci")
    XCTAssertThrowsError(try Snapshot(entries: [same, same])) {
      XCTAssertEqual($0 as? SnapshotError, .duplicateEntry)
    }
    let composed = try Snapshot.Entry(text: "é")
    let decomposed = try Snapshot.Entry(text: "e\u{301}")
    XCTAssertThrowsError(try Snapshot(entries: [composed, decomposed])) {
      XCTAssertEqual($0 as? SnapshotError, .duplicateEntry)
    }
    // The same text with a different code is a distinct manual entry.
    XCTAssertNoThrow(try Snapshot(entries: [same, Snapshot.Entry(text: "词", code: "zi")]))
  }

  func testDecodingAlsoValidatesEntriesAndCount() throws {
    let invalidText = Data(#"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":0,"entries":[{"text":""}]}"#.utf8)
    XCTAssertThrowsError(try Snapshot.decodeJSON(invalidText)) {
      XCTAssertEqual($0 as? SnapshotError, .invalidEntryText)
    }
    let duplicates = Data(#"{"formatVersion":1,"snapshotVersion":0,"resetEpoch":0,"entries":[{"text":"词"},{"text":"词"}]}"#.utf8)
    XCTAssertThrowsError(try Snapshot.decodeJSON(duplicates)) {
      XCTAssertEqual($0 as? SnapshotError, .duplicateEntry)
    }
    let many = Array(repeating: #"{"text":"x"}"#, count: Snapshot.maximumEntries + 1).joined(separator: ",")
    let json = "{\"formatVersion\":1,\"snapshotVersion\":0,\"resetEpoch\":0,\"entries\":[\(many)]}"
    XCTAssertThrowsError(try Snapshot.decodeJSON(Data(json.utf8))) {
      XCTAssertEqual($0 as? SnapshotError, .tooManyEntries)
    }
  }

  func testJSONByteLimitIsEnforcedBeforeDecoding() throws {
    let oversized = Data(repeating: 0x20, count: Snapshot.maximumJSONBytes + 1)
    XCTAssertThrowsError(try Snapshot.decodeJSON(oversized)) {
      XCTAssertEqual($0 as? SnapshotError, .payloadTooLarge)
    }
    XCTAssertThrowsError(try Snapshot.decodeJSON(Data("not json".utf8)))
  }

  func testMarkerChangesAreIndependentAndNeverAssumeInitialReset() {
    let old = Snapshot.Markers(snapshotVersion: 5, resetEpoch: 7)
    XCTAssertEqual(old.change(since: nil), .initial)
    XCTAssertEqual(old.change(since: old), .unchanged)
    XCTAssertEqual(Snapshot.Markers(snapshotVersion: 6, resetEpoch: 7).change(since: old),
                   .changed(content: true, reset: false))
    XCTAssertEqual(Snapshot.Markers(snapshotVersion: 5, resetEpoch: 8).change(since: old),
                   .changed(content: false, reset: true))
    XCTAssertEqual(Snapshot.Markers(snapshotVersion: 6, resetEpoch: 8).change(since: old),
                   .changed(content: true, reset: true))
    XCTAssertEqual(Snapshot.Markers(snapshotVersion: 4, resetEpoch: 8).change(since: old), .stale)
    XCTAssertEqual(Snapshot.Markers(snapshotVersion: 6, resetEpoch: 6).change(since: old), .stale)
    let max = Snapshot.Markers(snapshotVersion: UInt64.max, resetEpoch: UInt64.max)
    XCTAssertEqual(max.change(since: max), .unchanged)
  }

  func testReplacementRejectsRollbackAndUnversionedContentChanges() throws {
    let old = try Snapshot(snapshotVersion: 5, resetEpoch: 7, entries: [Snapshot.Entry(text: "旧")])
    let unversioned = try Snapshot(snapshotVersion: 5, resetEpoch: 8, entries: [Snapshot.Entry(text: "新")])
    XCTAssertThrowsError(try unversioned.validateReplacement(of: old)) {
      XCTAssertEqual($0 as? SnapshotError, .contentVersionNotAdvanced)
    }
    let unversionedPreferences = try Snapshot(
      snapshotVersion: 5, resetEpoch: 7, entries: old.entries,
      preferences: Snapshot.Preferences(suggestionsEnabled: false)
    )
    XCTAssertThrowsError(try unversionedPreferences.validateReplacement(of: old)) {
      XCTAssertEqual($0 as? SnapshotError, .contentVersionNotAdvanced)
    }
    let rollback = try Snapshot(snapshotVersion: 6, resetEpoch: 6, entries: old.entries)
    XCTAssertThrowsError(try rollback.validateReplacement(of: old)) {
      XCTAssertEqual($0 as? SnapshotError, .staleMarkers)
    }
    let resetOnly = try Snapshot(snapshotVersion: 5, resetEpoch: 8, entries: old.entries)
    XCTAssertNoThrow(try resetOnly.validateReplacement(of: old))
    let contentOnly = try Snapshot(snapshotVersion: 6, resetEpoch: 7, entries: [Snapshot.Entry(text: "新")])
    XCTAssertNoThrow(try contentOnly.validateReplacement(of: old))
    XCTAssertNoThrow(try old.validateReplacement(of: old))
  }
}
