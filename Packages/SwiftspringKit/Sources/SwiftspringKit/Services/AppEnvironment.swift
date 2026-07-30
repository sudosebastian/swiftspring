import Foundation
import Combine

/// Application-wide composition root for macOS and iOS.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let database: AppDatabase
    public let repository: MailRepository
    public let credentials: CredentialStore
    public let syncEngine: SyncEngine
    public let accounts: AccountService
    public let mail: MailService
    public let compose: ComposeService
    public let search: SearchService
    public let snooze: SnoozeService
    public let rules: MailRulesService
    public let contacts: ContactService
    public let notifications: NotificationService
    public let calendar: CalendarService

    /// Shared demo transport so account connect + sync see the same seeded mailbox.
    public let sharedDemoTransport: InMemoryMailTransport

    public init(
        database: AppDatabase,
        credentials: CredentialStore = KeychainCredentialStore(),
        useDemoTransport: Bool = true,
        googleClientId: String = ProcessInfo.processInfo.environment["SWIFTSPRING_GOOGLE_CLIENT_ID"] ?? "",
        microsoftClientId: String = ProcessInfo.processInfo.environment["SWIFTSPRING_MICROSOFT_CLIENT_ID"] ?? ""
    ) {
        self.database = database
        self.repository = MailRepository(db: database)
        self.credentials = credentials
        let demo = InMemoryMailTransport(seedDemoMail: true)
        self.sharedDemoTransport = demo

        let transportFactory: @Sendable () -> any MailTransport = {
            if useDemoTransport {
                return demo
            }
            return MailTransportFactory.make()
        }

        let engine = SyncEngine(
            repository: repository,
            credentials: credentials,
            transportFactory: transportFactory
        )
        self.syncEngine = engine
        self.accounts = AccountService(
            repository: repository,
            credentials: credentials,
            syncEngine: engine,
            googleClientId: googleClientId,
            microsoftClientId: microsoftClientId,
            transportFactory: transportFactory
        )
        self.mail = MailService(repository: repository, syncEngine: engine)
        self.compose = ComposeService(repository: repository, syncEngine: engine)
        self.search = SearchService(repository: repository)
        self.snooze = SnoozeService(repository: repository)
        self.rules = MailRulesService(repository: repository)
        self.contacts = ContactService(repository: repository)
        self.notifications = NotificationService()
        self.calendar = CalendarService(repository: repository)
    }

    public static func bootstrap(demo: Bool = true) throws -> AppEnvironment {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Swiftspring", isDirectory: true)
        let db = try AppDatabase.open(in: support)
        #if targetEnvironment(simulator)
        let useDemo = true
        #else
        let useDemo = demo
        #endif
        // Prefer Keychain on device; fall back to memory when unavailable in previews/tests.
        let creds: CredentialStore = demo ? InMemoryCredentialStore() : KeychainCredentialStore()
        return AppEnvironment(database: db, credentials: creds, useDemoTransport: useDemo)
    }

    public static func preview() throws -> AppEnvironment {
        let db = try AppDatabase.openInMemory()
        let env = AppEnvironment(database: db, credentials: InMemoryCredentialStore(), useDemoTransport: true)
        return env
    }
}
