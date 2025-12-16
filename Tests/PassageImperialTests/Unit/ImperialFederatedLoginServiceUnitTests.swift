import Testing
import Vapor
import VaporTesting
import Passage
import ImperialCore
import ImperialGitHub
import ImperialGoogle
@testable import PassageImperial

// MARK: - Mock User

struct MockUser: User {
    typealias Id = UUID

    var id: UUID?
    var email: String?
    var phone: String?
    var username: String?
    var passwordHash: String?
    var isAnonymous: Bool = false
    var isEmailVerified: Bool = false
    var isPhoneVerified: Bool = false

    static func make(
        id: UUID = UUID(),
        email: String? = "user@example.com",
        username: String? = "testuser"
    ) -> MockUser {
        MockUser(
            id: id,
            email: email,
            username: username
        )
    }

    public var sessionID: String {
        guard let id = self.id else {
            fatalError("Cannot persist unsaved model to session.")
        }
        return id.uuidString
    }
}

// MARK: - ImperialFederatedLoginService Initialization Tests

@Suite("ImperialFederatedLoginService Initialization Tests")
struct InitializationTests {

    @Test("initializes with empty services dictionary")
    func initWithEmptyServices() {
        let service = ImperialFederatedLoginService(services: [:])
        #expect(service.services.isEmpty)
    }

    @Test("initializes with GitHub service")
    func initWithGitHubService() {
        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self
        ])
        #expect(service.services.count == 1)
        #expect(service.services[.github] != nil)
    }

    @Test("initializes with Google service")
    func initWithGoogleService() {
        let service = ImperialFederatedLoginService(services: [
            .google: Google.self
        ])
        #expect(service.services.count == 1)
        #expect(service.services[.google] != nil)
    }

    @Test("initializes with multiple services")
    func initWithMultipleServices() {
        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self,
            .google: Google.self
        ])
        #expect(service.services.count == 2)
        #expect(service.services[.github] != nil)
        #expect(service.services[.google] != nil)
    }

    @Test("initializes with custom provider name")
    func initWithCustomProviderName() {
        let customName = FederatedProvider.Name("custom-provider")
        let service = ImperialFederatedLoginService(services: [
            customName: GitHub.self
        ])
        #expect(service.services.count == 1)
        #expect(service.services[customName] != nil)
    }
}

// MARK: - Provider Configuration Error Tests

@Suite("Provider Configuration Error Tests")
struct ProviderConfigurationErrorTests {

    @Test("throws error when provider is not configured")
    func throwsErrorWhenProviderNotConfigured() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self
        ])

        let config = Passage.Configuration.FederatedLogin(
            providers: [] // No providers configured
        )

        var didThrow = false
        do {
            try service.register(
                router: app.routes,
                origin: URL(string: "https://example.com")!,
                group: ["auth"],
                config: config
            ) { request, identity in
                return HTTPStatus.ok
            }
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                #expect(message.contains("is not configured"))
                #expect(message.contains("github"))
                didThrow = true
            }
        }

        #expect(didThrow)
    }

    @Test("throws error when service exists but provider config missing")
    func throwsErrorWhenServiceExistsButProviderMissing() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        let service = ImperialFederatedLoginService(services: [
            .github: GitHub.self,
            .google: Google.self
        ])

        // Only configure GitHub, not Google
        let config = Passage.Configuration.FederatedLogin(
            providers: [.init(provider: .github())]
        )

        var didThrow = false
        do {
            try service.register(
                router: app.routes,
                origin: URL(string: "https://example.com")!,
                group: ["auth"],
                config: config
            ) { request, identity in
                return HTTPStatus.ok
            }
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                #expect(message.contains("is not configured"))
                #expect(message.contains("google"))
                didThrow = true
            }
        }

        #expect(didThrow)
    }
}

// MARK: - Type Conformance Tests

@Suite("Type Conformance Tests")
struct TypeConformanceTests {

    @Test("ImperialFederatedLoginService conforms to FederatedLoginService protocol")
    func conformsToFederatedLoginService() {
        let service = ImperialFederatedLoginService(services: [:])
        let _: any Passage.FederatedLoginService = service
    }

    @Test("ImperialFederatedLoginService is Sendable")
    func isSendable() {
        func acceptsSendable<T: Sendable>(_ value: T) {}
        let service = ImperialFederatedLoginService(services: [:])
        acceptsSendable(service)
    }

    @Test("Services dictionary is accessible")
    func servicesAccessible() {
        let services: [FederatedProvider.Name: any FederatedService.Type] = [
            .github: GitHub.self,
            .google: Google.self
        ]
        let service = ImperialFederatedLoginService(services: services)
        #expect(service.services.count == 2)
    }
}

// MARK: - Provider Name Tests

@Suite("Provider Name Tests")
struct ProviderNameTests {

    @Test("Provider.Name equality")
    func providerNameEquality() {
        let name1 = FederatedProvider.Name("github")
        let name2 = FederatedProvider.Name("github")
        let name3 = FederatedProvider.Name("google")

        #expect(name1 == name2)
        #expect(name1 != name3)
    }

    @Test("Provider.Name static values")
    func providerNameStaticValues() {
        #expect(FederatedProvider.Name.github.description == "github")
        #expect(FederatedProvider.Name.google.description == "google")
    }

    @Test("Provider.Name hashable")
    func providerNameHashable() {
        var set = Set<FederatedProvider.Name>()
        set.insert(.github)
        set.insert(.google)
        set.insert(.github) // Duplicate

        #expect(set.count == 2)
    }
}

// MARK: - FederatedIdentity Tests

@Suite("FederatedIdentity Tests")
struct FederatedIdentityTests {

    @Test("FederatedIdentity initializes correctly")
    func federatedIdentityInit() {
        let identity = FederatedIdentity(
            identifier: .federated(.github, userId: "12345"),
            provider: .named("GitHub"),
            verifiedEmails: ["user@example.com"],
            verifiedPhoneNumbers: [],
            displayName: "Test User",
            profilePictureURL: "https://example.com/avatar.png"
        )

        #expect(identity.identifier.kind == .federated)
        #expect(identity.identifier.value == "12345")
        #expect(identity.identifier.provider?.description == "github")
        #expect(identity.provider.description == "GitHub")
        #expect(identity.verifiedEmails == ["user@example.com"])
        #expect(identity.verifiedPhoneNumbers.isEmpty)
        #expect(identity.displayName == "Test User")
        #expect(identity.profilePictureURL == "https://example.com/avatar.png")
    }

    @Test("FederatedIdentity email accessor returns first email")
    func federatedIdentityEmailAccessor() {
        let identity = FederatedIdentity(
            identifier: .federated(.github, userId: "12345"),
            provider: .named("GitHub"),
            verifiedEmails: ["first@example.com", "second@example.com"],
            verifiedPhoneNumbers: [],
            displayName: nil,
            profilePictureURL: nil
        )

        #expect(identity.email == "first@example.com")
    }

    @Test("FederatedIdentity email accessor returns nil when empty")
    func federatedIdentityEmailAccessorReturnsNil() {
        let identity = FederatedIdentity(
            identifier: .federated(.github, userId: "12345"),
            provider: .named("GitHub"),
            verifiedEmails: [],
            verifiedPhoneNumbers: [],
            displayName: nil,
            profilePictureURL: nil
        )

        #expect(identity.email == nil)
    }

    @Test("FederatedIdentity phone accessor returns first phone")
    func federatedIdentityPhoneAccessor() {
        let identity = FederatedIdentity(
            identifier: .federated(.github, userId: "12345"),
            provider: .named("GitHub"),
            verifiedEmails: [],
            verifiedPhoneNumbers: ["+1234567890", "+0987654321"],
            displayName: nil,
            profilePictureURL: nil
        )

        #expect(identity.phone == "+1234567890")
    }

    @Test("FederatedIdentity phone accessor returns nil when empty")
    func federatedIdentityPhoneAccessorReturnsNil() {
        let identity = FederatedIdentity(
            identifier: .federated(.github, userId: "12345"),
            provider: .named("GitHub"),
            verifiedEmails: [],
            verifiedPhoneNumbers: [],
            displayName: nil,
            profilePictureURL: nil
        )

        #expect(identity.phone == nil)
    }

    @Test("FederatedIdentity userInfo accessor")
    func federatedIdentityUserInfoAccessor() {
        let identity = FederatedIdentity(
            identifier: .federated(.github, userId: "12345"),
            provider: .named("GitHub"),
            verifiedEmails: ["user@example.com"],
            verifiedPhoneNumbers: ["+1234567890"],
            displayName: "Test User",
            profilePictureURL: nil
        )

        let userInfo = identity.userInfo
        #expect(userInfo.email == "user@example.com")
        #expect(userInfo.phone == "+1234567890")
    }
}

// MARK: - Identifier Tests

@Suite("Identifier Tests")
struct IdentifierTests {

    @Test("federated identifier creation")
    func federatedIdentifierCreation() {
        let identifier = Identifier.federated(.github, userId: "user123")

        #expect(identifier.kind == .federated)
        #expect(identifier.value == "user123")
        #expect(identifier.provider?.description == "github")
    }

    @Test("federated identifier with different providers")
    func federatedIdentifierWithDifferentProviders() {
        let githubId = Identifier.federated(.github, userId: "gh123")
        let googleId = Identifier.federated(.google, userId: "goog456")

        #expect(githubId.provider?.description == "github")
        #expect(googleId.provider?.description == "google")
        #expect(githubId != googleId)
    }
}

// MARK: - Configuration Path Tests

@Suite("Configuration Path Tests")
struct ConfigurationPathTests {

    @Test("loginPath generates correct path for provider")
    func loginPathGeneration() {
        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github())]
        )

        let provider = FederatedProvider.github()
        let path = config.loginPath(for: provider)

        #expect(path.map { $0.description } == ["oauth", "github"])
    }

    @Test("callbackPath generates correct path for provider")
    func callbackPathGeneration() {
        let config = Passage.Configuration.FederatedLogin(
            routes: .init(group: "oauth"),
            providers: [.init(provider: .github())]
        )

        let provider = FederatedProvider.github()
        let path = config.callbackPath(for: provider)

        #expect(path.map { $0.description } == ["oauth", "github", "callback"])
    }
}

// MARK: - Provider Factory Tests

@Suite("Provider Factory Tests")
struct ProviderFactoryTests {

    @Test("github() creates GitHub provider")
    func githubProviderFactory() {
        let provider = FederatedProvider.github()

        #expect(provider.name == .github)
        #expect(provider.scope.isEmpty)
    }

    @Test("google() creates Google provider")
    func googleProviderFactory() {
        let provider = FederatedProvider.google()

        #expect(provider.name == .google)
        #expect(provider.scope.isEmpty)
    }

    @Test("github() with scope")
    func githubProviderWithScope() {
        let provider = FederatedProvider.github(
            scope: ["user:email", "read:user"]
        )

        #expect(provider.name == .github)
        #expect(provider.scope == ["user:email", "read:user"])
    }

    @Test("google() with scope")
    func googleProviderWithScope() {
        let provider = FederatedProvider.google(
            scope: ["email", "profile"]
        )

        #expect(provider.name == .google)
        #expect(provider.scope == ["email", "profile"])
    }

    @Test("custom() creates custom provider")
    func customProviderFactory() {
        let provider = FederatedProvider.custom(
            name: "my-custom-provider",
            scope: ["custom:scope"]
        )

        #expect(provider.name.description == "my-custom-provider")
        #expect(provider.scope == ["custom:scope"])
    }
}
