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

import Benchmark
import Logging
import OSLogHandler
import SensitivityAttribute

// No `import os` here, so `Logger` unambiguously means swift-log's `Logger`.

/// Creates a `Logger` backed by `OSLogHandler`.
///
/// The log level is fixed to `.info`, so the unified logging configuration of the machine does not affect the
/// results.
///
/// - Parameters:
///   - category: The category of the handler and the label of the logger.
///   - base: The base metadata of the handler.
///   - json: Whether the handler uses the `.json` metadata format.
private func makeBridgeLogger(
    category: String,
    base: Logger.Metadata = [:],
    json: Bool
) -> Logger {
    var handler = OSLogHandler(
        subsystem: "com.example.applelogbench",
        category: category,
        metadataFormat: json ? .json : .keyValue
    )
    for (key, value) in base {
        handler[metadataKey: key] = value
    }
    var logger = Logger(label: category) { _ in handler }
    logger.logLevel = .info
    return logger
}

/// Registers the benchmarks that log through swift-log and `OSLogHandler`.
///
/// - Parameters:
///   - configuration: The measurement settings shared by all benchmarks.
///   - json: Whether the handler uses the `.json` metadata format. The names of the benchmarks then start with
///     `json_`.
func bridgeBenchmarks(configuration: Benchmark.Configuration, json: Bool = false) {
    let prefix = json ? "json_" : ""
    let suffix = json ? "-json" : ""
    // A constant message and no metadata.
    let noMetadata = makeBridgeLogger(category: "bridge-nometa\(suffix)", json: json)
    Benchmark("\(prefix)bridge_no_metadata", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            noMetadata.info("req")
        }
    }

    // One field passed at each log call.
    let emissionTime = makeBridgeLogger(category: "bridge-emission\(suffix)", json: json)
    Benchmark("\(prefix)bridge_emission_time_metadata", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            emissionTime.info("req", metadata: ["id": "\(42, sensitivity: .public)"])
        }
    }

    // The same field, set once on the handler as base metadata. The log calls pass no metadata.
    let baseMetadata: Logger.Metadata = ["id": "\(42, sensitivity: .public)"]
    let withBaseMetadata = makeBridgeLogger(
        category: "bridge-base\(suffix)",
        base: baseMetadata,
        json: json
    )
    Benchmark("\(prefix)bridge_base_metadata", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            withBaseMetadata.info("req")
        }
    }

    // One base field and one field passed at each log call.
    let baseContext: Logger.Metadata = ["ctx": "\(1, sensitivity: .public)"]
    let withBaseAndEmission = makeBridgeLogger(
        category: "bridge-both\(suffix)",
        base: baseContext,
        json: json
    )
    Benchmark("\(prefix)bridge_base_and_emission_metadata", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            withBaseAndEmission.info("req", metadata: ["id": "\(42, sensitivity: .public)"])
        }
    }

    // The same, with 24 base entries.
    var largeBase = Logger.Metadata()
    for i in 0..<24 {
        largeBase["ctx-\(i)"] = "\("value-\(i)", sensitivity: .public)"
    }
    let withLargeBase = makeBridgeLogger(
        category: "bridge-large-base\(suffix)",
        base: largeBase,
        json: json
    )
    Benchmark("\(prefix)bridge_large_base_and_emission_metadata", configuration: configuration) { benchmark in
        for _ in benchmark.scaledIterations {
            withLargeBase.info("req", metadata: ["id": "\(42, sensitivity: .public)"])
        }
    }

    // A `withLogger(mergingMetadata:)` scope with 24 base entries and 10 log calls that pass one field each. The
    // outer `withLogger` makes `scopeLogger` the current logger, which the inner call extends. The measurement
    // includes the scope setup. One iteration is expensive, so this benchmark does not use the scaling factor.
    var unscaledConfiguration = configuration
    unscaledConfiguration.scalingFactor = .one
    let scopeLogger = makeBridgeLogger(category: "bridge-scope\(suffix)", json: json)
    Benchmark("\(prefix)bridge_scope_large_base_multiple_emissions", configuration: unscaledConfiguration) { _ in
        withLogger(scopeLogger) { _ in
            withLogger(mergingMetadata: largeBase) { logger in
                for _ in 0..<10 {
                    logger.info("req", metadata: ["id": "\(42, sensitivity: .public)"])
                }
            }
        }
    }
}
