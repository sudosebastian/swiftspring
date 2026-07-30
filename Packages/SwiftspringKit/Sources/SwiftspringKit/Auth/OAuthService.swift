import Foundation

public enum OAuthProvider: String, Sendable {
    case google
    case microsoft
}

public struct OAuthConfiguration: Sendable {
    public var clientId: String
    public var redirectURI: String
    public var scopes: [String]
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL

    public init(
        clientId: String,
        redirectURI: String,
        scopes: [String],
        authorizationEndpoint: URL,
        tokenEndpoint: URL
    ) {
        self.clientId = clientId
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    public static func google(clientId: String, redirectURI: String = "swiftspring://oauth/google") -> OAuthConfiguration {
        OAuthConfiguration(
            clientId: clientId,
            redirectURI: redirectURI,
            scopes: [
                "https://mail.google.com/",
                "email",
                "profile",
                "openid",
            ],
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )
    }

    public static func microsoft(clientId: String, redirectURI: String = "swiftspring://oauth/microsoft") -> OAuthConfiguration {
        OAuthConfiguration(
            clientId: clientId,
            redirectURI: redirectURI,
            scopes: [
                "offline_access",
                "https://outlook.office.com/IMAP.AccessAsUser.All",
                "https://outlook.office.com/SMTP.Send",
                "openid",
                "email",
                "profile",
            ],
            authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
        )
    }
}

public struct OAuthTokenResponse: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresIn: Int?
    public var tokenType: String?
    public var idToken: String?
    public var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case idToken = "id_token"
        case scope
    }
}

public struct OAuthUserProfile: Sendable, Equatable {
    public var email: String
    public var name: String?

    public init(email: String, name: String? = nil) {
        self.email = email
        self.name = name
    }
}

public enum OAuthError: Error, LocalizedError, Sendable {
    case invalidAuthorizationURL
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)
    case profileFetchFailed

    public var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL: return "Could not build OAuth authorization URL."
        case .missingCode: return "OAuth callback did not include an authorization code."
        case .stateMismatch: return "OAuth callback state did not match the authorization request."
        case .tokenExchangeFailed(let message): return "Token exchange failed: \(message)"
        case .profileFetchFailed: return "Could not load the user profile."
        }
    }
}

public struct OAuthService: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func authorizationURL(config: OAuthConfiguration, state: String = UUID().uuidString) throws -> URL {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        guard let url = components?.url else {
            throw OAuthError.invalidAuthorizationURL
        }
        return url
    }

    public func exchangeCode(_ code: String, config: OAuthConfiguration) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": config.clientId,
            "code": code,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed(message)
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    public func refreshAccessToken(refreshToken: String, config: OAuthConfiguration) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": config.clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown"
            throw OAuthError.tokenExchangeFailed(message)
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    public func fetchGoogleProfile(accessToken: String) async throws -> OAuthUserProfile {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.profileFetchFailed
        }
        struct Payload: Decodable { let email: String; let name: String? }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return OAuthUserProfile(email: payload.email, name: payload.name)
    }

    public func fetchMicrosoftProfile(accessToken: String) async throws -> OAuthUserProfile {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthError.profileFetchFailed
        }
        struct Payload: Decodable {
            let mail: String?
            let userPrincipalName: String?
            let displayName: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let email = payload.mail ?? payload.userPrincipalName else {
            throw OAuthError.profileFetchFailed
        }
        return OAuthUserProfile(email: email, name: payload.displayName)
    }
}
