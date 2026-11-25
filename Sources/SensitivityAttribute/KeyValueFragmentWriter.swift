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

/// Writes metadata entries as `key=value`, separated by a space.
@usableFromInline
package enum KeyValueFragmentWriter: MetadataFragmentWriter {
    @usableFromInline
    package static var separator: StaticString { " " }

    @inlinable
    package static func prepared(_ value: Logger.MetadataValue) -> Logger.MetadataValue {
        if case .string = value { return value }
        return .string(value.description)
    }

    @inlinable
    package static func size(key: String, value: Logger.MetadataValue) -> Int {
        key.utf8.count + 1 + value.description.utf8.count
    }

    @inlinable
    package static func write(key: String, value: Logger.MetadataValue, to cursor: inout FragmentCursor) {
        cursor.append(key)
        cursor.append(UInt8(ascii: "="))
        cursor.append(value.description)
    }
}
