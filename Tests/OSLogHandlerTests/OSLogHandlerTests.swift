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
import Logging
import OSLogHandler
import SensitivityAttribute
import Testing
import os

@Suite
struct OSLogHandlerTests {

    // MARK: - Level mapping

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func mapsEverySwiftLogLevelToAnOSLogType() {
        #expect(OSLogHandler.osLogType(for: .trace) == .debug)
        #expect(OSLogHandler.osLogType(for: .debug) == .debug)
        #expect(OSLogHandler.osLogType(for: .info) == .info)
        #expect(OSLogHandler.osLogType(for: .notice) == .default)
        #expect(OSLogHandler.osLogType(for: .warning) == .default)
        #expect(OSLogHandler.osLogType(for: .error) == .error)
        #expect(OSLogHandler.osLogType(for: .critical) == .fault)
    }

    // MARK: - Metadata merging

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func emissionTimeMetadataAppliesProviderThenEventPrecedence() throws {
        var handler = OSLogHandler(subsystem: "test", category: "merge")
        handler.metadata = ["a": "base_a"]  // base is kept separate from the emission-time metadata
        handler.metadataProvider = Logger.MetadataProvider {
            ["b": "prov_b", "shared": "prov_shared"]
        }

        let event = LogEvent(
            level: .info,
            message: "msg",
            error: nil,
            metadata: ["c": "evt_c", "shared": "evt_shared"],
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )

        let emission = try #require(handler.emissionTimeMetadata(for: event))
        #expect(emission["b"]?.description == "prov_b")
        #expect(emission["c"]?.description == "evt_c")
        #expect(emission["shared"]?.description == "evt_shared")  // event wins over provider
        #expect(emission["a"] == nil)  // base metadata is not part of the emission-time metadata
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func emissionTimeMetadataForwardsEventMetadata() throws {
        let handler = OSLogHandler(subsystem: "test", category: "fast")  // no base, no provider

        let event = LogEvent(
            level: .info,
            message: "msg",
            error: nil,
            metadata: ["k": "v"],
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )

        let emission = try #require(handler.emissionTimeMetadata(for: event))
        #expect(emission["k"]?.description == "v")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func emissionTimeMetadataReturnsNilWhenEmpty() {
        let handler = OSLogHandler(subsystem: "test", category: "empty")

        let event = LogEvent(
            level: .info,
            message: "msg",
            error: nil,
            metadata: nil,
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )

        #expect(handler.emissionTimeMetadata(for: event) == nil)
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func emissionTimeMetadataInjectsErrorFieldsThatStayPrivate() throws {
        struct SampleError: Error {}
        let handler = OSLogHandler(subsystem: "test", category: "error")

        let event = LogEvent(
            level: .error,
            message: "boom",
            error: SampleError(),
            metadata: nil,
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )

        let emission = try #require(handler.emissionTimeMetadata(for: event))
        #expect(emission["error.message"] != nil)
        #expect(emission["error.type"]?.description.hasSuffix("SampleError") == true)

        // Untagged error fields stay private under deny-by-default.
        let (publicFragment, _) = PartitionedMetadata<KeyValueFragmentWriter>.partition(emission)
        #expect(publicFragment.isEmpty)
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func emissionTimeMetadataDoesNotOverrideExplicitEventErrorFields() throws {
        struct SampleError: Error {}
        let handler = OSLogHandler(subsystem: "test", category: "error-override")

        let event = LogEvent(
            level: .error,
            message: "boom",
            error: SampleError(),
            metadata: ["error.message": "custom"],
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )

        // The event's own error.message is kept. The injected one does not overwrite it.
        let emission = try #require(handler.emissionTimeMetadata(for: event))
        #expect(emission["error.message"]?.description == "custom")
    }

    // MARK: - Base metadata: split by sensitivity, cached, reconstructed

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func baseMetadataSplitsBySensitivityAndReconstructs() {
        var handler = OSLogHandler(subsystem: "test", category: "base")

        // A fresh handler has empty halves and empty cached strings.
        #expect(handler.base.publicBaseFragment.isEmpty)
        #expect(handler.base.sensitiveBaseFragment.isEmpty)

        handler.metadata = [
            "method": .attributed("GET", attributes: [Sensitivity.public]),
            "client_ip": "203.0.113.5",  // untagged, so private
        ]

        // Split by sensitivity into the two halves.
        #expect(handler.base.publicBase["method"]?.description == "GET")
        #expect(handler.base.sensitiveBase["client_ip"]?.description == "203.0.113.5")
        #expect(handler.base.publicBase["client_ip"] == nil)
        #expect(handler.base.sensitiveBase["method"] == nil)

        // Cached strings match a flatten of each half.
        #expect(handler.base.publicBaseFragment == "method=GET")
        #expect(handler.base.sensitiveBaseFragment == "client_ip=203.0.113.5")

        // The getter reconstructs the whole dictionary from the two halves.
        #expect(handler.metadata["method"]?.description == "GET")
        #expect(handler.metadata["client_ip"]?.description == "203.0.113.5")
        #expect(handler.metadata.count == 2)

        // The subscript routes to the correct half and keeps the cached string in sync.
        handler[metadataKey: "user_id"] = .attributed("u-1", attributes: [Sensitivity.sensitive])
        #expect(handler.base.sensitiveBase["user_id"]?.description == "u-1")
        #expect(handler.base.sensitiveBaseFragment == "client_ip=203.0.113.5 user_id=u-1")

        // Value semantics: a copy updates its own halves independently.
        var copy = handler
        copy[metadataKey: "method"] = nil
        #expect(handler.base.publicBaseFragment == "method=GET")
        #expect(copy.base.publicBaseFragment.isEmpty)
    }

    // MARK: - Value semantics (LogHandler requirement)

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func logLevelAndMetadataBehaveAsValues() {
        var handler1 = OSLogHandler(subsystem: "test", category: "value")
        handler1.logLevel = .debug
        handler1[metadataKey: "only-on"] = "first"

        var handler2 = handler1
        handler2.logLevel = .error
        handler2[metadataKey: "only-on"] = "second"

        #expect(handler1.logLevel == .debug)
        #expect(handler2.logLevel == .error)
        #expect(handler1[metadataKey: "only-on"]?.description == "first")
        #expect(handler2[metadataKey: "only-on"]?.description == "second")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func explicitLogLevelOverridesSystemEnablement() {
        // With no override, the level is derived from the system's current enablement (environment
        // dependent, so not asserted here). An explicit assignment must take precedence regardless.
        var handler = OSLogHandler(subsystem: "test", category: "override")
        handler.logLevel = .critical
        #expect(handler.logLevel == .critical)
        handler.logLevel = .trace
        #expect(handler.logLevel == .trace)
    }
}

#endif
