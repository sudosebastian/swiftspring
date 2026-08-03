import Foundation
import GRDB
import Combine

public struct MailRepository: Sendable {
    public let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Accounts

    public func upsertAccount(_ account: Account) throws {
        try db.dbWriter.write { db in
            try account.save(db)
        }
    }

    public func allAccounts() throws -> [Account] {
        try db.dbWriter.read { db in
            try Account.order(Column("emailAddress")).fetchAll(db)
        }
    }

    public func account(id: EntityID) throws -> Account? {
        try db.dbWriter.read { db in
            try Account.fetchOne(db, key: id)
        }
    }

    public func deleteAccount(id: EntityID) throws {
        try db.dbWriter.write { db in
            _ = try Account.deleteOne(db, key: id)
        }
    }

    public func observeAccounts() -> AnyPublisher<[Account], Error> {
        ValueObservation
            .tracking { db in try Account.order(Column("emailAddress")).fetchAll(db) }
            .publisher(in: db.dbWriter)
            .eraseToAnyPublisher()
    }

    // MARK: - Folders

    public func upsertFolder(_ folder: MailFolder) throws {
        try db.dbWriter.write { db in
            try folder.save(db)
        }
    }

    public func upsertFolders(_ folders: [MailFolder]) throws {
        try db.dbWriter.write { db in
            for folder in folders {
                try folder.save(db)
            }
        }
    }

    public func folders(accountId: EntityID) throws -> [MailFolder] {
        try db.dbWriter.read { db in
            try MailFolder
                .filter(Column("accountId") == accountId)
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    public func folder(id: EntityID) throws -> MailFolder? {
        try db.dbWriter.read { db in
            try MailFolder.fetchOne(db, key: id)
        }
    }

    public func folder(accountId: EntityID, role: FolderRole) throws -> MailFolder? {
        try db.dbWriter.read { db in
            try MailFolder
                .filter(Column("accountId") == accountId && Column("role") == role)
                .fetchOne(db)
        }
    }

    public func observeFolders(accountId: EntityID?) -> AnyPublisher<[MailFolder], Error> {
        ValueObservation
            .tracking { db -> [MailFolder] in
                var request = MailFolder.order(Column("name"))
                if let accountId {
                    request = MailFolder
                        .filter(Column("accountId") == accountId)
                        .order(Column("name"))
                }
                return try request.fetchAll(db)
            }
            .publisher(in: db.dbWriter)
            .eraseToAnyPublisher()
    }

    // MARK: - Threads

    public func upsertThread(_ thread: MailThread) throws {
        try db.dbWriter.write { db in
            try thread.save(db)
            try replaceThreadFolders(db: db, threadId: thread.id, folderIds: thread.folderIds)
        }
    }

    public func upsertThreads(_ threads: [MailThread]) throws {
        try db.dbWriter.write { db in
            for thread in threads {
                try thread.save(db)
                try replaceThreadFolders(db: db, threadId: thread.id, folderIds: thread.folderIds)
            }
        }
    }

    private func replaceThreadFolders(db: Database, threadId: EntityID, folderIds: [EntityID]) throws {
        try db.execute(sql: "DELETE FROM threadFolder WHERE threadId = ?", arguments: [threadId])
        for folderId in folderIds {
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO threadFolder (threadId, folderId) VALUES (?, ?)
                """,
                arguments: [threadId, folderId]
            )
        }
    }

    public func threads(folderId: EntityID?, limit: Int = 100, offset: Int = 0) throws -> [MailThread] {
        try db.dbWriter.read { db in
            if let folderId {
                return try MailThread.fetchAll(
                    db,
                    sql: """
                    SELECT thread.* FROM thread
                    INNER JOIN threadFolder ON threadFolder.threadId = thread.id
                    LEFT JOIN snooze ON snooze.threadId = thread.id
                    WHERE threadFolder.folderId = ?
                    AND (snooze.id IS NULL OR snooze.wakeAt <= ?)
                    ORDER BY thread.lastMessageReceivedAt DESC
                    LIMIT ? OFFSET ?
                    """,
                    arguments: [folderId, Date(), limit, offset]
                )
            }
            return try MailThread.fetchAll(
                db,
                sql: """
                SELECT thread.* FROM thread
                LEFT JOIN snooze ON snooze.threadId = thread.id
                WHERE snooze.id IS NULL OR snooze.wakeAt <= ?
                ORDER BY thread.lastMessageReceivedAt DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [Date(), limit, offset]
            )
        }
    }

    public func thread(id: EntityID) throws -> MailThread? {
        try db.dbWriter.read { db in
            try MailThread.fetchOne(db, key: id)
        }
    }

    public func observeThreads(folderId: EntityID?) -> AnyPublisher<[MailThread], Error> {
        ValueObservation
            .tracking { [folderId] db -> [MailThread] in
                if let folderId {
                    return try MailThread.fetchAll(
                        db,
                        sql: """
                        SELECT thread.* FROM thread
                        INNER JOIN threadFolder ON threadFolder.threadId = thread.id
                        LEFT JOIN snooze ON snooze.threadId = thread.id
                        WHERE threadFolder.folderId = ?
                        AND (snooze.id IS NULL OR snooze.wakeAt <= ?)
                        ORDER BY thread.lastMessageReceivedAt DESC
                        LIMIT 200
                        """,
                        arguments: [folderId, Date()]
                    )
                }
                return try MailThread.fetchAll(
                    db,
                    sql: """
                    SELECT thread.* FROM thread
                    LEFT JOIN snooze ON snooze.threadId = thread.id
                    WHERE snooze.id IS NULL OR snooze.wakeAt <= ?
                    ORDER BY thread.lastMessageReceivedAt DESC
                    LIMIT 200
                    """,
                    arguments: [Date()]
                )
            }
            .publisher(in: db.dbWriter)
            .eraseToAnyPublisher()
    }

    // MARK: - Messages

    public func upsertMessage(_ message: Message) throws {
        try db.dbWriter.write { db in
            try message.save(db)
        }
    }

    public func upsertMessages(_ messages: [Message]) throws {
        try db.dbWriter.write { db in
            for message in messages {
                try message.save(db)
            }
        }
    }

    public func messages(threadId: EntityID) throws -> [Message] {
        try db.dbWriter.read { db in
            try Message
                .filter(Column("threadId") == threadId)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    public func message(id: EntityID) throws -> Message? {
        try db.dbWriter.read { db in
            try Message.fetchOne(db, key: id)
        }
    }

    public func message(folderId: EntityID, imapUID: Int64) throws -> Message? {
        try db.dbWriter.read { db in
            try Message
                .filter(Column("folderId") == folderId && Column("imapUID") == imapUID)
                .fetchOne(db)
        }
    }

    public func message(headerMessageId: String) throws -> Message? {
        let trimmed = headerMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try db.dbWriter.read { db in
            try Message
                .filter(Column("headerMessageId") == trimmed)
                .fetchOne(db)
        }
    }

    public func messageStats(folderId: EntityID) throws -> (total: Int, unread: Int) {
        try db.dbWriter.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM message WHERE folderId = ?",
                arguments: [folderId]
            ) ?? 0
            let unread = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM message WHERE folderId = ? AND unread = 1",
                arguments: [folderId]
            ) ?? 0
            return (total, unread)
        }
    }

    public func observeMessages(threadId: EntityID) -> AnyPublisher<[Message], Error> {
        ValueObservation
            .tracking { db in
                try Message
                    .filter(Column("threadId") == threadId)
                    .order(Column("date").asc)
                    .fetchAll(db)
            }
            .publisher(in: db.dbWriter)
            .eraseToAnyPublisher()
    }

    public func saveBody(_ body: MessageBody) throws {
        try db.dbWriter.write { db in
            try body.save(db)
            if var message = try Message.fetchOne(db, key: body.messageId) {
                message.bodyFetched = true
                try message.update(db)
            }
            try indexMessageSearch(db: db, messageId: body.messageId, bodyText: body.plainText ?? body.html ?? "")
        }
    }

    public func body(messageId: EntityID) throws -> MessageBody? {
        try db.dbWriter.read { db in
            try MessageBody.fetchOne(db, key: messageId)
        }
    }

    // MARK: - Attachments

    public func upsertAttachment(_ file: AttachmentFile) throws {
        try db.dbWriter.write { db in
            try file.save(db)
        }
    }

    public func attachments(messageId: EntityID) throws -> [AttachmentFile] {
        try db.dbWriter.read { db in
            try AttachmentFile
                .filter(Column("messageId") == messageId)
                .fetchAll(db)
        }
    }

    public func deleteAttachments(messageId: EntityID) throws {
        try db.dbWriter.write { db in
            let existing = try AttachmentFile
                .filter(Column("messageId") == messageId)
                .fetchAll(db)
            for file in existing {
                if let path = file.localPath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            _ = try AttachmentFile
                .filter(Column("messageId") == messageId)
                .deleteAll(db)
        }
    }

    // MARK: - Tasks

    public func enqueue(_ task: MailTask) throws {
        try db.dbWriter.write { db in
            try task.save(db)
        }
    }

    public func pendingTasks(accountId: EntityID) throws -> [MailTask] {
        try db.dbWriter.read { db in
            try MailTask
                .filter(Column("accountId") == accountId && Column("status") == MailTaskStatus.local)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func updateTask(_ task: MailTask) throws {
        try db.dbWriter.write { db in
            try task.update(db)
        }
    }

    // MARK: - Search

    public func searchThreads(query: String, limit: Int = 50) throws -> [MailThread] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) else { return [] }

        return try db.dbWriter.read { db in
            let sql = """
            SELECT thread.* FROM thread
            JOIN threadSearch ON threadSearch.rowid = thread.rowid
            WHERE threadSearch MATCH ?
            ORDER BY rank
            LIMIT ?
            """
            return try MailThread.fetchAll(db, sql: sql, arguments: [pattern, limit])
        }
    }

    public func searchMessages(query: String, limit: Int = 50) throws -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pattern = FTS5Pattern(matchingAllTokensIn: trimmed) else { return [] }

        return try db.dbWriter.read { db in
            let sql = """
            SELECT message.* FROM message
            JOIN messageSearch ON messageSearch.messageId = message.id
            WHERE messageSearch MATCH ?
            LIMIT ?
            """
            return try Message.fetchAll(db, sql: sql, arguments: [pattern, limit])
        }
    }

    private func indexMessageSearch(db: Database, messageId: EntityID, bodyText: String) throws {
        guard let message = try Message.fetchOne(db, key: messageId) else { return }
        let fromText = message.from.map(\.displayString).joined(separator: " ")
        let toText = message.to.map(\.displayString).joined(separator: " ")
        try db.execute(sql: "DELETE FROM messageSearch WHERE messageId = ?", arguments: [messageId])
        try db.execute(
            sql: """
            INSERT INTO messageSearch(messageId, subject, fromText, toText, bodyText)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [messageId, message.subject, fromText, toText, bodyText]
        )
    }
}

/// Join table helper for thread ↔ folder.
struct ThreadFolder: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "threadFolder"
    var threadId: EntityID
    var folderId: EntityID
}
