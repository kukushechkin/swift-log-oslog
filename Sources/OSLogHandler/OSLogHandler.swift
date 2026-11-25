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
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct OSLogHandler: LogHandler {
    @usableFromInline
    internal var osLogger: os.Logger

    /// A parallel `OSLog` handle, used only to query enablement for ``logLevel``. `os.Logger` itself cannot
    /// report which levels the system has enabled.
    internal let osLog: OSLog

    /// The base metadata, split by ``Sensitivity`` ahead of time with the `key=value` text of each half cached.
    @usableFromInline package var base = PartitionedMetadata()

    /// Base metadata as one dictionary.
    ///
    /// Reunites the two halves. The setter re-splits and re-flattens them.
    public var metadata: Logging.Logger.Metadata {
        get { self.base.metadata }
        set { self.base.metadata = newValue }
    }

    /// Supplies metadata to attach to every log message, resolved fresh at emission time.
    ///
    /// The handler merges this provider's output with the event's own metadata.
    /// The event's metadata wins on key conflicts.
    public var metadataProvider: Logging.Logger.MetadataProvider?

    /// Explicit log-level override.
    ///
    /// `nil` means derive the level from the system's per-type enablement. See
    /// ``systemLogLevel(_:)``.
    internal var explicitLogLevel: Logging.Logger.Level?

    /// The effective log level.
    ///
    /// With no override, this derives from the system's current per-type enablement. See
    /// ``systemLogLevel(_:)``. A disabled level drops via a cheap comparison instead of building the log
    /// line. Assigning a value installs an explicit override that wins from then on. This preserves
    /// `LogHandler`'s value-semantics contract. System enablement is process-wide, so the derived value can
    /// legitimately differ across processes and change at runtime.
    public var logLevel: Logging.Logger.Level {
        get { self.explicitLogLevel ?? Self.systemLogLevel(self.osLog) }
        set { self.explicitLogLevel = newValue }
    }

    /// Creates an OSLog handler with the specified subsystem and category.
    ///
    /// - Parameters:
    ///   - subsystem: Reverse-DNS identifier for the subsystem, such as `"com.example.myapp"`.
    ///   - category: Category for filtering in Console.app or with `log`.
    public init(subsystem: String, category: String) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }

    /// Emits a log event to the Darwin unified logging system.
    ///
    /// This method partitions the event's metadata into public and private based on
    /// each value's ``Sensitivity``, maps `event.level` to the closest `OSLogType`,
    /// and emits a single `os.Logger` call.
    /// The message text itself is always `privacy: .public`.
    @inlinable
    public func log(event: LogEvent) {
        let level = Self.osLogType(for: event.level)

        let publicString: String
        let privateString: String
        if let emission = self.emissionTimeMetadata(for: event) {
            if self.base.overlapsBase(emission) {
                // Rare: emission-time key collides with a base key. Merge the two, where emission-time
                // metadata wins on conflicts, then partition the result.
                var merged = self.base.publicBaseMetadata
                merged.merge(self.base.privateBaseMetadata) { keep, _ in keep }
                merged.merge(emission) { _, emitted in emitted }
                (publicString, privateString) = PartitionedMetadata.partition(merged)
            } else {
                // Common: no collision. Partition just the emission-time metadata and append to the cached
                // base.
                let (emittedPublic, emittedPrivate) = PartitionedMetadata.partition(emission)
                publicString = PartitionedMetadata.appending(emittedPublic, to: self.base.publicBaseString)
                privateString = PartitionedMetadata.appending(emittedPrivate, to: self.base.privateBaseString)
            }
        } else {
            // No emission-time metadata: use the cached base partition directly.
            (publicString, privateString) = (self.base.publicBaseString, self.base.privateBaseString)
        }

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

    /// Accesses base metadata by key.
    ///
    /// A read checks both the public and private partitions. A write puts the new value into a
    /// partition based on its ``Sensitivity``; setting `nil` removes the key from both partitions.
    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { self.base[key] }
        set { self.base[key] = newValue }
    }

    // MARK: - Pure helpers (package access for testing)

    /// Emission-time metadata for one log call. It merges the metadata provider's output with the event's
    /// own metadata, where the event wins on conflicts, plus injected error fields. Returns `nil` when
    /// empty. Excludes base metadata.
    @usableFromInline
    package func emissionTimeMetadata(for event: LogEvent) -> Logging.Logger.Metadata? {
        var metadata = Logging.Logger.Metadata()
        if let provided = self.metadataProvider?.get(), !provided.isEmpty {
            metadata = provided
        }
        if let eventMetadata = event.metadata, !eventMetadata.isEmpty {
            if metadata.isEmpty {
                metadata = eventMetadata
            } else {
                metadata.merge(eventMetadata, uniquingKeysWith: { _, emitted in emitted })
            }
        }
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
