import Foundation

/// Simple plain-text / HTML signatures stored per account.
public struct Signature: Identifiable, Codable, Sendable, Equatable {
    public var id: EntityID
    public var accountId: EntityID
    public var name: String
    public var bodyHTML: String
    public var isDefault: Bool

    public init(
        id: EntityID = EntityID(),
        accountId: EntityID,
        name: String,
        bodyHTML: String,
        isDefault: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.name = name
        self.bodyHTML = bodyHTML
        self.isDefault = isDefault
    }
}

public final class SignatureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var signatures: [Signature] = []
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("signatures.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Signature].self, from: data) {
            signatures = decoded
        }
    }

    public func all(accountId: EntityID) -> [Signature] {
        lock.lock(); defer { lock.unlock() }
        return signatures.filter { $0.accountId == accountId }
    }

    public func save(_ signature: Signature) throws {
        lock.lock()
        if let index = signatures.firstIndex(where: { $0.id == signature.id }) {
            signatures[index] = signature
        } else {
            signatures.append(signature)
        }
        if signature.isDefault {
            for i in signatures.indices where signatures[i].accountId == signature.accountId && signatures[i].id != signature.id {
                signatures[i].isDefault = false
            }
        }
        let snapshot = signatures
        lock.unlock()
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func defaultSignature(accountId: EntityID) -> Signature? {
        all(accountId: accountId).first(where: \.isDefault) ?? all(accountId: accountId).first
    }
}
