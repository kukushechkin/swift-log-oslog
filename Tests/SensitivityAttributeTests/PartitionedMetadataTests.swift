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
struct PartitionedMetadataTests {

    // MARK: - Partition (deny-by-default)

    @Test
    func partitionKeepsOnlyExplicitlyPublicValuesPublic() {
        let (publicString, privateString) = PartitionedMetadata.partition([
            "method": .attributed("GET", attributes: [Sensitivity.public]),
            "user_id": .attributed("u-123", attributes: [Sensitivity.sensitive]),
            "client_ip": "203.0.113.5",  // untagged, so private
        ])

        #expect(publicString == "method=GET")
        // Sorted by key: client_ip before user_id.
        #expect(privateString == "client_ip=203.0.113.5 user_id=u-123")
    }

    @Test
    func partitionSortsEachSideByKey() {
        let (publicString, privateString) = PartitionedMetadata.partition([
            "b": .attributed("2", attributes: [Sensitivity.public]),
            "a": .attributed("1", attributes: [Sensitivity.public]),
            "z": .attributed("26", attributes: [Sensitivity.sensitive]),
            "y": .attributed("25", attributes: [Sensitivity.sensitive]),
        ])

        #expect(publicString == "a=1 b=2")
        #expect(privateString == "y=25 z=26")
    }

    @Test
    func partitionRoutesAllToPrivateWhenNothingIsPublic() {
        let (publicString, privateString) = PartitionedMetadata.partition([
            "a": "1",
            "b": .attributed("2", attributes: [Sensitivity.sensitive]),
        ])

        #expect(publicString.isEmpty)
        #expect(privateString == "a=1 b=2")
    }

    // MARK: - Overlap with the base

    @Test
    func overlapsBaseDetectsSharedKeys() {
        var base = PartitionedMetadata()
        base.metadata = [
            "a": "base_a",  // private side
            "b": .attributed("base_b", attributes: [Sensitivity.public]),  // public side
        ]

        #expect(base.overlapsBase(["a": "x"]))  // shares a private-side key
        #expect(base.overlapsBase(["b": "x"]))  // shares a public-side key
        #expect(base.overlapsBase(["c": "x", "a": "y"]))  // any shared key
        #expect(!base.overlapsBase(["c": "x", "d": "y"]))  // disjoint
    }

    // MARK: - Base metadata: split by sensitivity, cached, reconstructed

    @Test
    func baseMetadataSplitsBySensitivityAndReconstructs() {
        var base = PartitionedMetadata()

        // A new value has empty halves and empty cached strings.
        #expect(base.publicBaseString.isEmpty)
        #expect(base.privateBaseString.isEmpty)

        base.metadata = [
            "method": .attributed("GET", attributes: [Sensitivity.public]),
            "client_ip": "203.0.113.5",  // untagged, so private
        ]

        // Split by sensitivity into the two halves.
        #expect(base.publicBaseMetadata["method"]?.description == "GET")
        #expect(base.privateBaseMetadata["client_ip"]?.description == "203.0.113.5")
        #expect(base.publicBaseMetadata["client_ip"] == nil)
        #expect(base.privateBaseMetadata["method"] == nil)

        // Cached strings match a flatten of each half.
        #expect(base.publicBaseString == "method=GET")
        #expect(base.privateBaseString == "client_ip=203.0.113.5")

        // The getter reconstructs the whole dictionary from the two halves.
        #expect(base.metadata["method"]?.description == "GET")
        #expect(base.metadata["client_ip"]?.description == "203.0.113.5")
        #expect(base.metadata.count == 2)

        // The subscript routes to the correct half and keeps the cached string in sync.
        base["user_id"] = .attributed("u-1", attributes: [Sensitivity.sensitive])
        #expect(base.privateBaseMetadata["user_id"]?.description == "u-1")
        #expect(base.privateBaseString == "client_ip=203.0.113.5 user_id=u-1")

        // Value semantics: a copy updates its own halves independently.
        var copy = base
        copy["method"] = nil
        #expect(base.publicBaseString == "method=GET")
        #expect(copy.publicBaseString.isEmpty)
    }

    // MARK: - Appending

    @Test
    func appendingJoinsWithASpaceAndSkipsEmptySides() {
        #expect(PartitionedMetadata.appending("b=2", to: "a=1") == "a=1 b=2")
        #expect(PartitionedMetadata.appending("", to: "a=1") == "a=1")
        #expect(PartitionedMetadata.appending("b=2", to: "") == "b=2")
    }
}
