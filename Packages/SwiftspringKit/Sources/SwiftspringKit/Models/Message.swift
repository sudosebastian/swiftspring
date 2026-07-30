import Foundation

public struct Thread: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var accountId: EntityID
    public var subject: String
    public var snippet: String
    public var unread: Bool
    public var starred: Bool
    public var participants: [EmailAddress]
    public var folderIds: [EntityID]
    public var labelIds: [EntityID]
    public var attachmentCount: Int
    public var messageCount: Int
    public var firstMessageAt: Date
    public var lastMessageReceivedAt: Date
    public var lastMessageSentAt: Date?
    public var inAllMail: Bool

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        subject: String,
        snippet: String = "",
        unread: Bool = false,
        starred: Bool = false,
        participants: [EmailAddress] = [],
        folderIds: [EntityID] = [],
        labelIds: [EntityID] = [],
        attachmentCount: Int = 0,
        messageCount: Int = 0,
        firstMessageAt: Date = Date(),
        lastMessageReceivedAt: Date = Date(),
        lastMessageSentAt: Date? = nil,
        inAllMail: Bool = true
    ) {
        self.id = id
        self.accountId = accountId
        self.subject = subject
        self.snippet = snippet
        self.unread = unread
        self.starred = starred
        self.participants = participants
        self.folderIds = folderIds
        self.labelIds = labelIds
        self.attachmentCount = attachmentCount
        self.messageCount = messageCount
        self.firstMessageAt = firstMessageAt
        self.lastMessageReceivedAt = lastMessageReceivedAt
        self.lastMessageSentAt = lastMessageSentAt
        self.inAllMail = inAllMail
    }
}

public struct Message: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var accountId: EntityID
    public var threadId: EntityID
    public var folderId: EntityID?
    public var imapUID: Int64?
    public var headerMessageId: String?
    public var replyToHeaderMessageId: String?
    public var subject: String
    public var snippet: String
    public var from: [EmailAddress]
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var replyTo: [EmailAddress]
    public var date: Date
    public var unread: Bool
    public var starred: Bool
    public var draft: Bool
    public var pristine: Bool
    public var hasAttachments: Bool
    public var bodyFetched: Bool

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        threadId: EntityID,
        folderId: EntityID? = nil,
        imapUID: Int64? = nil,
        headerMessageId: String? = nil,
        replyToHeaderMessageId: String? = nil,
        subject: String,
        snippet: String = "",
        from: [EmailAddress] = [],
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        replyTo: [EmailAddress] = [],
        date: Date = Date(),
        unread: Bool = false,
        starred: Bool = false,
        draft: Bool = false,
        pristine: Bool = true,
        hasAttachments: Bool = false,
        bodyFetched: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.threadId = threadId
        self.folderId = folderId
        self.imapUID = imapUID
        self.headerMessageId = headerMessageId
        self.replyToHeaderMessageId = replyToHeaderMessageId
        self.subject = subject
        self.snippet = snippet
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.date = date
        self.unread = unread
        self.starred = starred
        self.draft = draft
        self.pristine = pristine
        self.hasAttachments = hasAttachments
        self.bodyFetched = bodyFetched
    }
}

public struct MessageBody: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID { messageId }
    public var messageId: EntityID
    public var html: String?
    public var plainText: String?

    public init(messageId: EntityID, html: String? = nil, plainText: String? = nil) {
        self.messageId = messageId
        self.html = html
        self.plainText = plainText
    }
}

public struct AttachmentFile: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var messageId: EntityID
    public var accountId: EntityID
    public var filename: String
    public var contentType: String
    public var size: Int64
    public var contentId: String?
    public var isInline: Bool
    public var localPath: String?

    public init(
        id: EntityID = EntityID(),
        messageId: EntityID,
        accountId: EntityID,
        filename: String,
        contentType: String = "application/octet-stream",
        size: Int64 = 0,
        contentId: String? = nil,
        isInline: Bool = false,
        localPath: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.accountId = accountId
        self.filename = filename
        self.contentType = contentType
        self.size = size
        self.contentId = contentId
        self.isInline = isInline
        self.localPath = localPath
    }
}
