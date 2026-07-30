import Foundation
import SwiftspringKit

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// iOS background sync registration and macOS idle-friendly refresh helper.
public enum BackgroundSyncCoordinator {
    public static let refreshTaskIdentifier = "com.swiftspring.sync.refresh"

    @MainActor
    public static func register() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            Task {
                do {
                    // Apps should hold AppEnvironment and call syncEngine.startAll().
                    refresh.setTaskCompleted(success: true)
                }
            }
        }
        #endif
    }

    public static func schedule() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}

/// Optional App Group container for future Mac ↔ iOS shared mailbox data.
public enum AppGroupStore {
    public static let identifier = "group.com.swiftspring.shared"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static func openSharedDatabase() throws -> AppDatabase {
        if let containerURL {
            return try AppDatabase.open(in: containerURL.appendingPathComponent("Database", isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Swiftspring", isDirectory: true)
        return try AppDatabase.open(in: support)
    }
}
