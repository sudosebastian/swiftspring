import Foundation

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// iOS background sync registration and macOS idle-friendly refresh helper.
public enum BackgroundSyncCoordinator {
    public static let refreshTaskIdentifier = "com.swiftspring.sync.refresh"

    @MainActor
    private static var syncEngine: SyncEngine?

    /// Bind the live sync engine so background refresh can sync the open mailbox.
    @MainActor
    public static func bind(syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
    }

    @MainActor
    public static func register() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let work = Task {
                let success = await performRefresh()
                refresh.setTaskCompleted(success: success)
            }
            refresh.expirationHandler = {
                work.cancel()
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

    /// Runs sync via the bound engine, or a standalone engine against the shared DB.
    public static func performRefresh() async -> Bool {
        if let engine = await MainActor.run(body: { syncEngine }) {
            await engine.startAll()
            return true
        }
        do {
            let db = try AppGroupStore.openSharedDatabase()
            let repository = MailRepository(db: db)
            let engine = SyncEngine(
                repository: repository,
                credentials: KeychainCredentialStore(),
                transportFactory: { MailTransportFactory.make() }
            )
            await engine.startAll()
            return true
        } catch {
            return false
        }
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
