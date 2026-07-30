import Foundation
import Combine

@MainActor
public final class ComposeService: ObservableObject {
    @Published public var draft: Message?
    @Published public var htmlBody: String = ""
    @Published public var plainBody: String = ""
    @Published public var attachmentURLs: [URL] = []
    @Published public var isSending = false
    @Published public var undoSecondsRemaining: Int = 0

    public let repository: MailRepository
    public let syncEngine: SyncEngine

    public init(repository: MailRepository, syncEngine: SyncEngine) {
        self.repository = repository
        self.syncEngine = syncEngine
    }

    public func newDraft(from account: Account, to: [EmailAddress] = [], subject: String = "") throws -> Message {
        let draftsFolder = try repository.folder(accountId: account.id, role: .drafts)
        let thread = Thread(
            accountId: account.id,
            subject: subject.isEmpty ? "(no subject)" : subject,
            folderIds: draftsFolder.map { [$0.id] } ?? []
        )
        try repository.upsertThread(thread)
        let message = Message(
            accountId: account.id,
            threadId: thread.id,
            folderId: draftsFolder?.id,
            subject: subject,
            from: [EmailAddress(name: account.name, email: account.emailAddress)],
            to: to,
            draft: true,
            pristine: true
        )
        try repository.upsertMessage(message)
        try repository.saveBody(MessageBody(messageId: message.id, html: "", plainText: ""))
        draft = message
        htmlBody = ""
        plainBody = ""
        attachmentURLs = []
        return message
    }

    public func reply(to message: Message, account: Account, replyAll: Bool) throws -> Message {
        let to = message.from
        var cc: [EmailAddress] = []
        if replyAll {
            cc = (message.to + message.cc).filter { $0.email != account.emailAddress }
        }
        let subject = message.subject.lowercased().hasPrefix("re:")
            ? message.subject
            : "Re: \(message.subject)"
        var draft = try newDraft(from: account, to: to, subject: subject)
        draft.cc = cc
        draft.replyToHeaderMessageId = message.headerMessageId
        draft.pristine = false
        try repository.upsertMessage(draft)
        let quoted = try repository.body(messageId: message.id)
        let quoteHTML = """
        <br><br><blockquote>
        On \(message.date.formatted()), \(message.from.first?.displayString ?? "") wrote:<br>
        \(quoted?.html ?? quoted?.plainText ?? "")
        </blockquote>
        """
        htmlBody = quoteHTML
        plainBody = "\n\n> \(quoted?.plainText ?? "")"
        try repository.saveBody(MessageBody(messageId: draft.id, html: htmlBody, plainText: plainBody))
        self.draft = draft
        return draft
    }

    public func forward(message: Message, account: Account) throws -> Message {
        let subject = message.subject.lowercased().hasPrefix("fwd:")
            ? message.subject
            : "Fwd: \(message.subject)"
        let draft = try newDraft(from: account, subject: subject)
        let body = try repository.body(messageId: message.id)
        htmlBody = """
        <br><br>---------- Forwarded message ----------<br>
        \(body?.html ?? body?.plainText ?? "")
        """
        plainBody = "\n\n---------- Forwarded message ----------\n\(body?.plainText ?? "")"
        try repository.saveBody(MessageBody(messageId: draft.id, html: htmlBody, plainText: plainBody))
        self.draft = draft
        return draft
    }

    public func saveDraft() throws {
        guard var draft else { return }
        draft.subject = draft.subject
        draft.pristine = false
        draft.snippet = String(plainBody.prefix(140))
        try repository.upsertMessage(draft)
        try repository.saveBody(MessageBody(messageId: draft.id, html: htmlBody, plainText: plainBody))

        for url in attachmentURLs {
            let data = try Data(contentsOf: url)
            var file = AttachmentFile(
                messageId: draft.id,
                accountId: draft.accountId,
                filename: url.lastPathComponent,
                contentType: "application/octet-stream",
                size: Int64(data.count)
            )
            let dest = repository.db.attachmentsDirectory
                .appendingPathComponent(file.id.rawValue)
                .appendingPathExtension(url.pathExtension)
            try data.write(to: dest)
            file.localPath = dest.path
            try repository.upsertAttachment(file)
        }
        draft.hasAttachments = !attachmentURLs.isEmpty
        try repository.upsertMessage(draft)
        self.draft = draft
    }

    public func send(undoDelaySeconds: Int = 5) async throws {
        guard var draft else { return }
        try saveDraft()
        isSending = true
        undoSecondsRemaining = undoDelaySeconds
        defer {
            isSending = false
            undoSecondsRemaining = 0
        }

        let payload = SendDraftPayload(messageId: draft.id, undoDelaySeconds: 0)
        let task = MailTask(
            accountId: draft.accountId,
            kind: .sendDraft,
            payloadJSON: try MailTaskCodec.encode(payload)
        )
        try repository.enqueue(task)

        // Local countdown for undo UI; SMTP send runs immediately after.
        for remaining in stride(from: undoDelaySeconds, through: 1, by: -1) {
            undoSecondsRemaining = remaining
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        undoSecondsRemaining = 0
        try await syncEngine.processTasks(accountId: draft.accountId)
        draft.draft = false
        self.draft = nil
    }

    public func updateRecipients(to: [EmailAddress], cc: [EmailAddress] = [], bcc: [EmailAddress] = []) throws {
        guard var draft else { return }
        draft.to = to
        draft.cc = cc
        draft.bcc = bcc
        draft.pristine = false
        try repository.upsertMessage(draft)
        self.draft = draft
    }

    public func updateSubject(_ subject: String) throws {
        guard var draft else { return }
        draft.subject = subject
        draft.pristine = false
        try repository.upsertMessage(draft)
        self.draft = draft
    }
}
