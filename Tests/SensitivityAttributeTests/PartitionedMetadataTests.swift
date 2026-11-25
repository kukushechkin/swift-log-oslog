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

import Foundation
import Logging
import Testing

@testable import SensitivityAttribute

/// Writes `key=value`, separated by a space.
private enum TestWriter: MetadataFragmentWriter {
    static var separator: StaticString { " " }

    static func size(key: String, value: Logger.MetadataValue) -> Int {
        "\(key)=\(value.description)".utf8.count
    }

    static func write(key: String, value: Logger.MetadataValue, to cursor: inout FragmentCursor) {
        cursor.append("\(key)=\(value.description)")
    }
}

/// Writes `k=v`, separated by a comma and surrounded by brackets.
private enum BracketedWriter: MetadataFragmentWriter {
    static var prefix: StaticString { "[" }
    static var suffix: StaticString { "]" }
    static var separator: StaticString { "," }

    static func size(key: String, value: Logger.MetadataValue) -> Int {
        "\(key)=\(value.description)".utf8.count
    }

    static func write(key: String, value: Logger.MetadataValue, to cursor: inout FragmentCursor) {
        cursor.append("\(key)=\(value.description)")
    }
}

private typealias Partitioned = PartitionedMetadata<TestWriter>
private typealias Bracketed = PartitionedMetadata<BracketedWriter>

@Suite
struct PartitionedMetadataTests {
    // MARK: - Partition (deny by default)

    @Test
    func partitionKeepsOnlyExplicitlyPublicValuesPublic() {
        let (publicFragment, sensitiveFragment) = Partitioned.partition([
            "method": .attributed("GET", attributes: [Sensitivity.public]),
            "user_id": .attributed("u-123", attributes: [Sensitivity.sensitive]),
            "client_ip": "203.0.113.5",  // untagged, so sensitive
        ])

        #expect(publicFragment == "method=GET")
        // Sorted by key: client_ip before user_id.
        #expect(sensitiveFragment == "client_ip=203.0.113.5 user_id=u-123")
    }

    @Test
    func partitionSortsEachSideByKey() {
        let (publicFragment, sensitiveFragment) = Partitioned.partition([
            "b": .attributed("2", attributes: [Sensitivity.public]),
            "a": .attributed("1", attributes: [Sensitivity.public]),
            "z": .attributed("26", attributes: [Sensitivity.sensitive]),
            "y": .attributed("25", attributes: [Sensitivity.sensitive]),
        ])

        #expect(publicFragment == "a=1 b=2")
        #expect(sensitiveFragment == "y=25 z=26")
    }

    @Test
    func partitionRoutesAllToSensitiveWhenNothingIsPublic() {
        let (publicFragment, sensitiveFragment) = Partitioned.partition([
            "a": "1",
            "b": .attributed("2", attributes: [Sensitivity.sensitive]),
        ])

        #expect(publicFragment.isEmpty)
        #expect(sensitiveFragment == "a=1 b=2")
    }

    // MARK: - Base metadata

    @Test
    func baseMetadataSplitsBySensitivityAndReconstructs() {
        var partitioned = Partitioned()
        #expect(partitioned.publicBaseFragment.isEmpty)
        #expect(partitioned.sensitiveBaseFragment.isEmpty)

        partitioned.metadata = [
            "method": .attributed("GET", attributes: [Sensitivity.public]),
            "client_ip": "203.0.113.5",
        ]

        #expect(partitioned.publicBase["method"]?.description == "GET")
        #expect(partitioned.sensitiveBase["client_ip"]?.description == "203.0.113.5")
        #expect(partitioned.publicBaseFragment == "method=GET")
        #expect(partitioned.sensitiveBaseFragment == "client_ip=203.0.113.5")
        #expect(partitioned.metadata.count == 2)

        // The subscript moves a key between the halves and keeps the fragments in sync.
        partitioned["client_ip"] = .attributed("203.0.113.5", attributes: [Sensitivity.public])
        #expect(partitioned.publicBaseFragment == "client_ip=203.0.113.5 method=GET")
        #expect(partitioned.sensitiveBaseFragment.isEmpty)

        partitioned["method"] = nil
        #expect(partitioned["method"] == nil)
        #expect(partitioned.publicBaseFragment == "client_ip=203.0.113.5")
    }

    @Test
    func baseMetadataHasValueSemantics() {
        var original = Partitioned()
        original["a"] = .attributed("1", attributes: [Sensitivity.public])

        var copy = original
        copy["a"] = nil

        #expect(original.publicBaseFragment == "a=1")
        #expect(copy.publicBaseFragment.isEmpty)
    }

    // MARK: - Emission

    @Test
    func overlapsBaseDetectsSharedKeysInEitherHalf() {
        var partitioned = Partitioned()
        partitioned.metadata = [
            "a": "base_a",  // sensitive half
            "b": .attributed("base_b", attributes: [Sensitivity.public]),  // public half
        ]

        #expect(partitioned.overlapsBase(["a": "x"]))
        #expect(partitioned.overlapsBase(["b": "x"]))
        #expect(partitioned.overlapsBase(["c": "x", "a": "y"]))
        #expect(!partitioned.overlapsBase(["c": "x", "d": "y"]))
    }

    @Test
    func fragmentsWithoutEmissionReturnTheCachedBase() {
        var partitioned = Partitioned()
        partitioned.metadata = ["a": .attributed("1", attributes: [Sensitivity.public]), "b": "2"]

        let (publicFragment, sensitiveFragment) = partitioned.fragments(forEmission: nil)

        #expect(publicFragment == "a=1")
        #expect(sensitiveFragment == "b=2")
    }

    @Test
    func fragmentsAppendTheEmissionToTheBase() {
        var partitioned = Partitioned()
        partitioned.metadata = ["a": .attributed("1", attributes: [Sensitivity.public]), "b": "2"]

        let (publicFragment, sensitiveFragment) = partitioned.fragments(forEmission: [
            "c": .attributed("3", attributes: [Sensitivity.public]),
            "d": "4",
        ])

        #expect(publicFragment == "a=1 c=3")
        #expect(sensitiveFragment == "b=2 d=4")
    }

    @Test
    func fragmentsLetTheEmissionWinOnAKeyConflict() {
        var partitioned = Partitioned()
        partitioned.metadata = ["a": .attributed("base", attributes: [Sensitivity.public])]

        // The emission value is sensitive, so the key leaves the public half.
        let (publicFragment, sensitiveFragment) = partitioned.fragments(forEmission: ["a": "emitted"])

        #expect(publicFragment.isEmpty)
        #expect(sensitiveFragment == "a=emitted")
    }

    @Test
    func mergedLetsTheEventWinOverTheProvider() {
        let provider = Logger.MetadataProvider { ["a": "provided", "b": "provided"] }

        let merged = Partitioned.merged(provider: provider, eventMetadata: ["b": "event", "c": "event"])

        #expect(merged["a"]?.description == "provided")
        #expect(merged["b"]?.description == "event")
        #expect(merged["c"]?.description == "event")
    }

    @Test
    func mergedIsEmptyWithoutProviderAndEventMetadata() {
        #expect(Partitioned.merged(provider: nil, eventMetadata: nil).isEmpty)
    }

    // MARK: - Prefix and suffix

    @Test
    func fragmentsHaveThePrefixAndTheSuffixOnlyWhenTheyHaveEntries() {
        let (publicFragment, sensitiveFragment) = Bracketed.partition([
            "b": .attributed("2", attributes: [Sensitivity.public]),
            "a": .attributed("1", attributes: [Sensitivity.public]),
        ])

        #expect(publicFragment == "[a=1,b=2]")
        #expect(sensitiveFragment.isEmpty)
        #expect(Bracketed.flatten([:]).isEmpty)
    }

    @Test
    func appendingJoinsTwoFragmentsInsideOneBracketPair() {
        #expect(Bracketed.appending("[c=3]", to: "[a=1,b=2]") == "[a=1,b=2,c=3]")
        #expect(Bracketed.appending("", to: "[a=1]") == "[a=1]")
        #expect(Bracketed.appending("[a=1]", to: "") == "[a=1]")
    }

    @Test
    func baseFragmentsKeepThePrefixAndTheSuffixAfterWrites() {
        var partitioned = Bracketed()
        partitioned["a"] = .attributed("1", attributes: [Sensitivity.public])
        partitioned["b"] = "2"
        #expect(partitioned.publicBaseFragment == "[a=1]")
        #expect(partitioned.sensitiveBaseFragment == "[b=2]")

        let (publicFragment, sensitiveFragment) = partitioned.fragments(forEmission: [
            "c": .attributed("3", attributes: [Sensitivity.public])
        ])
        #expect(publicFragment == "[a=1,c=3]")
        #expect(sensitiveFragment == "[b=2]")

        // A write of one half does not change the fragment of the other half.
        partitioned["a"] = nil
        #expect(partitioned.publicBaseFragment.isEmpty)
        #expect(partitioned.sensitiveBaseFragment == "[b=2]")
    }

    // MARK: - Size disagreement

    /// Reports one byte per entry but writes five. This writer breaks the contract on purpose.
    private enum LyingWriter: MetadataFragmentWriter {
        static var separator: StaticString { "," }

        static func size(key: String, value: Logger.MetadataValue) -> Int { 1 }

        static func write(key: String, value: Logger.MetadataValue, to cursor: inout FragmentCursor) {
            cursor.append("12345")
        }
    }

    @Test
    func aWriterThatWritesMoreThanItsSizeGetsTheStorageItNeeds() {
        let fragment = PartitionedMetadata<LyingWriter>.flatten(["a": "1", "b": "2"])

        // Two entries reserve 1 + 1 + 1 bytes, and the writer needs 5 + 1 + 5. The second run has enough storage.
        #expect(fragment == "12345,12345")
    }

    @Test
    func aWriterThatNeverAgreesWithItsSizeGivesAnEmptyFragment() {
        /// Writes more on every run, so no run has enough storage.
        enum GrowingWriter: MetadataFragmentWriter {
            nonisolated(unsafe) static var runs = 0
            static var separator: StaticString { "," }

            static func size(key: String, value: Logger.MetadataValue) -> Int { 1 }

            static func write(key: String, value: Logger.MetadataValue, to cursor: inout FragmentCursor) {
                runs += 1
                cursor.append(String(repeating: "x", count: runs * 10))
            }
        }

        let fragment = PartitionedMetadata<GrowingWriter>.flatten(["a": "1"])

        // Three runs, then the fragment is empty.
        #expect(GrowingWriter.runs == 3)
        #expect(fragment.isEmpty)
    }

    /// Returns a short text on the first read and a longer text on every later read.
    private final class GrowingDescription: CustomStringConvertible, @unchecked Sendable {
        nonisolated(unsafe) private var reads = 0

        var description: String {
            self.reads += 1
            return self.reads == 1 ? "a" : "aaaaa"
        }
    }

    @Test
    func aDescriptionThatGrowsBetweenTheSizeAndTheWriteStillGivesAValidFragment() throws {
        let value = GrowingDescription()

        let (publicFragment, sensitiveFragment) = PartitionedMetadata<JSONFragmentWriter>.partition([
            "k": .array([.stringConvertible(value)])
        ])

        #expect(publicFragment.isEmpty)
        let object = try JSONSerialization.jsonObject(with: Data(sensitiveFragment.utf8)) as? [String: [String]]
        #expect(object == ["k": ["aaaaa"]])
    }

    /// Returns a longer text on every read.
    private final class EndlessDescription: CustomStringConvertible, @unchecked Sendable {
        nonisolated(unsafe) private var reads = 0

        var description: String {
            self.reads += 1
            return String(repeating: "a", count: self.reads)
        }
    }

    @Test
    func aDescriptionThatNeverStopsGrowingGivesAnEmptyFragment() {
        let (publicFragment, sensitiveFragment) = PartitionedMetadata<JSONFragmentWriter>.partition([
            "k": .array([.stringConvertible(EndlessDescription())])
        ])

        #expect(publicFragment.isEmpty)
        #expect(sensitiveFragment.isEmpty)
    }

    /// Counts how many times the text is read.
    private final class CountingDescription: CustomStringConvertible, @unchecked Sendable {
        nonisolated(unsafe) private(set) var reads = 0

        var description: String {
            self.reads += 1
            return "text"
        }
    }

    @Test
    func aKeyValueEntryReadsTheDescriptionOnce() {
        let single = CountingDescription()
        _ = PartitionedMetadata<KeyValueFragmentWriter>.partition(["a": .stringConvertible(single)])
        #expect(single.reads == 1)

        let first = CountingDescription()
        let second = CountingDescription()
        let fragment = PartitionedMetadata<KeyValueFragmentWriter>.flatten([
            "a": .stringConvertible(first),
            "b": .string("x"),
            "c": .array([.stringConvertible(second)]),
        ])
        #expect(first.reads == 1)
        #expect(second.reads == 1)
        #expect(fragment == #"a=text b=x c=["text"]"#)

        let partitioned = CountingDescription()
        _ = PartitionedMetadata<KeyValueFragmentWriter>.partition([
            "a": .stringConvertible(partitioned),
            "b": .string("x"),
        ])
        #expect(partitioned.reads == 1)
    }
}
