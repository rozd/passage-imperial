//
//  Imperial.swift
//  passten
//
//  Created by Max Rozdobudko on 11/30/25.
//

import Vapor
import ImperialCore
import ImperialGitHub
import ImperialGoogle

struct ImperialFederatedLoginService: Identity.FederatedLoginService {

    let services: [Identity.Configuration.FederatedLogin.Provider.Name: any FederatedService.Type]

    init(
        services: [Identity.Configuration.FederatedLogin.Provider.Name: any FederatedService.Type]
    ) {
        self.services = services
    }

    func register(
        router: any RoutesBuilder,
        origin: URL,
        group: [PathComponent],
        config: Identity.Configuration.FederatedLogin,
        completion: @escaping @Sendable (
            _ provider: Identity.Configuration.FederatedLogin.Provider,
            _ request: Request,
            _ payload: String
        ) async throws -> some AsyncResponseEncodable
    ) throws {
        for (name, service) in services {
            guard let provider = config.providers.first(where: { $0.name == name }) else {
                throw IdentityError.unexpected(
                    message: "Provider for name \(name) is not configured"
                )
            }

            let loginPath = group + config.loginPath(for: provider)
            let callbackPath = group + config.callbackPath(for: provider)
            let loginURL = origin.appending(path: loginPath.string)
            let callbackURL = origin.appending(path: callbackPath.string)

            try router.oAuth(
                from: service,
                authenticate: loginURL.absoluteString,
                callback: callbackURL.absoluteString,
                scope: provider.scope,
            ) { request, accessToken in
                try await completion(provider, request, accessToken)
            }
        }

    }
}
