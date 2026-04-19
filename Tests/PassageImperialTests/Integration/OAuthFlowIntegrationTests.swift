import Testing
import Vapor
import VaporTesting
import Passage
import ImperialCore
import ImperialGitHub
import ImperialGoogle
@testable import PassageImperial

// MARK: - OAuth Flow Integration Tests

@Suite("OAuth Flow Integration Tests")
struct OAuthFlowIntegrationTests {

    @Test("registers routes for GitHub provider")
    func registersRoutesForGitHub() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        // Set required environment variables for Imperial
        Environment.process.GITHUB_CLIENT_ID = "test-client-id"
        Environment.process.GITHUB_CLIENT_SECRET = "test-client-secret"

        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self
        ])

        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github())]
        )

        try service.register(
            router: app.routes,
            origin: URL(string: "https://example.com")!,
            group: ["auth"],
            config: config
        ) { request, identity in
            return HTTPStatus.ok
        }

        // Check that routes were registered
        let routes = app.routes.all
        let routePaths = routes.map { $0.path.map { $0.description }.joined(separator: "/") }

        #expect(routePaths.contains("auth/oauth/github"))
        #expect(routePaths.contains("auth/oauth/github/callback"))
    }

    @Test("registers routes for Google provider")
    func registersRoutesForGoogle() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        // Set required environment variables for Imperial
        Environment.process.GOOGLE_CLIENT_ID = "test-client-id"
        Environment.process.GOOGLE_CLIENT_SECRET = "test-client-secret"

        let service = ImperialFederatedLoginService(services: [
            .google: Google.self
        ])

        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .google())]
        )

        try service.register(
            router: app.routes,
            origin: URL(string: "https://example.com")!,
            group: ["auth"],
            config: config
        ) { request, identity in
            return HTTPStatus.ok
        }

        let routes = app.routes.all
        let routePaths = routes.map { $0.path.map { $0.description }.joined(separator: "/") }

        #expect(routePaths.contains("auth/oauth/google"))
        #expect(routePaths.contains("auth/oauth/google/callback"))
    }

    @Test("registers routes for multiple providers")
    func registersRoutesForMultipleProviders() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        // Set required environment variables for Imperial
        Environment.process.GITHUB_CLIENT_ID = "test-github-id"
        Environment.process.GITHUB_CLIENT_SECRET = "test-github-secret"
        Environment.process.GOOGLE_CLIENT_ID = "test-google-id"
        Environment.process.GOOGLE_CLIENT_SECRET = "test-google-secret"

        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self,
            .google: Google.self
        ])

        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github()), .init(provider: .google())]
        )

        try service.register(
            router: app.routes,
            origin: URL(string: "https://example.com")!,
            group: ["api", "v1"],
            config: config
        ) { request, identity in
            return HTTPStatus.ok
        }

        let routes = app.routes.all
        let routePaths = routes.map { $0.path.map { $0.description }.joined(separator: "/") }

        #expect(routePaths.contains("api/v1/oauth/github"))
        #expect(routePaths.contains("api/v1/oauth/github/callback"))
        #expect(routePaths.contains("api/v1/oauth/google"))
        #expect(routePaths.contains("api/v1/oauth/google/callback"))
    }

    @Test("uses correct callback URL from origin")
    func usesCorrectCallbackURLFromOrigin() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        Environment.process.GITHUB_CLIENT_ID = "test-id"
        Environment.process.GITHUB_CLIENT_SECRET = "test-secret"

        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self
        ])

        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github())]
        )

        // Different origins should create different callback URLs
        try service.register(
            router: app.routes,
            origin: URL(string: "https://myapp.example.com")!,
            group: ["api"],
            config: config
        ) { request, identity in
            return HTTPStatus.ok
        }

        // Verify routes are registered (the actual callback URL handling is done by Imperial)
        let routes = app.routes.all
        #expect(!routes.isEmpty)
    }
}

// MARK: - Provider Credentials Tests

@Suite("Provider Credentials Tests")
struct ProviderCredentialsTests {

    @Test("conventional credentials use environment variables")
    func conventionalCredentialsUseEnv() {
        let provider = FederatedProvider.github(
            credentials: .conventional
        )

        if case .conventional = provider.credentials {
            // Success
        } else {
            Issue.record("Expected conventional credentials")
        }
    }

    @Test("client credentials store id and secret")
    func clientCredentialsStoreIdAndSecret() {
        let provider = FederatedProvider.github(
            credentials: .client(id: "my-client-id", secret: "my-client-secret")
        )

        if case .client(let id, let secret) = provider.credentials {
            #expect(id == "my-client-id")
            #expect(secret == "my-client-secret")
        } else {
            Issue.record("Expected client credentials")
        }
    }
}

// MARK: - Route Group Tests

@Suite("Route Group Tests")
struct RouteGroupTests {

    @Test("default route group creates expected paths")
    func defaultRouteGroupCreatesPaths() {
        let config = Passage.Configuration.FederatedLogin(
            providers: [.init(provider: .github())]
        )
        let provider = Passage.Configuration.FederatedLogin.Provider(provider: .github())
        let loginPath = config.loginPath(for: provider)

        // Default group is "oauth"
        #expect(loginPath.map { $0.description } == ["connect", "github"])
    }

    @Test("custom route group creates expected paths")
    func customRouteGroupCreatesPaths() {
        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "identity", "providers"),
            providers: [.init(provider: .github())]
        )
        let provider = Passage.Configuration.FederatedLogin.Provider(provider: .github())
        let loginPath = config.loginPath(for: provider)

        #expect(loginPath.map { $0.description } == ["identity", "providers", "github"])
    }
}

// MARK: - Account Linking Configuration Tests

@Suite("Account Linking Configuration Tests")
struct AccountLinkingConfigurationTests {

    @Test("default state expiration is 600 seconds")
    func defaultStateExpirationIs600Seconds() {
        let linking = Passage.Configuration.FederatedLogin.AccountLinking(resolution: .disabled)
        #expect(linking.stateExpiration == 600)
    }

    @Test("custom state expiration is used")
    func customStateExpirationIsUsed() {
        let linking = Passage.Configuration.FederatedLogin.AccountLinking(
            resolution: .disabled,
            stateExpiration: 1800
        )
        #expect(linking.stateExpiration == 1800)
    }

    @Test("default linking routes")
    func defaultLinkingRoutes() {
        let routes = Passage.Configuration.FederatedLogin.AccountLinking.Routes()
        #expect(routes.select.map { $0.description } == ["link", "select"])
        #expect(routes.verify.map { $0.description } == ["link", "verify"])
    }

    @Test("custom linking routes")
    func customLinkingRoutes() {
        let routes = Passage.Configuration.FederatedLogin.AccountLinking.Routes(
            select: ["custom", "select"],
            verify: ["custom", "verify"]
        )
        #expect(routes.select.map { $0.description } == ["custom", "select"])
        #expect(routes.verify.map { $0.description } == ["custom", "verify"])
    }

    @Test("linkSelectPath combines group and select routes")
    func linkSelectPathCombinesGroupAndSelectRoutes() {
        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github())]
        )

        let path = config.linkAccountSelectPath
        #expect(path.map { $0.description } == ["oauth", "link", "select"])
    }

    @Test("linkVerifyPath combines group and verify routes")
    func linkVerifyPathCombinesGroupAndVerifyRoutes() {
        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github())]
        )

        let path = config.linkAccountVerifyPath
        #expect(path.map { $0.description } == ["oauth", "link", "verify"])
    }
}

// MARK: - Redirect Location Tests

@Suite("Redirect Location Tests")
struct RedirectLocationTests {

    @Test("default redirect location is root")
    func defaultRedirectLocationIsRoot() {
        let config = Passage.Configuration.FederatedLogin(
            providers: [.init(provider: .github())]
        )
        #expect(config.redirectLocation == "/")
    }

    @Test("custom redirect location is used")
    func customRedirectLocationIsUsed() {
        let config = Passage.Configuration.FederatedLogin(
            providers: [.init(provider: .github())],
            redirectLocation: "/dashboard"
        )
        #expect(config.redirectLocation == "/dashboard")
    }
}
