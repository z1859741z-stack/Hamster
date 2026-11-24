import Foundation

/// A small, versioned interchange format, not the keyboard's local frequency database.
///
/// The host app is the only intended writer; the keyboard should use the reader only.
/// This is an integration rule, not an App Group permission boundary: all entitled
/// processes can access the container. The caller supplies a trusted file URL and
/// is responsible for the container, file protection, backups and access policy.
public struct OfflineKeyboardSnapshot: Codable, Equatable {
  public static let currentFormatVersion = 1
  public static let maximumEntries = 4_096
  public static let maximumJSONBytes = 4 * 1_024 * 1_024

  /// A manually entered word or phrase and its optional input code. No usage count
  /// or learned text belongs in the shared snapshot.
  public struct Entry: Codable, Hashable {
    public static let maximumTextBytes = 256
    public static let maximumCodeBytes = 128

    public let text: String
    public let code: String?

    public init(text: String, code: String? = nil) throws {
      guard Self.isValid(text, maximumBytes: Self.maximumTextBytes) else {
        throw OfflineKeyboardSnapshotError.invalidEntryText
      }
      if let code = code, !Self.isValid(code, maximumBytes: Self.maximumCodeBytes) {
        throw OfflineKeyboardSnapshotError.invalidEntryCode
      }
      self.text = text
      self.code = code
    }

    private static func isValid(_ value: String, maximumBytes: Int) -> Bool {
      guard value.utf8.count <= maximumBytes,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
      // Reject C0/C1 controls without rejecting joiners used by many scripts/emoji.
      return !value.unicodeScalars.contains {
        $0.value <= 0x1F || (0x7F...0x9F).contains($0.value)
      }
    }

    private enum CodingKeys: String, CodingKey { case text, code }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let text = try container.decode(String.self, forKey: .text)
      let code = try container.decodeIfPresent(String.self, forKey: .code)
      try self.init(text: text, code: code)
    }
  }

  /// These switches only describe preferences; they do not implement suggestions or learning.
  /// Learning defaults off and any frequency data remains in the keyboard's own container.
  public struct Preferences: Codable, Equatable {
    public let suggestionsEnabled: Bool
    public let localLearningEnabled: Bool

    public init(suggestionsEnabled: Bool = true, localLearningEnabled: Bool = false) {
      self.suggestionsEnabled = suggestionsEnabled
      self.localLearningEnabled = localLearningEnabled
    }

    private enum CodingKeys: String, CodingKey { case suggestionsEnabled, localLearningEnabled }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      // Missing keys use documented defaults; explicit nulls and wrong types fail.
      suggestionsEnabled = try container.contains(.suggestionsEnabled)
        ? container.decode(Bool.self, forKey: .suggestionsEnabled) : true
      localLearningEnabled = try container.contains(.localLearningEnabled)
        ? container.decode(Bool.self, forKey: .localLearningEnabled) : false
    }
  }

  /// Content revision and reset generation are separate monotonic counters.
  /// The first snapshot may use zero for both. Never wrap either counter.
  public struct Markers: Codable, Equatable {
    public let snapshotVersion: UInt64
    public let resetEpoch: UInt64

    public init(snapshotVersion: UInt64 = 0, resetEpoch: UInt64 = 0) {
      self.snapshotVersion = snapshotVersion
      self.resetEpoch = resetEpoch
    }

    /// Compare with the last *successfully applied and persistently recorded* markers.
    /// A missing baseline is intentionally not treated as either a reset or no reset:
    /// the caller must decide how to handle any pre-existing local frequency data.
    public func change(since previous: Markers?) -> Change {
      guard let previous = previous else { return .initial }
      guard snapshotVersion >= previous.snapshotVersion,
            resetEpoch >= previous.resetEpoch else { return .stale }
      let contentChanged = snapshotVersion > previous.snapshotVersion
      let resetChanged = resetEpoch > previous.resetEpoch
      if !contentChanged && !resetChanged { return .unchanged }
      return .changed(content: contentChanged, reset: resetChanged)
    }
  }

  public enum Change: Equatable {
    case initial
    case unchanged
    case changed(content: Bool, reset: Bool)
    /// At least one counter went backwards. Do not apply the snapshot or reset.
    case stale
  }

  public let formatVersion: Int
  public let snapshotVersion: UInt64
  public let resetEpoch: UInt64
  public let entries: [Entry]
  public let preferences: Preferences

  public var markers: Markers {
    Markers(snapshotVersion: snapshotVersion, resetEpoch: resetEpoch)
  }

  /// `snapshotVersion` advances when entries or preferences change; `resetEpoch`
  /// advances when the host requests a local reset. Either may advance independently.
  public init(
    formatVersion: Int = OfflineKeyboardSnapshot.currentFormatVersion,
    snapshotVersion: UInt64 = 0,
    resetEpoch: UInt64 = 0,
    entries: [Entry] = [],
    preferences: Preferences = Preferences()
  ) throws {
    guard formatVersion == Self.currentFormatVersion else {
      throw OfflineKeyboardSnapshotError.unsupportedFormatVersion(formatVersion)
    }
    guard entries.count <= Self.maximumEntries else {
      throw OfflineKeyboardSnapshotError.tooManyEntries
    }
    guard Set(entries).count == entries.count else {
      throw OfflineKeyboardSnapshotError.duplicateEntry
    }
    self.formatVersion = formatVersion
    self.snapshotVersion = snapshotVersion
    self.resetEpoch = resetEpoch
    self.entries = entries
    self.preferences = preferences
  }

  private enum CodingKeys: String, CodingKey {
    case formatVersion, snapshotVersion, resetEpoch, entries, preferences
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Format and both counters are mandatory on the wire: missing is not a reset.
    let formatVersion = try container.decode(Int.self, forKey: .formatVersion)
    guard formatVersion == Self.currentFormatVersion else {
      throw OfflineKeyboardSnapshotError.unsupportedFormatVersion(formatVersion)
    }
    let snapshotVersion = try container.decode(UInt64.self, forKey: .snapshotVersion)
    let resetEpoch = try container.decode(UInt64.self, forKey: .resetEpoch)
    var entries: [Entry] = []
    if container.contains(.entries) {
      var array = try container.nestedUnkeyedContainer(forKey: .entries)
      if let count = array.count, count > Self.maximumEntries {
        throw OfflineKeyboardSnapshotError.tooManyEntries
      }
      while !array.isAtEnd {
        guard entries.count < Self.maximumEntries else {
          throw OfflineKeyboardSnapshotError.tooManyEntries
        }
        entries.append(try array.decode(Entry.self))
      }
    }
    let preferences = try container.contains(.preferences)
      ? container.decode(Preferences.self, forKey: .preferences) : Preferences()
    try self.init(formatVersion: formatVersion, snapshotVersion: snapshotVersion,
                  resetEpoch: resetEpoch, entries: entries, preferences: preferences)
  }

  /// Use this boundary for untrusted/stored JSON. Direct JSONDecoder use still
  /// validates the model, but cannot enforce a limit on the original input bytes.
  public static func decodeJSON(_ data: Data) throws -> OfflineKeyboardSnapshot {
    guard data.count <= maximumJSONBytes else {
      throw OfflineKeyboardSnapshotError.payloadTooLarge
    }
    return try JSONDecoder().decode(Self.self, from: data)
  }

  public func encodeJSON() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumJSONBytes else {
      throw OfflineKeyboardSnapshotError.payloadTooLarge
    }
    return data
  }

  /// A writer can use this when preparing a replacement. A reset does not have
  /// to advance the content revision, but changed entries/preferences do.
  public func validateReplacement(of previous: OfflineKeyboardSnapshot) throws {
    guard markers.change(since: previous.markers) != .stale else {
      throw OfflineKeyboardSnapshotError.staleMarkers
    }
    if (entries != previous.entries || preferences != previous.preferences)
      && snapshotVersion == previous.snapshotVersion {
      throw OfflineKeyboardSnapshotError.contentVersionNotAdvanced
    }
  }
}

/// Errors contain no word or code text, so logging an error need not expose entries.
public enum OfflineKeyboardSnapshotError: Error, Equatable {
  case unsupportedFormatVersion(Int)
  case invalidEntryText
  case invalidEntryCode
  case tooManyEntries
  case duplicateEntry
  case payloadTooLarge
  case invalidFileURL
  case staleMarkers
  case contentVersionNotAdvanced
}

/// Read-only API for the keyboard. Failures are propagated, never replaced by an
/// empty snapshot. A caller may keep its last successfully applied snapshot.
public struct OfflineKeyboardSnapshotReader {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func read() throws -> OfflineKeyboardSnapshot {
    guard fileURL.isFileURL else { throw OfflineKeyboardSnapshotError.invalidFileURL }
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var data = Data()
    // Read at most one byte past the cap, rather than loading an arbitrary file.
    while data.count <= OfflineKeyboardSnapshot.maximumJSONBytes {
      let remaining = OfflineKeyboardSnapshot.maximumJSONBytes + 1 - data.count
      let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
      if chunk.isEmpty { break }
      data.append(chunk)
    }
    return try OfflineKeyboardSnapshot.decodeJSON(data)
  }
}

/// Host-app-only API by convention. A single serialized writer is required; this
/// type does not lock, authenticate processes, create directories or prevent other
/// entitled App Group members from writing. Atomic replacement protects readers
/// against partial files, not against deletion, rollback, or loss after a crash.
public struct OfflineKeyboardSnapshotWriter {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func write(_ snapshot: OfflineKeyboardSnapshot) throws {
    guard fileURL.isFileURL else { throw OfflineKeyboardSnapshotError.invalidFileURL }
    let encoded = try snapshot.encodeJSON()
    let previous: OfflineKeyboardSnapshot?
    do {
      previous = try OfflineKeyboardSnapshotReader(fileURL: fileURL).read()
    } catch {
      let nsError = error as NSError
      let missing = (nsError.domain == NSCocoaErrorDomain &&
                     (nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError)) ||
                    (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(POSIXErrorCode.ENOENT.rawValue))
      guard missing else { throw error }
      previous = nil
    }
    if let previous = previous {
      try snapshot.validateReplacement(of: previous)
    }
    try encoded.write(to: fileURL, options: .atomic)
  }
}
