//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(os)
public import Logging
import SensitivityAttribute
import os

/// A sensitivity-aware log handler for the Darwin unified logging system that maps sensitivity values
/// to the OSLog privacy model.
///
/// ## Usage
///
/// ```swift
/// let handler = OSLogHandler(subsystem: "com.example.myapp", category: "network")
/// let logger = Logger(label: "network") { _ in handler }
///
/// let userId = "12345"
/// logger.info("User logged in", metadata: [
///     "user.id": "\(userId, sensitivity: .sensitive)",
///     "action": "\(\"login\", sensitivity: .public)",
/// ])
/// ```
///
/// ## Redaction behavior
///
/// - ``Sensitivity/public`` maps to OSLog `privacy: .public` and stays visible.
/// - Everything else maps to `privacy: .private` and shows as `<private>`. This includes
///   ``Sensitivity/sensitive``, untagged values, and future `Sensitivity` cases.
/// - The message itself is always `privacy: .public`. OSLog would otherwise redact every dynamic message.
///   Keep sensitive data in metadata, not the message.
///
/// Pass a ``MetadataFormat`` to the initializer to select the text of the metadata in the log message. The default is
/// `key=value` pairs.
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct OSLogHandler: LogHandler {
    /// The text format of the metadata in a log message.
    @nonexhaustive
    public enum MetadataFormat: Sendable {
        /// Writes `key=value` pairs. This is the default.
        case keyValue

        /// Writes the public and the sensitive metadata as one JSON object each. An object without entries is `{}`.
        ///
        /// For example, `Upload failed public={"reason":"disk full"} sensitive=<private>`. A container is public only
        /// when every value inside it is tagged ``Sensitivity/public``. A container without values is sensitive.
        case json
    }

    @usableFromInline package let metadataFormat: MetadataFormat

    @usableFromInline
    internal var osLogger: os.Logger

    /// A parallel `OSLog` handle, used only to query enablement for ``logLevel``. `os.Logger` itself cannot
    /// report which levels the system has enabled.
    internal let osLog: OSLog

    @usableFromInline package var base = PartitionedMetadata<KeyValueFragmentWriter>()

    @usableFromInline package var jsonBase = PartitionedMetadata<JSONFragmentWriter>()

    /// Base metadata as one dictionary.
    ///
    /// Reunites the two halves. The setter re-splits and re-flattens them.
    public var metadata: Logging.Logger.Metadata {
        get {
            switch self.metadataFormat {
            case .keyValue: return self.base.metadata
            case .json: return self.jsonBase.metadata
            }
        }
        set {
            switch self.metadataFormat {
            case .keyValue: self.base.metadata = newValue
            case .json: self.jsonBase.metadata = newValue
            }
        }
    }

    /// Supplies metadata to attach to every log message, resolved fresh at emission time.
    ///
    /// The handler merges this provider's output with the event's own metadata.
    /// The event's metadata wins on key conflicts.
    public var metadataProvider: Logging.Logger.MetadataProvider?

    /// Explicit log-level override. `nil` means derive the level from the system's per-type enablement.
    internal var explicitLogLevel: Logging.Logger.Level?

    /// The effective log level.
    ///
    /// With no override, this derives from the system's current per-type enablement. A disabled level drops via a
    /// cheap comparison instead of building the log line. Assigning a value installs an explicit override that wins
    /// from then on. This preserves `LogHandler`'s value-semantics contract. System enablement is process-wide, so the
    /// derived value can legitimately differ across processes and change at runtime.
    public var logLevel: Logging.Logger.Level {
        get { self.explicitLogLevel ?? Self.systemLogLevel(self.osLog) }
        set { self.explicitLogLevel = newValue }
    }

    /// Creates an OSLog handler with the specified subsystem, category, and metadata format.
    ///
    /// - Parameters:
    ///   - subsystem: Reverse-DNS identifier for the subsystem, such as `"com.example.myapp"`.
    ///   - category: Category for filtering in Console.app or with `log`.
    ///   - metadataFormat: The text format of the metadata in a log message.
    ///     The default is ``MetadataFormat/keyValue``.
    public init(subsystem: String, category: String, metadataFormat: MetadataFormat = .keyValue) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        self.osLog = OSLog(subsystem: subsystem, category: category)
        self.metadataFormat = metadataFormat
    }

    /// Emits a log event to the Darwin unified logging system.
    ///
    /// This method partitions the event's metadata into public and private based on
    /// each value's ``Sensitivity``, maps `event.level` to the closest `OSLogType`,
    /// and emits a single `os.Logger` call.
    /// The message text itself is always `privacy: .public`.
    @inlinable
    public func log(event: LogEvent) {
        switch self.metadataFormat {
        case .keyValue: self.logKeyValue(event: event)
        case .json: self.logJSON(event: event)
        }
    }

    /// Emits a log event with the metadata as `key=value` pairs.
    @inlinable
    internal func logKeyValue(event: LogEvent) {
        let level = Self.osLogType(for: event.level)

        let (publicString, privateString) = self.base.fragments(forEmission: self.emissionTimeMetadata(for: event))

        switch (publicString.isEmpty, privateString.isEmpty) {
        case (false, false):
            self.osLogger.log(
                level: level,
                "\(event.message.description, privacy: .public) \(publicString, privacy: .public) \(privateString, privacy: .private)"
            )
        case (false, true):
            self.osLogger.log(
                level: level,
                "\(event.message.description, privacy: .public) \(publicString, privacy: .public)"
            )
        case (true, false):
            self.osLogger.log(
                level: level,
                "\(event.message.description, privacy: .public) \(privateString, privacy: .private)"
            )
        case (true, true):
            self.osLogger.log(level: level, "\(event.message.description, privacy: .public)")
        }
    }

    /// Emits a log event with the metadata as JSON objects.
    @usableFromInline
    internal func logJSON(event: LogEvent) {
        let (publicObject, sensitiveObject) = self.jsonObjects(for: event)
        self.osLogger.log(
            level: Self.osLogType(for: event.level),
            "\(event.message.description, privacy: .public) public=\(publicObject, privacy: .public) sensitive=\(sensitiveObject, privacy: .private)"
        )
    }

    /// The public and the sensitive JSON object of one log call. An object without entries is `{}`.
    @usableFromInline
    internal func jsonObjects(for event: LogEvent) -> (publicObject: String, sensitiveObject: String) {
        let (publicObject, sensitiveObject) = self.jsonBase.fragments(
            forEmission: self.emissionTimeMetadata(for: event)
        )
        return (publicObject.isEmpty ? "{}" : publicObject, sensitiveObject.isEmpty ? "{}" : sensitiveObject)
    }

    /// Accesses base metadata by key.
    ///
    /// A read checks both the public and private partitions. A write puts the new value into a
    /// partition based on its ``Sensitivity``; setting `nil` removes the key from both partitions.
    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get {
            switch self.metadataFormat {
            case .keyValue: return self.base[key]
            case .json: return self.jsonBase[key]
            }
        }
        set {
            switch self.metadataFormat {
            case .keyValue: self.base[key] = newValue
            case .json: self.jsonBase[key] = newValue
            }
        }
    }

    // MARK: - Pure helpers (package access for testing)

    /// The public and the private text of one log call.
    package func fragments(for event: LogEvent) -> (publicFragment: String, privateFragment: String) {
        switch self.metadataFormat {
        case .keyValue:
            let (publicFragment, sensitiveFragment) = self.base.fragments(
                forEmission: self.emissionTimeMetadata(for: event)
            )
            return (publicFragment, sensitiveFragment)
        case .json:
            let (publicObject, sensitiveObject) = self.jsonObjects(for: event)
            return (publicObject, sensitiveObject)
        }
    }

    /// Emission-time metadata for one log call. It merges the metadata provider's output with the event's
    /// own metadata, where the event wins on conflicts, plus injected error fields. Returns `nil` when
    /// empty. Excludes base metadata.
    @usableFromInline
    package func emissionTimeMetadata(for event: LogEvent) -> Logging.Logger.Metadata? {
        var metadata = PartitionedMetadata<KeyValueFragmentWriter>.merged(
            provider: self.metadataProvider,
            eventMetadata: event.metadata
        )
        if let error = event.error {
            if metadata["error.message"] == nil {
                metadata["error.message"] = "\(error)"
            }
            if metadata["error.type"] == nil {
                metadata["error.type"] = "\(String(reflecting: type(of: error)))"
            }
        }
        return metadata.isEmpty ? nil : metadata
    }

    /// Maps a swift-log level to the closest `OSLogType`. OSLog has five levels for swift-log's seven:
    /// `trace`/`debug` collapse to `.debug`, `notice`/`warning` collapse to `.default`.
    @usableFromInline
    package static func osLogType(for level: Logging.Logger.Level) -> OSLogType {
        switch level {
        case .trace, .debug: return .debug
        case .info: return .info
        case .notice, .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }

    /// Derives a swift-log threshold from the system's per-type enablement. Assumes enablement is monotonic
    /// (`.debug` implies `.info`, etc.) and probes from most to least verbose.
    package static func systemLogLevel(_ osLog: OSLog) -> Logging.Logger.Level {
        if osLog.isEnabled(type: .debug) { return .trace }
        if osLog.isEnabled(type: .info) { return .info }
        if osLog.isEnabled(type: .default) { return .notice }
        if osLog.isEnabled(type: .error) { return .error }
        return .critical
    }
}

#endif
