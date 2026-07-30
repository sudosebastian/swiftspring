import XCTest
@testable import SwiftspringKit

final class ThreadingEngineTests: XCTestCase {
    func testNormalizedSubjectStripsReplyPrefixes() {
        XCTAssertEqual(ThreadingEngine.normalizedSubject("Re: Hello"), "hello")
        XCTAssertEqual(ThreadingEngine.normalizedSubject("Fwd: Re: Hello"), "hello")
    }

    func testThreadKeyUsesReferences() {
        let header = RemoteMessageHeader(
            uid: 1,
            headerMessageId: "<child@example.com>",
            subject: "Re: Hello",
            references: ["<root@example.com>"]
        )
        XCTAssertEqual(ThreadingEngine.threadKey(for: header), "root@example.com")
    }
}

final class RepositoryTests: XCTestCase {
    @MainActor
    func testAccountRoundTrip() throws {
        let db = try AppDatabase.openInMemory()
        let repo = MailRepository(db: db)
        let account = Account(
            name: "Test",
            emailAddress: "test@example.com",
            provider: .imap,
            imap: ServerSettings(host: "imap.example.com", port: 993, username: "test@example.com"),
            smtp: ServerSettings(host: "smtp.example.com", port: 587, username: "test@example.com", security: .startTLS)
        )
        try repo.upsertAccount(account)
        let loaded = try repo.account(id: account.id)
        XCTAssertEqual(loaded?.emailAddress, "test@example.com")
    }

    @MainActor
    func testDemoSyncProducesThreads() async throws {
        let db = try AppDatabase.openInMemory()
        let creds = InMemoryCredentialStore()
        let transport = InMemoryMailTransport(seedDemoMail: true)
        let repo = MailRepository(db: db)
        let engine = SyncEngine(repository: repo, credentials: creds, transportFactory: { transport })
        let accounts = AccountService(
            repository: repo,
            credentials: creds,
            syncEngine: engine,
            transportFactory: { transport }
        )
        let account = try await accounts.addIMAPAccount(
            name: "Demo",
            email: "you@example.com",
            provider: .imap,
            password: "demo",
            imap: ServerSettings(host: "localhost", port: 993, username: "you@example.com"),
            smtp: ServerSettings(host: "localhost", port: 587, username: "you@example.com")
        )
        let folders = try repo.folders(accountId: account.id)
        XCTAssertFalse(folders.isEmpty)
        let inbox = try repo.folder(accountId: account.id, role: .inbox)
        XCTAssertNotNil(inbox)
        let threads = try repo.threads(folderId: inbox?.id)
        XCTAssertGreaterThanOrEqual(threads.count, 1)
    }
}

final class MailRulesTests: XCTestCase {
    func testRuleMatching() throws {
        let db = try AppDatabase.openInMemory()
        let repo = MailRepository(db: db)
        let service = MailRulesService(repository: repo)
        let condition = MailRuleCondition(fromContains: "news")
        let action = MailRuleAction(markRead: true)
        let rule = MailRule(
            name: "Newsletters",
            conditionJSON: try MailTaskCodec.encode(condition),
            actionJSON: try MailTaskCodec.encode(action)
        )
        try service.save(rule)
        let message = Message(
            accountId: EntityID(),
            threadId: EntityID(),
            subject: "Weekly",
            from: [EmailAddress(email: "news@example.com")]
        )
        let matches = try service.matchingRules(for: message)
        XCTAssertEqual(matches.count, 1)
    }
}
