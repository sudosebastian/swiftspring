import Foundation

public actor SyncEngine {
    private let repository: MailRepository
    private let credentials: CredentialStore
    private let transportFactory: @Sendable () -> any MailTransport
    private var actors: [EntityID: AccountSyncActor] = [:]

    public init(
        repository: MailRepository,
        credentials: CredentialStore,
        transportFactory: @escaping @Sendable () -> any MailTransport = { MailTransportFactory.make() }
    ) {
        self.repository = repository
        self.credentials = credentials
        self.transportFactory = transportFactory
    }

    public func startAll() async {
        let accounts = (try? repository.allAccounts()) ?? []
        for account in accounts {
            await start(accountId: account.id)
        }
    }

    public func start(accountId: EntityID) async {
        let actor = actors[accountId] ?? AccountSyncActor(
            accountId: accountId,
            repository: repository,
            credentials: credentials,
            transport: transportFactory()
        )
        actors[accountId] = actor
        await actor.start()
    }

    public func sync(accountId: EntityID) async {
        await start(accountId: accountId)
    }

    public func processTasks(accountId: EntityID) async throws {
        if actors[accountId] == nil {
            actors[accountId] = AccountSyncActor(
                accountId: accountId,
                repository: repository,
                credentials: credentials,
                transport: transportFactory()
            )
        }
        try await actors[accountId]?.processPendingTasks()
    }

    public func fetchBody(accountId: EntityID, messageId: EntityID) async throws {
        if actors[accountId] == nil {
            actors[accountId] = AccountSyncActor(
                accountId: accountId,
                repository: repository,
                credentials: credentials,
                transport: transportFactory()
            )
        }
        try await actors[accountId]?.fetchAndStoreBody(messageId: messageId)
    }
}
