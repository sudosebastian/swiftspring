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

final class ThreadFolderTests: XCTestCase {
    func testUpsertThreadReplacesFolderMembership() throws {
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
        let inbox = MailFolder(accountId: account.id, path: "INBOX", name: "Inbox", role: .inbox)
        let archive = MailFolder(accountId: account.id, path: "Archive", name: "Archive", role: .archive)
        try repo.upsertFolders([inbox, archive])

        var thread = MailThread(accountId: account.id, subject: "Move me", folderIds: [inbox.id])
        try repo.upsertThread(thread)
        XCTAssertEqual(try repo.threads(folderId: inbox.id).map(\.id), [thread.id])

        thread.folderIds = [archive.id]
        try repo.upsertThread(thread)

        XCTAssertTrue(try repo.threads(folderId: inbox.id).isEmpty)
        XCTAssertEqual(try repo.threads(folderId: archive.id).map(\.id), [thread.id])
    }
}

final class SyncDedupeTests: XCTestCase {
    @MainActor
    func testResyncDoesNotDuplicateMessages() async throws {
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
        guard var inbox = try repo.folder(accountId: account.id, role: .inbox) else {
            return XCTFail("Missing inbox")
        }
        let firstCount = try repo.messageStats(folderId: inbox.id).total
        XCTAssertGreaterThan(firstCount, 0)

        // Force a full refetch of the same IMAP UIDs.
        inbox.uidNext = nil
        try repo.upsertFolder(inbox)
        await engine.sync(accountId: account.id)

        let secondCount = try repo.messageStats(folderId: inbox.id).total
        XCTAssertEqual(firstCount, secondCount)
    }
}

final class OAuthStateTests: XCTestCase {
    @MainActor
    func testCompleteOAuthRejectsMismatchedState() async throws {
        let db = try AppDatabase.openInMemory()
        let creds = InMemoryCredentialStore()
        let transport = InMemoryMailTransport(seedDemoMail: true)
        let repo = MailRepository(db: db)
        let engine = SyncEngine(repository: repo, credentials: creds, transportFactory: { transport })
        let accounts = AccountService(
            repository: repo,
            credentials: creds,
            syncEngine: engine,
            googleClientId: "client",
            transportFactory: { transport }
        )
        _ = try accounts.authorizationURL(for: .gmail)
        do {
            _ = try await accounts.completeOAuth(provider: .gmail, code: "code", state: "wrong-state")
            XCTFail("Expected state mismatch")
        } catch OAuthError.stateMismatch {
            // expected
        }
    }

    @MainActor
    func testCompleteOAuthRejectsMissingState() async throws {
        let db = try AppDatabase.openInMemory()
        let creds = InMemoryCredentialStore()
        let transport = InMemoryMailTransport(seedDemoMail: true)
        let repo = MailRepository(db: db)
        let engine = SyncEngine(repository: repo, credentials: creds, transportFactory: { transport })
        let accounts = AccountService(
            repository: repo,
            credentials: creds,
            syncEngine: engine,
            googleClientId: "client",
            transportFactory: { transport }
        )
        _ = try accounts.authorizationURL(for: .gmail)
        do {
            _ = try await accounts.completeOAuth(provider: .gmail, code: "code")
            XCTFail("Expected state mismatch")
        } catch OAuthError.stateMismatch {
            // expected
        }
    }
}

final class ComposeAttachmentTests: XCTestCase {
    @MainActor
    func testSaveDraftDoesNotDuplicateAttachments() throws {
        let db = try AppDatabase.openInMemory()
        let creds = InMemoryCredentialStore()
        let transport = InMemoryMailTransport(seedDemoMail: true)
        let repo = MailRepository(db: db)
        let engine = SyncEngine(repository: repo, credentials: creds, transportFactory: { transport })
        let compose = ComposeService(repository: repo, syncEngine: engine)

        let account = Account(
            name: "Test",
            emailAddress: "test@example.com",
            provider: .imap,
            imap: ServerSettings(host: "imap.example.com", port: 993, username: "test@example.com"),
            smtp: ServerSettings(host: "smtp.example.com", port: 587, username: "test@example.com", security: .startTLS)
        )
        try repo.upsertAccount(account)
        try repo.upsertFolder(MailFolder(accountId: account.id, path: "Drafts", name: "Drafts", role: .drafts))

        _ = try compose.newDraft(from: account, subject: "With attachment")
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftspring-attach-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        compose.attachmentURLs = [temp]
        try compose.saveDraft()
        try compose.saveDraft()

        let attachments = try repo.attachments(messageId: compose.draft!.id)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.filename, temp.lastPathComponent)
    }
}

final class MailServiceMultiAccountTests: XCTestCase {
    @MainActor
    func testSetUnreadEnqueuesTaskPerAccount() async throws {
        let db = try AppDatabase.openInMemory()
        let creds = InMemoryCredentialStore()
        let transport = InMemoryMailTransport(seedDemoMail: true)
        let repo = MailRepository(db: db)
        let engine = SyncEngine(repository: repo, credentials: creds, transportFactory: { transport })
        let mail = MailService(repository: repo, syncEngine: engine)

        let accountA = Account(
            name: "A",
            emailAddress: "a@example.com",
            provider: .imap,
            imap: ServerSettings(host: "localhost", port: 993, username: "a@example.com"),
            smtp: ServerSettings(host: "localhost", port: 587, username: "a@example.com")
        )
        let accountB = Account(
            name: "B",
            emailAddress: "b@example.com",
            provider: .imap,
            imap: ServerSettings(host: "localhost", port: 993, username: "b@example.com"),
            smtp: ServerSettings(host: "localhost", port: 587, username: "b@example.com")
        )
        try repo.upsertAccount(accountA)
        try repo.upsertAccount(accountB)
        try creds.save(accountId: accountA.id, credentials: AccountCredentials(password: "x"))
        try creds.save(accountId: accountB.id, credentials: AccountCredentials(password: "x"))

        let folderA = MailFolder(accountId: accountA.id, path: "INBOX", name: "Inbox", role: .inbox)
        let folderB = MailFolder(accountId: accountB.id, path: "INBOX", name: "Inbox", role: .inbox)
        try repo.upsertFolders([folderA, folderB])

        let threadA = MailThread(accountId: accountA.id, subject: "A", unread: true, folderIds: [folderA.id])
        let threadB = MailThread(accountId: accountB.id, subject: "B", unread: true, folderIds: [folderB.id])
        try repo.upsertThreads([threadA, threadB])
        try repo.upsertMessages([
            Message(accountId: accountA.id, threadId: threadA.id, folderId: folderA.id, imapUID: 1, subject: "A", unread: true),
            Message(accountId: accountB.id, threadId: threadB.id, folderId: folderB.id, imapUID: 1, subject: "B", unread: true),
        ])

        try await transport.connectIMAP(
            settings: accountA.imap,
            credentials: AccountCredentials(password: "x")
        )
        try await mail.setUnread(threadIds: [threadA.id, threadB.id], unread: false)

        XCTAssertEqual(try repo.thread(id: threadA.id)?.unread, false)
        XCTAssertEqual(try repo.thread(id: threadB.id)?.unread, false)
        XCTAssertTrue(try repo.pendingTasks(accountId: accountA.id).isEmpty)
        XCTAssertTrue(try repo.pendingTasks(accountId: accountB.id).isEmpty)
    }
}
