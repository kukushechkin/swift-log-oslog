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
import Foundation
import Logging
import OSLog
import OSLogHandler
import SensitivityAttribute
import Testing

@Suite
struct OSLogHandlerJSONFormatTests {
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    private static func fragments(
        _ handler: OSLogHandler,
        for event: LogEvent
    ) -> (publicFragment: String, privateFragment: String) {
        handler.fragments(for: event)
    }

    // MARK: - Events

    private func event(
        message: Logging.Logger.Message = "msg",
        metadata: Logging.Logger.Metadata? = nil,
        error: (any Error)? = nil
    ) -> LogEvent {
        LogEvent(
            level: .info,
            message: message,
            error: error,
            metadata: metadata,
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func keyValueIsTheDefaultFormat() {
        let handler = OSLogHandler(subsystem: "test", category: "default-format")
        #expect(handler.metadataFormat == .keyValue)

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: ["a": .attributed("1", attributes: [Sensitivity.public]), "b": "2"])
        )

        #expect(publicFragment == "a=1")
        #expect(privateFragment == "b=2")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func keyValueKeepsANestedValuePrivateWhateverItsLeavesAreTagged() {
        let handler = OSLogHandler(subsystem: "test", category: "nested-key-value")

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: [
                "request": .dictionary(["method": .attributed("PUT", attributes: [Sensitivity.public])])
            ])
        )

        #expect(publicFragment.isEmpty)
        #expect(privateFragment == "request=[\"method\": \"PUT\"]")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func jsonKeepsANestedValueWithPublicLeavesPublic() {
        let handler = OSLogHandler(subsystem: "test", category: "nested-json", metadataFormat: .json)

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: [
                "request": .dictionary(["method": .attributed("PUT", attributes: [Sensitivity.public])])
            ])
        )

        #expect(publicFragment == "{\"request\":{\"method\":\"PUT\"}}")
        #expect(privateFragment == "{}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func aLineBreakInAValueSplitsKeyValueTextAndStaysEscapedInJSON() {
        let metadata: Logging.Logger.Metadata = [
            "reason": .attributed("disk full\nretry later", attributes: [Sensitivity.public])
        ]
        let keyValue = OSLogHandler(subsystem: "test", category: "newline-key-value")
        let json = OSLogHandler(subsystem: "test", category: "newline-json", metadataFormat: .json)

        let (keyValueText, _) = Self.fragments(keyValue, for: self.event(metadata: metadata))
        let (jsonText, _) = Self.fragments(json, for: self.event(metadata: metadata))

        #expect(keyValueText == "reason=disk full\nretry later")
        #expect(jsonText == "{\"reason\":\"disk full\\nretry later\"}")
        #expect(!jsonText.contains("\n"))
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func jsonWritesAnEmptyObjectForAHalfWithoutEntries() {
        let handler = OSLogHandler(subsystem: "test", category: "json-empty", metadataFormat: .json)

        let (noMetadataPublic, noMetadataPrivate) = Self.fragments(handler, for: self.event())
        let (onlyPublic, noPrivate) = Self.fragments(
            handler,
            for: self.event(metadata: ["a": .attributed("1", attributes: [Sensitivity.public])])
        )
        let (noPublic, onlyPrivate) = Self.fragments(handler, for: self.event(metadata: ["b": "2"]))

        #expect(noMetadataPublic == "{}")
        #expect(noMetadataPrivate == "{}")
        #expect(onlyPublic == "{\"a\":\"1\"}")
        #expect(noPrivate == "{}")
        #expect(noPublic == "{}")
        #expect(onlyPrivate == "{\"b\":\"2\"}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func writesOneObjectForEachHalf() {
        let handler = OSLogHandler(subsystem: "test", category: "json", metadataFormat: .json)

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: [
                "method": .attributed("GET", attributes: [Sensitivity.public]),
                "user.id": .attributed("u-1", attributes: [Sensitivity.sensitive]),
                "client_ip": "203.0.113.5",  // untagged, so private
            ])
        )

        #expect(publicFragment == "{\"method\":\"GET\"}")
        #expect(privateFragment == "{\"client_ip\":\"203.0.113.5\",\"user.id\":\"u-1\"}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func escapesValues() {
        let handler = OSLogHandler(subsystem: "test", category: "json-escape", metadataFormat: .json)

        let (publicFragment, _) = Self.fragments(
            handler,
            for: self.event(metadata: ["k": .attributed("say \"hi\"\n", attributes: [Sensitivity.public])])
        )

        #expect(publicFragment == "{\"k\":\"say \\\"hi\\\"\\n\"}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func keepsNestedValuesWithASensitiveLeafPrivate() {
        let handler = OSLogHandler(subsystem: "test", category: "json-nested", metadataFormat: .json)

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: [
                "ok": .dictionary(["a": .attributed("1", attributes: [Sensitivity.public])]),
                "mixed": .dictionary([
                    "a": .attributed("1", attributes: [Sensitivity.public]),
                    "b": "2",
                ]),
            ])
        )

        #expect(publicFragment == "{\"ok\":{\"a\":\"1\"}}")
        #expect(privateFragment == "{\"mixed\":{\"a\":\"1\",\"b\":\"2\"}}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func joinsBaseMetadataAndEmissionMetadata() {
        var handler = OSLogHandler(subsystem: "test", category: "json-base", metadataFormat: .json)
        handler[metadataKey: "service"] = .attributed("api", attributes: [Sensitivity.public])
        handler[metadataKey: "tenant"] = "t-1"

        let (cachedPublic, cachedPrivate) = Self.fragments(handler, for: self.event())
        #expect(cachedPublic == "{\"service\":\"api\"}")
        #expect(cachedPrivate == "{\"tenant\":\"t-1\"}")

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: ["id": .attributed("7", attributes: [Sensitivity.public])])
        )
        #expect(publicFragment == "{\"service\":\"api\",\"id\":\"7\"}")
        #expect(privateFragment == "{\"tenant\":\"t-1\"}")

        // The getters read the base metadata.
        #expect(handler.metadata.count == 2)
        #expect(handler[metadataKey: "tenant"]?.description == "t-1")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func keepsInjectedErrorFieldsPrivate() {
        struct SampleError: Error {}
        let handler = OSLogHandler(subsystem: "test", category: "json-error", metadataFormat: .json)

        let (publicFragment, privateFragment) = Self.fragments(handler, for: self.event(error: SampleError()))

        #expect(publicFragment == "{}")
        #expect(privateFragment.contains("\"error.message\""))
        #expect(privateFragment.contains("\"error.type\""))
    }

    // MARK: - Classification and conflicts

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func baseKeyMovesBetweenObjectsWhenItsSensitivityChanges() {
        var handler = OSLogHandler(subsystem: "test", category: "json-move", metadataFormat: .json)
        handler[metadataKey: "k"] = "secret"
        #expect(Self.fragments(handler, for: self.event()).privateFragment == "{\"k\":\"secret\"}")

        handler[metadataKey: "k"] = .attributed("open", attributes: [Sensitivity.public])
        let (publicFragment, privateFragment) = Self.fragments(handler, for: self.event())
        #expect(publicFragment == "{\"k\":\"open\"}")
        #expect(privateFragment == "{}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func eventValueWinsOverBaseValueAndChangesTheObject() {
        var handler = OSLogHandler(subsystem: "test", category: "json-conflict", metadataFormat: .json)
        handler[metadataKey: "k"] = .attributed("base", attributes: [Sensitivity.public])

        // A sensitive event value replaces a public base value. The key leaves the public object.
        let (publicFragment, privateFragment) = Self.fragments(handler, for: self.event(metadata: ["k": "event"]))

        #expect(publicFragment == "{}")
        #expect(privateFragment == "{\"k\":\"event\"}")
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func composedAndDecomposedKeysCountAsOneKey() {
        var handler = OSLogHandler(subsystem: "test", category: "json-unicode", metadataFormat: .json)
        handler[metadataKey: "caf\u{E9}"] = .attributed("base", attributes: [Sensitivity.public])

        // `e` followed by a combining accent is the same Swift `String` key as the composed character.
        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: ["cafe\u{301}": "event"])
        )

        #expect(publicFragment == "{}")
        #expect(privateFragment.contains("event"))
        #expect(!privateFragment.contains("base"))
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func producedObjectsParseAsJSON() throws {
        let handler = OSLogHandler(subsystem: "test", category: "json-parse", metadataFormat: .json)
        let value = "q\" b\\ n\n t\t \u{1} \u{2028}\u{2029} \u{1F600}"

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: [
                "p": .attributed(value, attributes: [Sensitivity.public]),
                "s": "\(value)",
                "list": .array(["a", .dictionary(["k": "v"])]),
            ])
        )

        let publicObject = try JSONSerialization.jsonObject(with: Data(publicFragment.utf8)) as? [String: String]
        #expect(publicObject == ["p": value])
        let privateObject = try #require(
            try JSONSerialization.jsonObject(with: Data(privateFragment.utf8)) as? [String: Any]
        )
        #expect(privateObject["s"] as? String == value)
        #expect(privateObject["list"] is [Any])
    }

    @Test
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    func stringConvertibleWithoutAnAttributeInsideAContainerIsSensitive() {
        let handler = OSLogHandler(subsystem: "test", category: "json-convertible", metadataFormat: .json)

        let (publicFragment, privateFragment) = Self.fragments(
            handler,
            for: self.event(metadata: [
                "c": .array([.attributed("x", attributes: [Sensitivity.public]), .stringConvertible(42)])
            ])
        )

        #expect(publicFragment == "{}")
        #expect(privateFragment == "{\"c\":[\"x\",\"42\"]}")
    }

    // MARK: - Unified log

    /// Logs through the handler and reads the entry back with `OSLogStore`. The format string has the labels, and
    /// each part is its own component that parses as JSON.
    @Test
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    func componentsAreSeparateJSONObjects() async throws {
        let subsystem = "com.example.osLogJSONHandlerTests.\(UUID().uuidString)"
        let started = Date().addingTimeInterval(-1)
        let logger = Logging.Logger(label: "test") { _ in
            var handler = OSLogHandler(subsystem: subsystem, category: "round-trip", metadataFormat: .json)
            handler.logLevel = .info
            return handler
        }
        logger.info(
            "Upload \"failed\"",
            metadata: [
                "reason": "\("disk full", sensitivity: .public)",
                "path": "\("/Users/a b/report.txt", sensitivity: .sensitive)",
            ]
        )
        logger.info("Upload finished")

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        var entries = [OSLogEntryLog]()
        for _ in 0..<100 where entries.count < 2 {
            entries = try store.getEntries(at: store.position(date: started))
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == subsystem }
            if entries.count < 2 { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        try #require(entries.count == 2)

        // Every entry has the same format string and three arguments, whatever metadata the call has.
        for entry in entries {
            #expect(entry.formatString == "%{public}s public=%{public}s sensitive=%{private}s")
        }

        let arguments = entries[0].components.filter { $0.argumentStringValue != nil }
        try #require(arguments.count == 3)
        #expect(arguments.map(\.placeholder) == ["%{public}s", "%{public}s", "%{private}s"])
        #expect(arguments[0].argumentStringValue == "Upload \"failed\"")

        let publicObject = try JSONSerialization.jsonObject(
            with: Data(try #require(arguments[1].argumentStringValue).utf8)
        )
        #expect((publicObject as? [String: String]) == ["reason": "disk full"])

        // The sensitive argument reads `<private>` when OSLog redacts it. Otherwise it holds JSON.
        let sensitiveText = try #require(arguments[2].argumentStringValue)
        if sensitiveText != "<private>" {
            let sensitiveObject = try JSONSerialization.jsonObject(with: Data(sensitiveText.utf8))
            #expect((sensitiveObject as? [String: String]) == ["path": "/Users/a b/report.txt"])
        }

        // A call without metadata writes an empty object for each half.
        let empty = entries[1].components.filter { $0.argumentStringValue != nil }
        try #require(empty.count == 3)
        #expect(empty[0].argumentStringValue == "Upload finished")
        #expect(empty[1].argumentStringValue == "{}")
        #expect(["{}", "<private>"].contains(empty[2].argumentStringValue))
    }
}

#endif
