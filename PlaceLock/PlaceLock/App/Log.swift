import os

/// PlaceLock's own log lines. View them with:
/// xcrun simctl spawn booted log show --last 10m --info --predicate 'subsystem == "com.nsimon.PlaceLock"'
enum Log {
    static let app = Logger(subsystem: "com.nsimon.PlaceLock", category: "app")
    static let sync = Logger(subsystem: "com.nsimon.PlaceLock", category: "sync")
}
