import Foundation
import Combine

@MainActor
public final class AccountService: ObservableObject {
    @Published public private(set) var accounts: [Account] = []
    @Published public var lastError: String?

    public let repository: MailRepository
    public let credentials: CredentialStore
    public let syncEngine: SyncEngine
    public let oauth: OAuthService
    public var googleClientId: String
    public var microsoftClientId: String
    private let transportFactory: @Sendable () -> any MailTransport
    /// CSRF `state` for the in-flight OAuth authorization request.
    private var pendingOAuthState: String?

    public init(
        repository: MailRepository,
        credentials: CredentialStore,
        syncEngine: SyncEngine,
        oauth: OAuthService = OAuthService(),
        googleClientId: String = "",
        microsoftClientId: String = "",
        transportFactory: @escaping @Sendable () -> any MailTransport = { MailTransportFactory.make() }
    ) {
        self.repository = repository
        self.credentials = credentials
        self.syncEngine = syncEngine
        self.oauth = oauth
        self.googleClientId = googleClientId
        self.microsoftClientId = microsoftClientId
        self.transportFactory = transportFactory
        refresh()
    }

    public func refresh() {
        accounts = (try? repository.allAccounts()) ?? []
    }

    public func addIMAPAccount(
        name: String,
        email: String,
        provider: MailProvider,
        password: String,
        imap: ServerSettings? = nil,
        smtp: ServerSettings? = nil
    ) async throws -> Account {
        let presets = ProviderPresets.settings(for: provider, email: email)
        let account = Account(
            name: name,
            emailAddress: email,
            provider: provider,
            imap: imap ?? presets.imap,
            smtp: smtp ?? presets.smtp,
            syncState: .authenticating
        )
        let creds = AccountCredentials(password: password)
        let transport = transportFactory()
        try await transport.testConnection(imap: account.imap, smtp: account.smtp, credentials: creds)
        try credentials.save(accountId: account.id, credentials: creds)
        var saved = account
        saved.syncState = .ok
        try repository.upsertAccount(saved)
        refresh()
        await syncEngine.start(accountId: saved.id)
        refresh()
        return saved
    }

    public func completeOAuth(
        provider: MailProvider,
        code: String,
        state: String? = nil
    ) async throws -> Account {
        guard let state, let pending = pendingOAuthState, state == pending else {
            pendingOAuthState = nil
            throw OAuthError.stateMismatch
        }
        pendingOAuthState = nil

        let config: OAuthConfiguration
        switch provider {
        case .gmail:
            config = .google(clientId: googleClientId)
        case .office365, .outlook:
            config = .microsoft(clientId: microsoftClientId)
        default:
            throw OAuthError.invalidAuthorizationURL
        }

        let tokens = try await oauth.exchangeCode(code, config: config)
        let profile: OAuthUserProfile
        switch provider {
        case .gmail:
            profile = try await oauth.fetchGoogleProfile(accessToken: tokens.accessToken)
        default:
            profile = try await oauth.fetchMicrosoftProfile(accessToken: tokens.accessToken)
        }

        let presets = ProviderPresets.settings(for: provider, email: profile.email)
        let account = Account(
            name: profile.name ?? profile.email,
            emailAddress: profile.email,
            provider: provider,
            imap: presets.imap,
            smtp: presets.smtp,
            syncState: .ok
        )
        var creds = AccountCredentials(
            refreshToken: tokens.refreshToken,
            accessToken: tokens.accessToken,
            oauthClientId: config.clientId
        )
        if let expiresIn = tokens.expiresIn {
            creds.accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
        try credentials.save(accountId: account.id, credentials: creds)
        try repository.upsertAccount(account)
        refresh()
        await syncEngine.start(accountId: account.id)
        refresh()
        return account
    }

    public func authorizationURL(for provider: MailProvider) throws -> URL {
        let state = UUID().uuidString
        pendingOAuthState = state
        switch provider {
        case .gmail:
            return try oauth.authorizationURL(config: .google(clientId: googleClientId), state: state)
        case .office365, .outlook:
            return try oauth.authorizationURL(config: .microsoft(clientId: microsoftClientId), state: state)
        default:
            pendingOAuthState = nil
            throw OAuthError.invalidAuthorizationURL
        }
    }

    public func removeAccount(_ account: Account) throws {
        try credentials.delete(accountId: account.id)
        try repository.deleteAccount(id: account.id)
        refresh()
    }

    public func addDemoAccount() async throws -> Account {
        try await addIMAPAccount(
            name: "Demo",
            email: "you@example.com",
            provider: .imap,
            password: "demo",
            imap: ServerSettings(host: "localhost", port: 993, username: "you@example.com"),
            smtp: ServerSettings(host: "localhost", port: 587, username: "you@example.com", security: .startTLS)
        )
    }
}
