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

public import Logging

/// Writes metadata entries as text. A fragment is the prefix, the entries joined by the separator, and the suffix.
@usableFromInline
package protocol MetadataFragmentWriter {
    static var prefix: StaticString { get }

    static var suffix: StaticString { get }

    static var separator: StaticString { get }

    /// Whether the value belongs to the public half. The default reads the ``Sensitivity`` of the value.
    static func isPublic(_ value: Logger.MetadataValue) -> Bool

    /// The value that `size` and `write` read. A writer renders the text of a value here once, so `size` and `write`
    /// do not render it twice. The default returns the value.
    static func prepared(_ value: Logger.MetadataValue) -> Logger.MetadataValue

    /// The number of bytes that `write` writes for one entry.
    static func size(key: String, value: Logger.MetadataValue) -> Int

    /// Writes one entry. A `write` that exceeds `size` runs again with more storage.
    static func write(key: String, value: Logger.MetadataValue, to cursor: inout FragmentCursor)
}

extension MetadataFragmentWriter {
    @inlinable
    package static var prefix: StaticString { "" }

    @inlinable
    package static var suffix: StaticString { "" }

    @inlinable
    package static func isPublic(_ value: Logger.MetadataValue) -> Bool {
        value.attributes[Sensitivity.self] == .public
    }

    @inlinable
    package static func prepared(_ value: Logger.MetadataValue) -> Logger.MetadataValue {
        value
    }
}

/// Base metadata split by ``Sensitivity``, with a cached text fragment for each half.
@usableFromInline
package struct PartitionedMetadata<Writer: MetadataFragmentWriter>: Sendable {
    @usableFromInline package var publicBase: Logger.Metadata = [:]

    @usableFromInline package var sensitiveBase: Logger.Metadata = [:]

    @usableFromInline package var publicBaseFragment: String = ""

    @usableFromInline package var sensitiveBaseFragment: String = ""

    @inlinable
    package init() {}

    /// The base metadata as one dictionary.
    @inlinable
    package var metadata: Logger.Metadata {
        get {
            if self.sensitiveBase.isEmpty { return self.publicBase }
            if self.publicBase.isEmpty { return self.sensitiveBase }
            return self.publicBase.merging(self.sensitiveBase) { keep, _ in keep }
        }
        set {
            self.publicBase = [:]
            self.sensitiveBase = [:]
            for (key, value) in newValue {
                self.store(value, forKey: key)
            }
            self.rebuildFragments()
        }
    }

    /// One base entry.
    @inlinable
    package subscript(key: String) -> Logger.MetadataValue? {
        get { self.publicBase[key] ?? self.sensitiveBase[key] }
        set {
            var publicChanged = self.publicBase.removeValue(forKey: key) != nil
            var sensitiveChanged = self.sensitiveBase.removeValue(forKey: key) != nil
            if let newValue {
                if Writer.isPublic(newValue) {
                    self.publicBase[key] = newValue
                    publicChanged = true
                } else {
                    self.sensitiveBase[key] = newValue
                    sensitiveChanged = true
                }
            }
            if publicChanged { self.publicBaseFragment = Self.flatten(self.publicBase) }
            if sensitiveChanged { self.sensitiveBaseFragment = Self.flatten(self.sensitiveBase) }
        }
    }

    @inlinable
    internal mutating func store(_ value: Logger.MetadataValue, forKey key: String) {
        if Writer.isPublic(value) {
            self.publicBase[key] = value
        } else {
            self.sensitiveBase[key] = value
        }
    }

    @inlinable
    package mutating func rebuildFragments() {
        self.publicBaseFragment = Self.flatten(self.publicBase)
        self.sensitiveBaseFragment = Self.flatten(self.sensitiveBase)
    }

    @inlinable
    package func overlapsBase(_ emission: Logger.Metadata) -> Bool {
        if self.publicBase.isEmpty && self.sensitiveBase.isEmpty { return false }
        for key in emission.keys where self.publicBase[key] != nil || self.sensitiveBase[key] != nil {
            return true
        }
        return false
    }

    /// The cached base fragments with the fragments of `emission` appended.
    @inlinable
    package func fragments(
        forEmission emission: Logger.Metadata?
    ) -> (publicFragment: String, sensitiveFragment: String) {
        guard let emission else {
            return (self.publicBaseFragment, self.sensitiveBaseFragment)
        }
        if self.overlapsBase(emission) {
            var merged = self.publicBase
            merged.merge(self.sensitiveBase) { keep, _ in keep }
            merged.merge(emission) { _, emitted in emitted }
            return Self.partition(merged)
        }
        let (emittedPublic, emittedSensitive) = Self.partition(emission)
        return (
            Self.appending(emittedPublic, to: self.publicBaseFragment),
            Self.appending(emittedSensitive, to: self.sensitiveBaseFragment)
        )
    }

    /// Merges the output of a metadata provider with the metadata of a log call. The log call wins.
    @inlinable
    package static func merged(
        provider: Logger.MetadataProvider?,
        eventMetadata: Logger.Metadata?
    ) -> Logger.Metadata {
        var emission = Logger.Metadata()
        if let provided = provider?.get(), !provided.isEmpty {
            emission = provided
        }
        if let eventMetadata, !eventMetadata.isEmpty {
            if emission.isEmpty {
                emission = eventMetadata
            } else {
                emission.merge(eventMetadata, uniquingKeysWith: { _, emitted in emitted })
            }
        }
        return emission
    }

    /// Writes metadata into one fragment, sorted by key.
    @inlinable
    package static func flatten(_ metadata: Logger.Metadata) -> String {
        guard let first = metadata.first else {
            return ""
        }
        if metadata.count == 1 {
            let value = Writer.prepared(first.value)
            return Self.makeFragment(entries: 1, entriesSize: Writer.size(key: first.key, value: value)) {
                Writer.write(key: first.key, value: value, to: &$0)
            }
        }
        let keys = metadata.keys.sorted()
        return withUnsafeTemporaryAllocation(of: Logger.MetadataValue?.self, capacity: keys.count) { values in
            var size = 0
            for (index, key) in keys.enumerated() {
                let value = metadata[key].map(Writer.prepared)
                values.initializeElement(at: index, to: value)
                if let value { size += Writer.size(key: key, value: value) }
            }
            defer { values.deinitialize() }
            return Self.makeFragment(entries: keys.count, entriesSize: size) { cursor in
                var isFirst = true
                for (index, key) in keys.enumerated() {
                    guard let value = values[index] else { continue }
                    if !isFirst { cursor.append(Writer.separator) }
                    isFirst = false
                    Writer.write(key: key, value: value, to: &cursor)
                }
            }
        }
    }

    /// Splits metadata into a public and a sensitive fragment, each sorted by key.
    @inlinable
    package static func partition(
        _ metadata: Logger.Metadata
    ) -> (publicFragment: String, sensitiveFragment: String) {
        guard let first = metadata.first else {
            return ("", "")
        }
        if metadata.count == 1 {
            let value = Writer.prepared(first.value)
            let fragment = Self.makeFragment(entries: 1, entriesSize: Writer.size(key: first.key, value: value)) {
                Writer.write(key: first.key, value: value, to: &$0)
            }
            return Writer.isPublic(first.value) ? (fragment, "") : ("", fragment)
        }
        let keys = metadata.keys.sorted()
        return withUnsafeTemporaryAllocation(of: Bool.self, capacity: keys.count) { isPublic in
            withUnsafeTemporaryAllocation(of: Logger.MetadataValue?.self, capacity: keys.count) { values in
                var publicCount = 0
                var publicSize = 0
                var sensitiveCount = 0
                var sensitiveSize = 0
                for (index, key) in keys.enumerated() {
                    guard let original = metadata[key] else {
                        isPublic[index] = false
                        values.initializeElement(at: index, to: nil)
                        continue
                    }
                    let value = Writer.prepared(original)
                    values.initializeElement(at: index, to: value)
                    let size = Writer.size(key: key, value: value)
                    if Writer.isPublic(original) {
                        isPublic[index] = true
                        publicCount += 1
                        publicSize += size
                    } else {
                        isPublic[index] = false
                        sensitiveCount += 1
                        sensitiveSize += size
                    }
                }
                defer { values.deinitialize() }
                let publicFragment = Self.makeFragment(entries: publicCount, entriesSize: publicSize) { cursor in
                    var isFirst = true
                    for (index, key) in keys.enumerated() where isPublic[index] {
                        guard let value = values[index] else { continue }
                        if !isFirst { cursor.append(Writer.separator) }
                        isFirst = false
                        Writer.write(key: key, value: value, to: &cursor)
                    }
                }
                let sensitiveFragment = Self.makeFragment(entries: sensitiveCount, entriesSize: sensitiveSize) {
                    cursor in
                    var isFirst = true
                    for (index, key) in keys.enumerated() where !isPublic[index] {
                        guard let value = values[index] else { continue }
                        if !isFirst { cursor.append(Writer.separator) }
                        isFirst = false
                        Writer.write(key: key, value: value, to: &cursor)
                    }
                }
                return (publicFragment, sensitiveFragment)
            }
        }
    }

    /// Creates a fragment with its exact storage. A body that needs more storage than reported runs again, up to three
    /// times. After that the fragment is empty, because a truncated fragment can be invalid text.
    @inlinable
    package static func makeFragment(
        entries: Int,
        entriesSize: Int,
        _ body: (inout FragmentCursor) -> Void
    ) -> String {
        if entries == 0 { return "" }
        var capacity = max(
            0,
            Writer.prefix.utf8CodeUnitCount + entriesSize + (entries - 1) * Writer.separator.utf8CodeUnitCount
                + Writer.suffix.utf8CodeUnitCount
        )
        var attempt = 1
        while true {
            var needed = 0
            let fragment = String(unsafeUninitializedCapacity: capacity) { buffer in
                guard let start = buffer.baseAddress else { return 0 }
                var cursor = FragmentCursor(base: start, capacity: capacity)
                cursor.append(Writer.prefix)
                body(&cursor)
                cursor.append(Writer.suffix)
                needed = cursor.required
                return cursor.count
            }
            if needed <= capacity { return fragment }
            if attempt == 3 { return "" }
            capacity = needed
            attempt += 1
        }
    }

    /// Joins two fragments into one.
    @inlinable
    package static func appending(_ field: String, to base: String) -> String {
        if field.isEmpty { return base }
        if base.isEmpty { return field }
        let keep = base.utf8.count - Writer.suffix.utf8CodeUnitCount
        let skip = Writer.prefix.utf8CodeUnitCount
        let total = keep + Writer.separator.utf8CodeUnitCount + field.utf8.count - skip
        var base = base
        var field = field
        return base.withUTF8 { baseBytes in
            field.withUTF8 { fieldBytes in
                String(unsafeUninitializedCapacity: total) { buffer in
                    guard let start = buffer.baseAddress else { return 0 }
                    var cursor = FragmentCursor(base: start, capacity: total)
                    cursor.append(UnsafeBufferPointer(rebasing: baseBytes[..<keep]))
                    cursor.append(Writer.separator)
                    cursor.append(UnsafeBufferPointer(rebasing: fieldBytes[skip...]))
                    return cursor.count
                }
            }
        }
    }
}

/// A write position in the storage of a fragment. The cursor drops bytes that do not fit and counts them in `required`.
@usableFromInline
package struct FragmentCursor {
    @usableFromInline var base: UnsafeMutablePointer<UInt8>
    @usableFromInline let capacity: Int

    @usableFromInline package var count = 0

    @usableFromInline package var required = 0

    @inlinable
    package init(base: UnsafeMutablePointer<UInt8>, capacity: Int) {
        self.base = base
        self.capacity = capacity
    }

    @inlinable
    package mutating func append(_ byte: UInt8) {
        self.required += 1
        if self.count < self.capacity {
            self.base[self.count] = byte
            self.count += 1
        }
    }

    @inlinable
    package mutating func append(_ buffer: UnsafeBufferPointer<UInt8>) {
        self.required += buffer.count
        let length = min(buffer.count, self.capacity - self.count)
        if let source = buffer.baseAddress, length > 0 {
            (self.base + self.count).update(from: source, count: length)
            self.count += length
        }
    }

    @inlinable
    package mutating func append(_ string: StaticString) {
        self.append(UnsafeBufferPointer(start: string.utf8Start, count: string.utf8CodeUnitCount))
    }

    @inlinable
    package mutating func append(_ string: String) {
        var string = string
        string.withUTF8 { self.append($0) }
    }
}
