import Testing

/// Parent suite that serializes all sync test suites to prevent
/// `NotificationCenter` cross-talk between `SaveMonitor` instances.
@Suite("SyncTests", .serialized)
enum SyncTests {}
