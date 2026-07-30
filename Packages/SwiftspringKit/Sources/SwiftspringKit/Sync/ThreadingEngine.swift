import Foundation

/// Groups messages into threads using References / In-Reply-To / subject heuristics.
public enum ThreadingEngine {
    public static func threadKey(for header: RemoteMessageHeader) -> String {
        if let firstRef = header.references.first, !firstRef.isEmpty {
            return normalize(firstRef)
        }
        if let messageId = header.headerMessageId, !messageId.isEmpty,
           header.references.isEmpty {
            // Root message — key by its own Message-ID.
            return normalize(messageId)
        }
        let subject = normalizedSubject(header.subject)
        let participants = (header.from + header.to)
            .map(\.email)
            .sorted()
            .joined(separator: ",")
        return "subj:\(subject)|\(participants)"
    }

    public static func normalizedSubject(_ subject: String) -> String {
        var value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["re:", "fw:", "fwd:", "aw:", "sv:", "antw:"]
        var changed = true
        while changed {
            changed = false
            let lower = value.lowercased()
            for prefix in prefixes where lower.hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        return value.lowercased()
    }

    private static func normalize(_ messageId: String) -> String {
        messageId
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .lowercased()
    }
}
