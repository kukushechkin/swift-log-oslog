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

/// Writes metadata entries as the members of one JSON object.
@usableFromInline
package enum JSONFragmentWriter: MetadataFragmentWriter {
    @usableFromInline package static var prefix: StaticString { "{" }

    @usableFromInline package static var suffix: StaticString { "}" }

    @usableFromInline package static var separator: StaticString { "," }

    /// A container has no attribute of its own, so its leaves decide. A container without leaves is sensitive.
    ///
    /// - Parameter value: The metadata value to classify.
    @usableFromInline package static func isPublic(_ value: Logger.MetadataValue) -> Bool {
        var sawLeaf = false
        return Self.allLeavesPublic(value, sawLeaf: &sawLeaf) && sawLeaf
    }

    private static func allLeavesPublic(_ value: Logger.MetadataValue, sawLeaf: inout Bool) -> Bool {
        switch value {
        case .dictionary(let dictionary):
            return dictionary.values.allSatisfy { Self.allLeavesPublic($0, sawLeaf: &sawLeaf) }
        case .array(let array):
            return array.allSatisfy { Self.allLeavesPublic($0, sawLeaf: &sawLeaf) }
        case .string, .stringConvertible:
            sawLeaf = true
            return value.attributes[Sensitivity.self] == .public
        }
    }

    @usableFromInline package static func prepared(_ value: Logger.MetadataValue) -> Logger.MetadataValue {
        if case .stringConvertible(let convertible) = value { return .string(convertible.description) }
        return value
    }

    @usableFromInline package static func size(key: String, value: Logger.MetadataValue) -> Int {
        Self.quotedSize(key) + 1 + Self.valueSize(value)
    }

    @usableFromInline package static func write(
        key: String,
        value: Logger.MetadataValue,
        to cursor: inout FragmentCursor
    ) {
        Self.writeQuoted(key, to: &cursor)
        cursor.append(UInt8(ascii: ":"))
        Self.writeValue(value, to: &cursor)
    }

    private static func valueSize(_ value: Logger.MetadataValue) -> Int {
        switch value {
        case .string(let string):
            return Self.quotedSize(string)
        case .stringConvertible(let convertible):
            return Self.quotedSize(convertible.description)
        case .dictionary(let dictionary):
            var size = 2 + max(dictionary.count - 1, 0)
            for (key, value) in dictionary { size += Self.size(key: key, value: value) }
            return size
        case .array(let array):
            var size = 2 + max(array.count - 1, 0)
            for value in array { size += Self.valueSize(value) }
            return size
        }
    }

    private static func writeValue(_ value: Logger.MetadataValue, to cursor: inout FragmentCursor) {
        switch value {
        case .string(let string):
            Self.writeQuoted(string, to: &cursor)
        case .stringConvertible(let convertible):
            Self.writeQuoted(convertible.description, to: &cursor)
        case .dictionary(let dictionary):
            cursor.append(UInt8(ascii: "{"))
            var isFirst = true
            for key in dictionary.keys.sorted() {
                guard let value = dictionary[key] else { continue }
                if !isFirst { cursor.append(UInt8(ascii: ",")) }
                isFirst = false
                Self.write(key: key, value: value, to: &cursor)
            }
            cursor.append(UInt8(ascii: "}"))
        case .array(let array):
            cursor.append(UInt8(ascii: "["))
            var isFirst = true
            for value in array {
                if !isFirst { cursor.append(UInt8(ascii: ",")) }
                isFirst = false
                Self.writeValue(value, to: &cursor)
            }
            cursor.append(UInt8(ascii: "]"))
        }
    }

    private static func quotedSize(_ string: String) -> Int {
        var string = string
        return string.withUTF8 { buffer in
            var size = buffer.count + 2
            for byte in buffer where byte < 0x20 || byte == 0x22 || byte == 0x5C {
                switch byte {
                case 0x22, 0x5C, 0x0A, 0x0D, 0x09, 0x08, 0x0C: size += 1
                default: size += 5
                }
            }
            return size
        }
    }

    private static func writeQuoted(_ string: String, to cursor: inout FragmentCursor) {
        cursor.append(UInt8(ascii: "\""))
        var string = string
        string.withUTF8 { buffer in
            var needsEscaping = false
            for byte in buffer where byte < 0x20 || byte == 0x22 || byte == 0x5C {
                needsEscaping = true
                break
            }
            guard needsEscaping else {
                cursor.append(buffer)
                return
            }
            let hex: StaticString = "0123456789abcdef"
            for byte in buffer {
                switch byte {
                case 0x22:
                    cursor.append(0x5C)
                    cursor.append(0x22)
                case 0x5C:
                    cursor.append(0x5C)
                    cursor.append(0x5C)
                case 0x0A:
                    cursor.append(0x5C)
                    cursor.append(UInt8(ascii: "n"))
                case 0x0D:
                    cursor.append(0x5C)
                    cursor.append(UInt8(ascii: "r"))
                case 0x09:
                    cursor.append(0x5C)
                    cursor.append(UInt8(ascii: "t"))
                case 0x08:
                    cursor.append(0x5C)
                    cursor.append(UInt8(ascii: "b"))
                case 0x0C:
                    cursor.append(0x5C)
                    cursor.append(UInt8(ascii: "f"))
                case ..<0x20:
                    cursor.append(0x5C)
                    cursor.append(UInt8(ascii: "u"))
                    cursor.append(0x30)
                    cursor.append(0x30)
                    cursor.append(hex.utf8Start[Int(byte >> 4)])
                    cursor.append(hex.utf8Start[Int(byte & 0xF)])
                default:
                    cursor.append(byte)
                }
            }
        }
        cursor.append(UInt8(ascii: "\""))
    }
}
