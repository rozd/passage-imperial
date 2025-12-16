import Vapor
import Passage
import ImperialCore
import ImperialGitHub
import ImperialGoogle

public struct ImperialFederatedLoginService: Passage.FederatedLoginService {

    public let services: [FederatedProvider.Name: any FederatedService.Type]

    public init(
        services: [FederatedProvider.Name: any FederatedService.Type]
    ) {
        self.services = services
    }

    // MARK: - Register with onSignIn callback (fetches user info)

    public func register(
        router: any RoutesBuilder,
        origin: URL,
        group: [PathComponent],
        config: Passage.Configuration.FederatedLogin,
        onSignIn: @escaping @Sendable (
            _ request: Request,
            _ identity: FederatedIdentity,
        ) async throws -> some AsyncResponseEncodable
    ) throws {
        for (name, service) in services {
            guard let cfg = config.providers.first(where: { $0.provider.name == name }) else {
                throw PassageError.unexpected(
                    message: "Provider for name \(name) is not configured"
                )
            }

            let loginPath = group + config.loginPath(for: cfg)
            let callbackPath = group + config.callbackPath(for: cfg)
            let loginURL = origin.appending(path: loginPath.string)
            let callbackURL = origin.appending(path: callbackPath.string)

            try router.oAuth(
                from: service,
                authenticate: loginURL.absoluteString,
                callback: callbackURL.absoluteString,
                scope: cfg.provider.scope,
            ) { (request: Request, accessToken: String) in

                // Fetch user info from the OAuth provider
                let identity = try await self.fetchIdentity(
                    from: service,
                    using: accessToken,
                    for: cfg.provider,
                    client: request.client
                )

                return try await onSignIn(request, identity)
            }
        }
    }
}

// MARK: - Fetch Identity

extension ImperialFederatedLoginService {

    func fetchIdentity(
        from service: any FederatedService.Type,
        using accessToken: String,
        for provider: FederatedProvider,
        client: Client
    ) async throws -> FederatedIdentity {
        switch service {
        case is GitHub.Type:
            return try await fetchGitHubUser(
                using: accessToken,
                for: provider,
                client: client
            )
        case is Google.Type:
            return try await fetchGoogleUser(
                using: accessToken,
                for: provider,
                client: client
            )
        default:
            throw PassageError.unexpected(message: "Unsupported OAuth provider: \(service)")
        }
    }

}

// MARK: Fetch Google Identity

extension ImperialFederatedLoginService {

    func fetchGoogleUser(
        using accessToken: String,
        for provider: FederatedProvider,
        client: Client
    ) async throws -> FederatedIdentity {
        let response = try await client.get(
            URI(string: "https://www.googleapis.com/oauth2/v2/userinfo"),
            headers: [
                "Authorization": "Bearer \(accessToken)"
            ]
        )

        guard response.status == .ok else {
            throw PassageError.unexpected(
                message: "Google API returned status \(response.status)"
            )
        }

        let user = try response.content.decode(GoogleUser.self)

        return .init(
            identifier: .federated(provider.name, userId: user.id),
            provider: provider.name,
            verifiedEmails: user.isEmailVerified == true ? [user.email].compactMap { $0 } : [],
            verifiedPhoneNumbers: [],
            displayName: user.name,
            profilePictureURL: user.picture
        )
    }

}

fileprivate  struct GoogleUser: Content {
    enum CodingKeys: String, CodingKey {
        case id, email, phone, name, picture
        case isEmailVerified = "verified_email"
    }

    let id: String
    let email: String?
    let phone: String?
    let name: String?
    let picture: String?
    let isEmailVerified: Bool?
}

// MARK: Fetch GitHub Identity

extension ImperialFederatedLoginService {

    func fetchGitHubUser(
        using accessToken: String,
        for provider: FederatedProvider,
        client: Client
    ) async throws -> FederatedIdentity {

        let response = try await client.get(
            URI(string: "https://api.github.com/user"),
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Accept": "application/vnd.github+json",
                "User-Agent": "Passage-Imperial"
            ]
        )

        guard response.status == .ok else {
            throw PassageError.unexpected(
                message: "GitHub API returned status \(response.status)"
            )
        }

        let user = try response.content.decode(GitHubUser.self)

        let emailResponse = try await client.get(
            URI(string: "https://api.github.com/user/emails"),
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "Passage-Imperial"
            ]
        )

        let emails = emailResponse.status == .ok
            ? try emailResponse.content.decode([GitHubEmail].self)
            : []

        return .init(
            identifier: .federated(provider.name, userId: String(user.id)),
            provider: provider.name,
            verifiedEmails: emails.filter { $0.verified }.map { $0.email },
            verifiedPhoneNumbers: [],
            displayName: user.name,
            profilePictureURL: user.avatarURL
        )
    }

}

fileprivate struct GitHubUser: Content {
    enum CodingKeys: String, CodingKey {
        case id, login, name
        case avatarURL = "avatar_url"
    }

    let id: Int
    let name: String?
    var avatarURL: String?
    let login: String
}

fileprivate struct GitHubEmail: Content {
    let email: String
    let primary: Bool
    let verified: Bool
}
