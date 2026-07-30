import Foundation
import GRDB

public enum DatabaseError: Error, LocalizedError, Sendable {
    case notOpen
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notOpen: return "Database is not open."
        case .migrationFailed(let message): return "Migration failed: \(message)"
        }
    }
}

public final class AppDatabase: Sendable {
    public let dbWriter: any DatabaseWriter
    public let attachmentsDirectory: URL

    public init(dbWriter: any DatabaseWriter, attachmentsDirectory: URL) throws {
        self.dbWriter = dbWriter
        self.attachmentsDirectory = attachmentsDirectory
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try migrator.migrate(dbWriter)
    }

    public static func open(in directory: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbURL = directory.appendingPathComponent("swiftspring.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        let attachments = directory.appendingPathComponent("Attachments", isDirectory: true)
        return try AppDatabase(dbWriter: pool, attachmentsDirectory: attachments)
    }

    public static func openInMemory() throws -> AppDatabase {
        let db = try DatabaseQueue()
        let attachments = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftspringAttachments-\(UUID().uuidString)", isDirectory: true)
        return try AppDatabase(dbWriter: db, attachmentsDirectory: attachments)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_schema") { db in
            try db.create(table: "account") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("emailAddress", .text).notNull().indexed()
                t.column("provider", .text).notNull()
                t.column("label", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("imapJSON", .text).notNull()
                t.column("smtpJSON", .text).notNull()
                t.column("aliasesJSON", .text).notNull().defaults(to: "[]")
                t.column("defaultAlias", .text)
                t.column("syncState", .text).notNull()
                t.column("syncErrorMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "folder") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                    .references("account", onDelete: .cascade)
                t.column("path", .text).notNull()
                t.column("name", .text).notNull()
                t.column("role", .text).notNull()
                t.column("delimiter", .text).notNull()
                t.column("uidValidity", .integer)
                t.column("uidNext", .integer)
                t.column("highestModSeq", .integer)
                t.column("totalCount", .integer).notNull().defaults(to: 0)
                t.column("unreadCount", .integer).notNull().defaults(to: 0)
                t.uniqueKey(["accountId", "path"])
            }

            try db.create(table: "label") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                    .references("account", onDelete: .cascade)
                t.column("path", .text).notNull()
                t.column("name", .text).notNull()
                t.column("role", .text).notNull()
                t.uniqueKey(["accountId", "path"])
            }

            try db.create(table: "thread") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                    .references("account", onDelete: .cascade)
                t.column("subject", .text).notNull().indexed()
                t.column("snippet", .text).notNull()
                t.column("unread", .boolean).notNull().indexed()
                t.column("starred", .boolean).notNull().indexed()
                t.column("participantsJSON", .text).notNull()
                t.column("folderIdsJSON", .text).notNull()
                t.column("labelIdsJSON", .text).notNull()
                t.column("attachmentCount", .integer).notNull()
                t.column("messageCount", .integer).notNull()
                t.column("firstMessageAt", .datetime).notNull()
                t.column("lastMessageReceivedAt", .datetime).notNull().indexed()
                t.column("lastMessageSentAt", .datetime)
                t.column("inAllMail", .boolean).notNull()
            }

            try db.create(table: "message") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                    .references("account", onDelete: .cascade)
                t.column("threadId", .text).notNull().indexed()
                    .references("thread", onDelete: .cascade)
                t.column("folderId", .text)
                t.column("imapUID", .integer)
                t.column("headerMessageId", .text).indexed()
                t.column("replyToHeaderMessageId", .text)
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("fromJSON", .text).notNull()
                t.column("toJSON", .text).notNull()
                t.column("ccJSON", .text).notNull()
                t.column("bccJSON", .text).notNull()
                t.column("replyToJSON", .text).notNull()
                t.column("date", .datetime).notNull().indexed()
                t.column("unread", .boolean).notNull()
                t.column("starred", .boolean).notNull()
                t.column("draft", .boolean).notNull().indexed()
                t.column("pristine", .boolean).notNull()
                t.column("hasAttachments", .boolean).notNull()
                t.column("bodyFetched", .boolean).notNull()
            }

            try db.create(table: "messageBody") { t in
                t.column("messageId", .text).primaryKey()
                    .references("message", onDelete: .cascade)
                t.column("html", .text)
                t.column("plainText", .text)
            }

            try db.create(table: "attachment") { t in
                t.column("id", .text).primaryKey()
                t.column("messageId", .text).notNull().indexed()
                    .references("message", onDelete: .cascade)
                t.column("accountId", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("contentType", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("contentId", .text)
                t.column("isInline", .boolean).notNull()
                t.column("localPath", .text)
            }

            try db.create(table: "mailTask") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                    .references("account", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("payloadJSON", .text).notNull()
                t.column("errorMessage", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "threadFolder") { t in
                t.column("threadId", .text).notNull()
                    .references("thread", onDelete: .cascade)
                t.column("folderId", .text).notNull()
                    .references("folder", onDelete: .cascade)
                t.primaryKey(["threadId", "folderId"])
            }

            try db.create(virtualTable: "threadSearch", using: FTS5()) { t in
                t.synchronize(withTable: "thread")
                t.tokenizer = .unicode61()
                t.column("subject")
                t.column("snippet")
                t.column("participantsJSON")
            }

            try db.create(virtualTable: "messageSearch", using: FTS5()) { t in
                t.tokenizer = .unicode61()
                t.column("messageId")
                t.column("subject")
                t.column("fromText")
                t.column("toText")
                t.column("bodyText")
            }
        }

        migrator.registerMigration("v2_contacts_calendar_hooks") { db in
            try db.create(table: "contact") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text).notNull().indexed()
                t.column("name", .text)
                t.column("email", .text).notNull().indexed()
                t.column("source", .text).notNull().defaults(to: "local")
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "snooze") { t in
                t.column("id", .text).primaryKey()
                t.column("threadId", .text).notNull().indexed()
                t.column("accountId", .text).notNull()
                t.column("wakeAt", .datetime).notNull().indexed()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "mailRule") { t in
                t.column("id", .text).primaryKey()
                t.column("accountId", .text)
                t.column("name", .text).notNull()
                t.column("enabled", .boolean).notNull()
                t.column("conditionJSON", .text).notNull()
                t.column("actionJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        return migrator
    }
}
