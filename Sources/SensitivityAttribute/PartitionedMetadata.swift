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

/// Base metadata split by ``Sensitivity``, with a cached `key=value` text for each half.
///
/// The split happens once, when the base metadata changes. A log call then reuses the cached text.
@usableFromInline
package struct PartitionedMetadata: Sendable {
    /// ``Sensitivity/public`` entries. Everything else is in ``privateBaseMetadata``.
    @usableFromInline package var publicBaseMetadata: Logger.Metadata = [:]
    @usableFromInline package var privateBaseMetadata: Logger.Metadata = [:]

    /// The `key=value` text of each half. It changes only when the base metadata changes.
    @usableFromInline package var publicBaseString: String = ""
    @usableFromInline package var privateBaseString: String = ""

    @usableFromInline
    package init() {}

    /// The base metadata as one dictionary.
    ///
    /// The setter splits the new value again and flattens both halves.
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
                if value.attributes[Sensitivity.self] == .public {
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
    package subscript(key: String) -> Logger.Metadata.Value? {
        get { self.publicBaseMetadata[key] ?? self.privateBaseMetadata[key] }
        set {
            self.publicBaseMetadata[key] = nil
            self.privateBaseMetadata[key] = nil
            if let newValue {
                if newValue.attributes[Sensitivity.self] == .public {
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
    @usableFromInline
    package func overlapsBase(_ emission: Logger.Metadata) -> Bool {
        for key in emission.keys where self.publicBaseMetadata[key] != nil || self.privateBaseMetadata[key] != nil {
            return true
        }
        return false
    }

    /// Flattens already-split metadata into a sorted `key=value` string.
    package static func flatten(_ metadata: Logger.Metadata) -> String {
        var result = ""
        result.reserveCapacity(metadata.keys.reduce(0) { $0 + $1.utf8.count + 2 } + metadata.count)
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            if !result.isEmpty { result.append(" ") }
            result.append(key)
            result.append("=")
            result.append(value.description)
        }
        return result
    }

    /// Appends `field` to `base`, separated by a space. Skips the copy when either side is empty.
    @usableFromInline
    package static func appending(_ field: String, to base: String) -> String {
        if field.isEmpty { return base }
        if base.isEmpty { return field }
        return base + " " + field
    }

    /// Splits metadata into sorted public/private `key=value` strings in one pass. Denies by default: only
    /// ``Sensitivity/public`` goes to the public string.
    @usableFromInline
    package static func partition(
        _ metadata: Logger.Metadata
    ) -> (publicString: String, privateString: String) {
        var publicString = ""
        var privateString = ""
        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            let isPublic = value.attributes[Sensitivity.self] == .public
            if isPublic {
                if !publicString.isEmpty { publicString.append(" ") }
                publicString.append(key)
                publicString.append("=")
                publicString.append(value.description)
            } else {
                if !privateString.isEmpty { privateString.append(" ") }
                privateString.append(key)
                privateString.append("=")
                privateString.append(value.description)
            }
        }
        return (publicString, privateString)
    }
}
