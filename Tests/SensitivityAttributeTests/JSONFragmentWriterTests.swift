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

import Logging
import Testing

@testable import SensitivityAttribute

@Suite
struct JSONFragmentWriterTests {
    /// The quoted JSON text of `string`, taken from a one-entry object.
    private func json(_ string: String) -> String {
        let object = PartitionedMetadata<JSONFragmentWriter>.flatten(["k": .string(string)])
        return String(object.dropFirst(5).dropLast())
    }

    private func fragment(_ metadata: Logger.Metadata) -> String {
        PartitionedMetadata<JSONFragmentWriter>.flatten(metadata)
    }

    // MARK: - Escaping

    @Test
    func plainStringIsQuoted() {
        #expect(self.json("hello") == "\"hello\"")
        #expect(self.json("") == "\"\"")
    }

    @Test
    func quoteAndBackslashAreEscaped() {
        #expect(self.json("a\"b\\c") == "\"a\\\"b\\\\c\"")
    }

    @Test
    func controlCharactersAreEscaped() {
        #expect(self.json("a\nb\rc\td") == "\"a\\nb\\rc\\td\"")
        #expect(self.json("\u{08}\u{0C}") == "\"\\b\\f\"")
        #expect(self.json("\u{01}") == "\"\\u0001\"")
        #expect(self.json("\u{1F}") == "\"\\u001f\"")
    }

    @Test
    func nonASCIICharactersStayUnescaped() {
        #expect(self.json("héllo 🌍 日本") == "\"héllo 🌍 日本\"")
        #expect(self.json("é\n") == "\"é\\n\"")
    }

    // MARK: - Values

    @Test
    func entriesAreSortedAndSeparatedByCommas() {
        #expect(self.fragment(["b": "2", "a": "1"]) == "{\"a\":\"1\",\"b\":\"2\"}")
    }

    @Test
    func stringConvertibleBecomesAString() {
        #expect(self.fragment(["n": .stringConvertible(42)]) == "{\"n\":\"42\"}")
    }

    @Test
    func dotsInKeysStayLiteral() {
        #expect(self.fragment(["user.id": "1"]) == "{\"user.id\":\"1\"}")
    }

    @Test
    func keysAreEscaped() {
        #expect(self.fragment(["a\"b": "1"]) == "{\"a\\\"b\":\"1\"}")
    }

    @Test
    func dictionaryBecomesAnObjectWithSortedKeys() {
        let value: Logger.MetadataValue = .dictionary(["b": "2", "a": "1"])
        #expect(self.fragment(["k": value]) == "{\"k\":{\"a\":\"1\",\"b\":\"2\"}}")
    }

    @Test
    func arrayBecomesAnArrayInOrder() {
        let value: Logger.MetadataValue = .array(["z", "a", .dictionary(["k": "v"])])
        #expect(self.fragment(["k": value]) == "{\"k\":[\"z\",\"a\",{\"k\":\"v\"}]}")
    }

    @Test
    func emptyContainersAreWritten() {
        #expect(self.fragment(["d": .dictionary([:]), "a": .array([])]) == "{\"a\":[],\"d\":{}}")
    }

    // MARK: - Classification

    @Test
    func stringIsPublicOnlyWhenTaggedPublic() {
        #expect(JSONFragmentWriter.isPublic(.attributed("x", attributes: [Sensitivity.public])))
        #expect(!JSONFragmentWriter.isPublic(.attributed("x", attributes: [Sensitivity.sensitive])))
        #expect(!JSONFragmentWriter.isPublic("untagged"))
    }

    @Test
    func containerIsPublicOnlyWhenEveryLeafIsPublic() {
        let publicLeaf: Logger.MetadataValue = .attributed("x", attributes: [Sensitivity.public])
        let sensitiveLeaf: Logger.MetadataValue = .attributed("y", attributes: [Sensitivity.sensitive])

        #expect(JSONFragmentWriter.isPublic(.dictionary(["a": publicLeaf, "b": publicLeaf])))
        #expect(JSONFragmentWriter.isPublic(.array([publicLeaf, .array([publicLeaf])])))
        #expect(!JSONFragmentWriter.isPublic(.dictionary(["a": publicLeaf, "b": sensitiveLeaf])))
        #expect(!JSONFragmentWriter.isPublic(.dictionary(["a": publicLeaf, "b": "untagged"])))
        #expect(!JSONFragmentWriter.isPublic(.array([publicLeaf, .dictionary(["k": sensitiveLeaf])])))
    }

    @Test
    func containerWithoutLeavesIsSensitive() {
        let publicLeaf: Logger.MetadataValue = .attributed("x", attributes: [Sensitivity.public])

        #expect(!JSONFragmentWriter.isPublic(.dictionary([:])))
        #expect(!JSONFragmentWriter.isPublic(.array([])))
        #expect(!JSONFragmentWriter.isPublic(.array([.dictionary([:])])))
        // An empty container next to a public leaf does not change the verdict.
        #expect(JSONFragmentWriter.isPublic(.array([publicLeaf, .array([])])))
    }
}
