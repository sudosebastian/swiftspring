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
    public let templates: TemplateService
    public let scheduledSends: ScheduledSendService
    public let followUpReminders: FollowUpReminderService
    public let activity: LocalActivityService
    public let gateway: SelfHostedGatewayService
    public let localTextServices: LocalTextServiceSettings
    public let grammar: LocalGrammarService
    public let translation: LocalTranslationService
    public let featureScheduler: LocalFeatureScheduler
    public let notifications: NotificationService
    public let calendar: CalendarService

    private var localFeatureSchedulerTask: Task<Void, Never>?

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
        self.templates = TemplateService(repository: repository)
        self.scheduledSends = ScheduledSendService(repository: repository)
        self.followUpReminders = FollowUpReminderService(repository: repository)
        self.activity = LocalActivityService(repository: repository)
        self.gateway = SelfHostedGatewayService(repository: repository)
        let textServices = LocalTextServiceSettings(repository: repository)
        self.localTextServices = textServices
        self.grammar = LocalGrammarService(settings: textServices)
        self.translation = LocalTranslationService(settings: textServices)
        self.featureScheduler = LocalFeatureScheduler(repository: repository, syncEngine: engine)
        self.notifications = NotificationService()
        self.calendar = CalendarService(repository: repository)
        self.mail.contacts = self.contacts
    }

    /// Starts the on-device scheduler while the app is open. Background refresh
    /// invokes the same processor when the operating system grants time.
    public func startLocalFeatureScheduler() {
        guard localFeatureSchedulerTask == nil else { return }
        localFeatureSchedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.processLocalFeatures()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    public func stopLocalFeatureScheduler() {
        localFeatureSchedulerTask?.cancel()
        localFeatureSchedulerTask = nil
    }

    public func processLocalFeatures(now: Date = Date()) async {
        let result = await featureScheduler.processDue(now: now)
        if !result.sentMessageIDs.isEmpty {
            notifications.status = "Sent \(result.sentMessageIDs.count) scheduled message\(result.sentMessageIDs.count == 1 ? "" : "s")"
        }
        if !result.dueReminderThreadIDs.isEmpty {
            notifications.status = "\(result.dueReminderThreadIDs.count) follow-up reminder\(result.dueReminderThreadIDs.count == 1 ? "" : "s") due"
        }
        if !result.unsnoozedThreadIDs.isEmpty {
            notifications.status = "\(result.unsnoozedThreadIDs.count) snoozed conversation\(result.unsnoozedThreadIDs.count == 1 ? "" : "s") returned"
        }
    }

    /// Boots the shared application environment.
    /// - Parameter demo: When `true`, uses in-memory credentials and the demo transport.
    ///   Defaults to `false` so device/macOS launches use Keychain + real MailCore.
    ///   Override with `SWIFTSPRING_DEMO=1` for local demo runs. The iOS Simulator
    ///   always uses the demo transport (MailCore IMAP is unreliable there).
    public static func bootstrap(demo: Bool = false) throws -> AppEnvironment {
        let envFlag = ProcessInfo.processInfo.environment["SWIFTSPRING_DEMO"]?.lowercased()
        let wantDemo = demo || envFlag == "1" || envFlag == "true"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Swiftspring", isDirectory: true)
        let db = try AppDatabase.open(in: support)
        #if targetEnvironment(simulator)
        let useDemo = true
        #else
        let useDemo = wantDemo
        #endif
        // Prefer Keychain on device; use memory only for explicit demo runs.
        let creds: CredentialStore = wantDemo ? InMemoryCredentialStore() : KeychainCredentialStore()
        return AppEnvironment(database: db, credentials: creds, useDemoTransport: useDemo)
    }

    public static func preview() throws -> AppEnvironment {
        let db = try AppDatabase.openInMemory()
        let env = AppEnvironment(database: db, credentials: InMemoryCredentialStore(), useDemoTransport: true)
        return env
    }
}
