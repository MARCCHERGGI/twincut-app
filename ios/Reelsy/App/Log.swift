import os

/// Unified-log channels; CI streams subsystem com.marcohergi.reelsy into the test artifact.
enum Log {
    static let export = Logger(subsystem: "com.marcohergi.reelsy", category: "export")
    static let analysis = Logger(subsystem: "com.marcohergi.reelsy", category: "analysis")
    static let library = Logger(subsystem: "com.marcohergi.reelsy", category: "library")
}
