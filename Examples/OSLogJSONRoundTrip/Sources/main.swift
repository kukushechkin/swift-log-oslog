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
import OSLog
import OSLogHandler
import SensitivityAttribute

/// The fields that the example decodes from the public object.
struct UploadFields: Decodable {
    var reason: String?
    var attempt: String?
}

/// One log entry that `OSLogHandler` wrote with the `.json` format, split into its parts.
struct ParsedEntry {
    var message: String?
    var publicObject: [String: Any]?
    var publicText: String?
    var sensitiveObject: [String: Any]?
    var sensitiveWasRedacted = false
    var wasCut = false
}

/// Splits an entry into the message and the two objects.
func parse(_ entry: OSLogEntryLog) -> ParsedEntry {
    var parsed = ParsedEntry()
    let arguments = entry.components.filter { !$0.placeholder.isEmpty }
    guard arguments.count == 3 else { return parsed }
    // An argument that did not fit in the message has no string value.
    parsed.wasCut = arguments.contains { $0.argumentStringValue == nil }
    parsed.message = arguments[0].argumentStringValue
    if let text = arguments[1].argumentStringValue {
        parsed.publicText = text
        parsed.publicObject = object(from: text)
    }
    if let text = arguments[2].argumentStringValue {
        if text == "<private>" {
            parsed.sensitiveWasRedacted = true
        } else {
            parsed.sensitiveObject = object(from: text)
        }
    }
    return parsed
}

/// Parses `text` as a JSON object.
func object(from text: String) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
}

// Log through `OSLogHandler` with the `.json` metadata format.
let started = Date().addingTimeInterval(-1)
let subsystem = "com.example.OSLogJSONRoundTrip"
let logger = Logger(label: "example") { _ in
    OSLogHandler(subsystem: subsystem, category: "upload", metadataFormat: .json)
}
logger.info(
    "Upload failed",
    metadata: [
        "reason": "\("disk full", sensitivity: .public)",
        "path": "\("/Users/a b/report.txt", sensitivity: .sensitive)",
    ]
)
logger.info("Upload retried", metadata: ["attempt": "\("2", sensitivity: .public)"])
logger.info("Upload finished")

// Read the entries of this process back. The store can take a moment to show a new entry, so the example waits for
// the last one.
let store = try OSLogStore(scope: .currentProcessIdentifier)
let position = store.position(date: started)
var entries = [OSLogEntryLog]()
for _ in 0..<50 where entries.count < 3 {
    entries = try store.getEntries(at: position).compactMap { $0 as? OSLogEntryLog }.filter {
        $0.subsystem == subsystem
    }
    if entries.count < 3 { try await Task.sleep(nanoseconds: 100_000_000) }
}
for entry in entries {
    let parsed = parse(entry)
    print("message:   \(parsed.message ?? "-")")
    print("public:    \(parsed.publicObject.map { "\($0)" } ?? "-")")
    print("sensitive: \(parsed.sensitiveObject.map { "\($0)" } ?? (parsed.sensitiveWasRedacted ? "<redacted>" : "-"))")
    if let text = parsed.publicText, let fields = try? JSONDecoder().decode(UploadFields.self, from: Data(text.utf8)) {
        print("decoded:   reason=\(fields.reason ?? "-") attempt=\(fields.attempt ?? "-")")
    }
    if parsed.wasCut { print("cut:       an argument did not fit in the message") }
    print()
}
