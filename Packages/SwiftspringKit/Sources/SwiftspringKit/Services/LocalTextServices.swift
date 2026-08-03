import Foundation
import GRDB

public enum LocalTextServiceError: Error, LocalizedError, Sendable {
    case notConfigured(String)
    case invalidLocalURL
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let name): return "Configure a local \(name) service first."
        case .invalidLocalURL: return "Text services must use a localhost URL."
        case .invalidResponse: return "The local text service returned an invalid response."
        }
    }
}

/// Endpoints for services that run on the user's own machine. The expected
/// defaults are LanguageTool's `/v2/check` API and LibreTranslate's `/translate`
/// API, both of which can be self-hosted without sending text to Mailspring.
public struct LocalTextServiceConfiguration: Identifiable, Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "localTextService"
    public static let singletonID = EntityID(rawValue: "local-text-services")

    public var id: EntityID
    public var languageToolURL: String?
    public var translationURL: String?
    public var updatedAt: Date

    public init(
        id: EntityID = Self.singletonID,
        languageToolURL: String? = nil,
        translationURL: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.languageToolURL = languageToolURL
        self.translationURL = translationURL
        self.updatedAt = updatedAt
    }
}

public struct LocalTextServiceSettings: Sendable {
    public let repository: MailRepository

    public init(repository: MailRepository) {
        self.repository = repository
    }

    public func current() throws -> LocalTextServiceConfiguration? {
        try repository.db.dbWriter.read { db in
            try LocalTextServiceConfiguration.fetchOne(db, key: LocalTextServiceConfiguration.singletonID)
        }
    }

    public func save(_ settings: LocalTextServiceConfiguration) throws {
        for endpoint in [settings.languageToolURL, settings.translationURL].compactMap({ $0 }) {
            guard Self.isLoopbackURL(endpoint) else { throw LocalTextServiceError.invalidLocalURL }
        }
        var settings = settings
        settings.id = LocalTextServiceConfiguration.singletonID
        settings.updatedAt = Date()
        try repository.db.dbWriter.write { db in
            try settings.save(db)
        }
    }

    private static func isLoopbackURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased() else { return false }
        return host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }
}

public struct GrammarIssue: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(offset)-\(length)-\(message)" }
    public var message: String
    public var offset: Int
    public var length: Int
    public var replacements: [String]

    public init(message: String, offset: Int, length: Int, replacements: [String]) {
        self.message = message
        self.offset = offset
        self.length = length
        self.replacements = replacements
    }

    private enum CodingKeys: String, CodingKey { case message, offset, length, replacements }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        offset = try container.decode(Int.self, forKey: .offset)
        length = try container.decode(Int.self, forKey: .length)
        let replacementValues = try container.decodeIfPresent([Replacement].self, forKey: .replacements) ?? []
        replacements = replacementValues.map(\.value)
    }

    private struct Replacement: Codable { var value: String }
}

public struct LocalGrammarService: Sendable {
    private let settings: LocalTextServiceSettings
    private let session: URLSession

    public init(settings: LocalTextServiceSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    public func check(_ text: String, language: String = "auto") async throws -> [GrammarIssue] {
        guard let endpoint = try settings.current()?.languageToolURL,
              let url = URL(string: endpoint) else {
            throw LocalTextServiceError.notConfigured("LanguageTool")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData(["text": text, "language": language]).data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalTextServiceError.invalidResponse
        }
        struct Response: Decodable { let matches: [GrammarIssue] }
        return try JSONDecoder().decode(Response.self, from: data).matches
    }
}

public struct LocalTranslationService: Sendable {
    private let settings: LocalTextServiceSettings
    private let session: URLSession

    public init(settings: LocalTextServiceSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    /// Uses the LibreTranslate-compatible JSON shape from a local endpoint.
    public func translate(_ text: String, from sourceLanguage: String = "auto", to targetLanguage: String) async throws -> String {
        guard let endpoint = try settings.current()?.translationURL,
              let url = URL(string: endpoint) else {
            throw LocalTextServiceError.notConfigured("translation")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "q": text,
            "source": sourceLanguage,
            "target": targetLanguage,
            "format": "text",
        ])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalTextServiceError.invalidResponse
        }
        struct Response: Decodable { let translatedText: String }
        return try JSONDecoder().decode(Response.self, from: data).translatedText
    }
}

private func formData(_ values: [String: String]) -> String {
    values.map { key, value in
        "\(key.urlQueryEncoded)=\(value.urlQueryEncoded)"
    }
    .joined(separator: "&")
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
