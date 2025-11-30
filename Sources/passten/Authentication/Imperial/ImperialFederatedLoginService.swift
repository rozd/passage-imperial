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

    struct ProviderNameConverter: Sendable {
        let nameToServiceType: @Sendable (Identity.Configuration.FederatedLogin.Provider.Name) -> (any FederatedService.Type)?
        let serviceTypeToName: @Sendable (any FederatedService.Type) -> Identity.Configuration.FederatedLogin.Provider.Name?
    }

    let converter: ProviderNameConverter

    init(
        converter: ProviderNameConverter = .default,
    ) {
        self.converter = converter
    }

    func register(
        router: any RoutesBuilder,
        group: [PathComponent],
        config: Identity.Configuration.FederatedLogin,
        completion: @escaping @Sendable (
            _ provider: Identity.Configuration.FederatedLogin.Provider,
            _ request: Request,
            _ payload: String
        ) async throws -> some AsyncResponseEncodable
    ) throws {
        let grouped = group.isEmpty ? router : router.grouped(group)

        for provider in config.providers {
            guard let service = converter.nameToServiceType(provider.name) else {
                throw IdentityError.unexpected(
                    message: "Unsupported federated login provider name \(provider.name)"
                )
            }
            try grouped.oAuth(
                from: service,
                authenticate: config.loginPath(for: provider).string,
                callback: config.callbackPath(for: provider).string,
            ) { request, accessToken in
                try await completion(provider, request, accessToken)
            }
        }
    }
}

extension ImperialFederatedLoginService.ProviderNameConverter {

    static let `default`: Self = .init(
        nameToServiceType: { name in
            switch name {
            case .google:
                return Google.self
            case .github:
                return GitHub.self
            default:
                return nil
            }
        },
        serviceTypeToName: { serviceType in
            switch serviceType {
            case is GitHub.Type:
                return .github
            case is Google.Type:
                return .google
            default:
                fatalError("Unsupported service type \(serviceType)")
            }
        }
    )

}
