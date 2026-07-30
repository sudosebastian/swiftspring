import Foundation

public enum ProviderPresets {
    public static func settings(for provider: MailProvider, email: String) -> (imap: ServerSettings, smtp: ServerSettings) {
        let username = email
        switch provider {
        case .gmail:
            return (
                ServerSettings(host: "imap.gmail.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "smtp.gmail.com", port: 465, username: username, security: .sslTLS)
            )
        case .office365, .outlook:
            return (
                ServerSettings(host: "outlook.office365.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "smtp.office365.com", port: 587, username: username, security: .startTLS)
            )
        case .icloud:
            return (
                ServerSettings(host: "imap.mail.me.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "smtp.mail.me.com", port: 587, username: username, security: .startTLS)
            )
        case .fastmail:
            return (
                ServerSettings(host: "imap.fastmail.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "smtp.fastmail.com", port: 465, username: username, security: .sslTLS)
            )
        case .yahoo:
            return (
                ServerSettings(host: "imap.mail.yahoo.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "smtp.mail.yahoo.com", port: 465, username: username, security: .sslTLS)
            )
        case .gmx:
            return (
                ServerSettings(host: "imap.gmx.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "mail.gmx.com", port: 587, username: username, security: .startTLS)
            )
        case .yandex:
            return (
                ServerSettings(host: "imap.yandex.com", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "smtp.yandex.com", port: 465, username: username, security: .sslTLS)
            )
        case .imap:
            return (
                ServerSettings(host: "", port: 993, username: username, security: .sslTLS),
                ServerSettings(host: "", port: 587, username: username, security: .startTLS)
            )
        }
    }

    public static func mapRole(path: String, flags: [String]) -> FolderRole {
        let lowered = path.lowercased()
        let flagSet = Set(flags.map { $0.lowercased() })
        if flagSet.contains("\\inbox") || lowered == "inbox" { return .inbox }
        if flagSet.contains("\\sent") || lowered.contains("sent") { return .sent }
        if flagSet.contains("\\drafts") || lowered.contains("draft") { return .drafts }
        if flagSet.contains("\\trash") || lowered.contains("trash") || lowered.contains("deleted") { return .trash }
        if flagSet.contains("\\junk") || lowered.contains("spam") || lowered.contains("junk") { return .spam }
        if flagSet.contains("\\archive") || lowered.contains("archive") || lowered == "[gmail]/all mail" { return .archive }
        if lowered.contains("all mail") { return .all }
        if lowered.contains("starred") || lowered.contains("flagged") { return .starred }
        if lowered.contains("important") { return .important }
        return .none
    }
}
