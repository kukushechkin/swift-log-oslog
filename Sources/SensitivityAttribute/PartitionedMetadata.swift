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

/// Writes metadata entries as text, so that ``PartitionedMetadata`` can cache the text of the base metadata.
@usableFromInline
package protocol MetadataFragmentWriter {
    /// The text between two entries.
    static var separator: String { get }

    /// Whether the value belongs to the public half. The default reads the ``Sensitivity`` of the value.
    static func isPublic(_ value: Logger.MetadataValue) -> Bool

    /// Appends the text of one entry to `fragment`.
    static func write(key: String, value: Logger.MetadataValue, to fragment: inout String)
}

extension MetadataFragmentWriter {
    @inlinable
    package static func isPublic(_ value: Logger.MetadataValue) -> Bool {
        value.attributes[Sensitivity.self] == .public
    }
}

/// Base metadata split by ``Sensitivity``, with a cached text for each half.
///
/// The split happens once, when the base metadata changes. A log call then reuses the cached text. The `Writer`
/// decides how the text of an entry looks.
@usableFromInline
package struct PartitionedMetadata<Writer: MetadataFragmentWriter>: Sendable {
    /// ``Sensitivity/public`` entries. Everything else is in ``privateBaseMetadata``.
    @usableFromInline package var publicBaseMetadata: Logger.Metadata = [:]
    @usableFromInline package var privateBaseMetadata: Logger.Metadata = [:]

    /// The text of each half. It changes only when the base metadata changes.
    @usableFromInline package var publicBaseString: String = ""
    @usableFromInline package var privateBaseString: String = ""

    @inlinable
    package init() {}

    /// The base metadata as one dictionary.
    ///
    /// The setter splits the new value again and flattens both halves.
    @inlinable
    package var metadata: Logger.Metadata {
        get {
            if self.privateBaseMetadata.isEmpty { return self.publicBaseMetadata }
            if self.publicBaseMetadata.isEmpty { return self.privateBaseMetadata }
            return self.publicBaseMetadata.merging(self.privateBaseMetadata) { keep, _ in keep }
        }
        set {
            self.publicBaseMetadata = [:]
            self.privateBaseMetadata = [:]
            for (key, value) in newValue {
                if Writer.isPublic(value) {
                    self.publicBaseMetadata[key] = value
                } else {
                    self.privateBaseMetadata[key] = value
                }
            }
            self.publicBaseString = Self.flatten(self.publicBaseMetadata)
            self.privateBaseString = Self.flatten(self.privateBaseMetadata)
        }
    }

    /// One base entry.
    ///
    /// A read checks both halves. A write puts the new value into a half based on its ``Sensitivity``. Setting
    /// `nil` removes the key from both halves.
    @inlinable
    package subscript(key: String) -> Logger.Metadata.Value? {
        get { self.publicBaseMetadata[key] ?? self.privateBaseMetadata[key] }
        set {
            self.publicBaseMetadata[key] = nil
            self.privateBaseMetadata[key] = nil
            if let newValue {
                if Writer.isPublic(newValue) {
                    self.publicBaseMetadata[key] = newValue
                } else {
                    self.privateBaseMetadata[key] = newValue
                }
            }
            self.publicBaseString = Self.flatten(self.publicBaseMetadata)
            self.privateBaseString = Self.flatten(self.privateBaseMetadata)
        }
    }

    /// Whether an emission-time key also names a base entry. Appending would duplicate that key in this
    /// case.
    @inlinable
    package func overlapsBase(_ emission: Logger.Metadata) -> Bool {
        for key in emission.keys where self.publicBaseMetadata[key] != nil || self.privateBaseMetadata[key] != nil {
            return true
        }
        return false
    }

    /// Flattens already-split metadata into a sorted text.
    @inlinable
    package static func flatten(_ metadata: Logger.Metadata) -> String {
        var result = ""
        result.reserveCapacity(metadata.keys.reduce(0) { $0 + $1.utf8.count + 2 } + metadata.count)
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            if !result.isEmpty { result.append(Writer.separator) }
            Writer.write(key: key, value: value, to: &result)
        }
        return result
    }

    /// Appends `field` to `base`, separated by the separator of the writer. Skips the copy when either side is empty.
    @inlinable
    package static func appending(_ field: String, to base: String) -> String {
        if field.isEmpty { return base }
        if base.isEmpty { return field }
        return base + Writer.separator + field
    }

    /// Splits metadata into sorted public/private texts in one pass. Denies by default: only
    /// ``Sensitivity/public`` goes to the public string.
    @inlinable
    package static func partition(
        _ metadata: Logger.Metadata
    ) -> (publicString: String, privateString: String) {
        var publicString = ""
        var privateString = ""
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            if Writer.isPublic(value) {
                if !publicString.isEmpty { publicString.append(Writer.separator) }
                Writer.write(key: key, value: value, to: &publicString)
            } else {
                if !privateString.isEmpty { privateString.append(Writer.separator) }
                Writer.write(key: key, value: value, to: &privateString)
            }
        }
        return (publicString, privateString)
    }
}
