import Testing
import Vapor
import VaporTesting
import NIOCore
import NIOEmbedded
import Passage
import ImperialCore
import ImperialGitHub
import ImperialGoogle
@testable import PassageImperial

// MARK: - Mock HTTP Client

final class MockHTTPClient: Client, @unchecked Sendable {
    private let lock = NSLock()
    private var _responses: [(pattern: String, response: ClientResponse)] = []
    private var _recordedRequests: [ClientRequest] = []
    private let _eventLoop: any EventLoop

    init(eventLoop: any EventLoop = EmbeddedEventLoop()) {
        self._eventLoop = eventLoop
    }

    func setResponse(for url: String, response: ClientResponse) {
        lock.lock()
        defer { lock.unlock() }
        _responses.insert((pattern: url, response: response), at: 0)
    }

    func getRecordedRequests() -> [ClientRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedRequests
    }

    var eventLoop: any EventLoop {
        _eventLoop
    }

    func delegating(to eventLoop: any EventLoop) -> any Client {
        self
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        lock.lock()
        _recordedRequests.append(request)

        let urlString = request.url.string

        // Find the most specific match (longest pattern that matches)
        var bestMatch: (pattern: String, response: ClientResponse)?
        for entry in _responses {
            if urlString.contains(entry.pattern) {
                if bestMatch == nil || entry.pattern.count > bestMatch!.pattern.count {
                    bestMatch = entry
                }
            }
        }

        if let match = bestMatch {
            lock.unlock()
            return _eventLoop.makeSucceededFuture(match.response)
        }

        lock.unlock()
        return _eventLoop.makeSucceededFuture(ClientResponse(status: .notFound))
    }

    func logging(to logger: Logger) -> any Client {
        self
    }

    func allocating(to byteBufferAllocator: ByteBufferAllocator) -> any Client {
        self
    }
}

// MARK: - Test Response Helpers

extension ClientResponse {
    static func googleUserResponse(
        id: String = "google-123",
        email: String? = "user@gmail.com",
        name: String? = "Google User",
        picture: String? = "https://google.com/avatar.png",
        isEmailVerified: Bool = true
    ) -> ClientResponse {
        var headers = HTTPHeaders()
        headers.contentType = .json

        var body = ByteBuffer()
        var json: [String: Any] = ["id": id]
        if let email = email { json["email"] = email }
        if let name = name { json["name"] = name }
        if let picture = picture { json["picture"] = picture }
        json["verified_email"] = isEmailVerified

        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        body.writeBytes(jsonData)

        return ClientResponse(status: .ok, headers: headers, body: body)
    }

    static func googleErrorResponse(status: HTTPResponseStatus = .unauthorized) -> ClientResponse {
        return ClientResponse(status: status)
    }

    static func githubUserResponse(
        id: Int = 12345,
        login: String = "octocat",
        name: String? = "GitHub User",
        avatarURL: String? = "https://github.com/avatar.png"
    ) -> ClientResponse {
        var headers = HTTPHeaders()
        headers.contentType = .json

        var body = ByteBuffer()
        var json: [String: Any] = ["id": id, "login": login]
        if let name = name { json["name"] = name }
        if let avatarURL = avatarURL { json["avatar_url"] = avatarURL }

        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        body.writeBytes(jsonData)

        return ClientResponse(status: .ok, headers: headers, body: body)
    }

    static func githubEmailsResponse(emails: [(email: String, primary: Bool, verified: Bool)]) -> ClientResponse {
        var headers = HTTPHeaders()
        headers.contentType = .json

        var body = ByteBuffer()
        let json = emails.map { email in
            ["email": email.email, "primary": email.primary, "verified": email.verified] as [String: Any]
        }

        let jsonData = try! JSONSerialization.data(withJSONObject: json)
        body.writeBytes(jsonData)

        return ClientResponse(status: .ok, headers: headers, body: body)
    }

    static func githubErrorResponse(status: HTTPResponseStatus = .unauthorized) -> ClientResponse {
        return ClientResponse(status: status)
    }
}

// MARK: - fetchGoogleUser Tests

@Suite("fetchGoogleUser Tests")
struct FetchGoogleUserTests {

    @Test("fetches Google user with verified email")
    func fetchGoogleUserWithVerifiedEmail() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleUserResponse(
                id: "google-user-123",
                email: "verified@gmail.com",
                name: "Test User",
                picture: "https://google.com/photo.jpg",
                isEmailVerified: true
            )
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        // Call the actual production code
        let identity = try await service.fetchGoogleUser(
            using: "test-access-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.identifier.kind == .federated)
        #expect(identity.identifier.value == "google-user-123")
        #expect(identity.identifier.provider == "google")
        #expect(identity.provider == "Google")
        #expect(identity.verifiedEmails == ["verified@gmail.com"])
        #expect(identity.verifiedPhoneNumbers.isEmpty)
        #expect(identity.displayName == "Test User")
        #expect(identity.profilePictureURL == "https://google.com/photo.jpg")

        let requests = mockClient.getRecordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].headers["Authorization"].first == "Bearer test-access-token")
    }

    @Test("fetches Google user with unverified email")
    func fetchGoogleUserWithUnverifiedEmail() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleUserResponse(
                id: "google-user-456",
                email: "unverified@gmail.com",
                isEmailVerified: false
            )
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        let identity = try await service.fetchGoogleUser(
            using: "test-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.verifiedEmails.isEmpty)
    }

    @Test("fetches Google user without email")
    func fetchGoogleUserWithoutEmail() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleUserResponse(
                id: "google-user-789",
                email: nil,
                name: "No Email User",
                isEmailVerified: true
            )
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        let identity = try await service.fetchGoogleUser(
            using: "test-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.verifiedEmails.isEmpty)
        #expect(identity.displayName == "No Email User")
    }

    @Test("fetches Google user with nil optional fields")
    func fetchGoogleUserWithNilOptionalFields() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleUserResponse(
                id: "google-minimal",
                email: nil,
                name: nil,
                picture: nil,
                isEmailVerified: false
            )
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        let identity = try await service.fetchGoogleUser(
            using: "test-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.identifier.value == "google-minimal")
        #expect(identity.displayName == nil)
        #expect(identity.profilePictureURL == nil)
        #expect(identity.verifiedEmails.isEmpty)
    }

    @Test("throws error on Google API failure")
    func throwsErrorOnGoogleAPIFailure() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleErrorResponse(status: .unauthorized)
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        var didThrow = false
        do {
            _ = try await service.fetchGoogleUser(
                using: "invalid-token",
                for: provider,
                client: mockClient
            )
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                #expect(message.contains("Google API returned status"))
                didThrow = true
            }
        }

        #expect(didThrow)
    }

    @Test("throws error on Google API 500 error")
    func throwsErrorOnGoogleAPI500Error() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleErrorResponse(status: .internalServerError)
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        var didThrow = false
        do {
            _ = try await service.fetchGoogleUser(
                using: "test-token",
                for: provider,
                client: mockClient
            )
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                didThrow = message.contains("Google") && message.contains("status")
            }
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}

// MARK: - fetchGitHubUser Tests

@Suite("fetchGitHubUser Tests")
struct FetchGitHubUserTests {

    @Test("fetches GitHub user with verified emails")
    func fetchGitHubUserWithVerifiedEmails() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user/emails",
            response: .githubEmailsResponse(emails: [
                (email: "octocat@github.com", primary: true, verified: true),
                (email: "octocat@example.com", primary: false, verified: true),
                (email: "unverified@example.com", primary: false, verified: false)
            ])
        )

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubUserResponse(
                id: 12345,
                login: "octocat",
                name: "The Octocat",
                avatarURL: "https://github.com/octocat.png"
            )
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        let identity = try await service.fetchGitHubUser(
            using: "test-github-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.identifier.kind == .federated)
        #expect(identity.identifier.value == "12345")
        #expect(identity.identifier.provider == "github")
        #expect(identity.provider == "Github")
        #expect(identity.verifiedEmails == ["octocat@github.com", "octocat@example.com"])
        #expect(identity.verifiedPhoneNumbers.isEmpty)
        #expect(identity.displayName == "The Octocat")
        #expect(identity.profilePictureURL == "https://github.com/octocat.png")

        let requests = mockClient.getRecordedRequests()
        #expect(requests.count == 2)
        #expect(requests[0].headers["Authorization"].first == "Bearer test-github-token")
        #expect(requests[0].headers["User-Agent"].first == "Passage-Imperial")
    }

    @Test("fetches GitHub user with no verified emails")
    func fetchGitHubUserWithNoVerifiedEmails() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user/emails",
            response: .githubEmailsResponse(emails: [
                (email: "unverified@example.com", primary: true, verified: false)
            ])
        )

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubUserResponse(
                id: 67890,
                login: "testuser"
            )
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        let identity = try await service.fetchGitHubUser(
            using: "test-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.verifiedEmails.isEmpty)
    }

    @Test("fetches GitHub user with email scope failure")
    func fetchGitHubUserWithEmailScopeFailure() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user/emails",
            response: .githubErrorResponse(status: .notFound)
        )

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubUserResponse(
                id: 11111,
                login: "noemails"
            )
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        let identity = try await service.fetchGitHubUser(
            using: "test-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.verifiedEmails.isEmpty)
        #expect(identity.identifier.value == "11111")
    }

    @Test("fetches GitHub user without optional fields")
    func fetchGitHubUserWithoutOptionalFields() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user/emails",
            response: .githubEmailsResponse(emails: [])
        )

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubUserResponse(
                id: 99999,
                login: "minimaluser",
                name: nil,
                avatarURL: nil
            )
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        let identity = try await service.fetchGitHubUser(
            using: "test-token",
            for: provider,
            client: mockClient
        )

        #expect(identity.displayName == nil)
        #expect(identity.profilePictureURL == nil)
    }

    @Test("throws error on GitHub user API failure")
    func throwsErrorOnGitHubUserAPIFailure() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubErrorResponse(status: .unauthorized)
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        var didThrow = false
        do {
            _ = try await service.fetchGitHubUser(
                using: "invalid-token",
                for: provider,
                client: mockClient
            )
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                #expect(message.contains("GitHub API returned status"))
                didThrow = true
            }
        }

        #expect(didThrow)
    }

    @Test("throws error on GitHub API rate limit")
    func throwsErrorOnGitHubAPIRateLimit() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubErrorResponse(status: .tooManyRequests)
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        var didThrow = false
        do {
            _ = try await service.fetchGitHubUser(
                using: "test-token",
                for: provider,
                client: mockClient
            )
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                didThrow = message.contains("GitHub") && message.contains("status")
            }
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("GitHub API headers are correct")
    func gitHubAPIHeadersAreCorrect() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user/emails",
            response: .githubEmailsResponse(emails: [])
        )

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubUserResponse(id: 1, login: "test")
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        _ = try await service.fetchGitHubUser(
            using: "my-token",
            for: provider,
            client: mockClient
        )

        let requests = mockClient.getRecordedRequests()

        // Check user endpoint request headers
        let userRequest = requests[0]
        #expect(userRequest.headers["Authorization"].first == "Bearer my-token")
        #expect(userRequest.headers["Accept"].first == "application/vnd.github+json")
        #expect(userRequest.headers["User-Agent"].first == "Passage-Imperial")

        // Check emails endpoint request headers
        let emailsRequest = requests[1]
        #expect(emailsRequest.headers["Authorization"].first == "Bearer my-token")
        #expect(emailsRequest.headers["Accept"].first == "application/vnd.github+json")
        #expect(emailsRequest.headers["X-GitHub-Api-Version"].first == "2022-11-28")
        #expect(emailsRequest.headers["User-Agent"].first == "Passage-Imperial")
    }
}

// MARK: - fetchIdentity Tests

@Suite("fetchIdentity Tests")
struct FetchIdentityTests {

    @Test("fetchIdentity routes to Google for Google service")
    func fetchIdentityRoutesToGoogle() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "googleapis.com/oauth2/v2/userinfo",
            response: .googleUserResponse(id: "google-id-123")
        )

        let service = ImperialFederatedLoginService(services: [.google: Google.self])
        let provider = Passage.FederatedLogin.Provider.google()

        let identity = try await service.fetchIdentity(
            from: Google.self,
            using: "token",
            for: provider,
            client: mockClient
        )

        #expect(identity.identifier.value == "google-id-123")
        #expect(identity.provider == "Google")
    }

    @Test("fetchIdentity routes to GitHub for GitHub service")
    func fetchIdentityRoutesToGitHub() async throws {
        let mockClient = MockHTTPClient()

        mockClient.setResponse(
            for: "api.github.com/user/emails",
            response: .githubEmailsResponse(emails: [])
        )

        mockClient.setResponse(
            for: "api.github.com/user",
            response: .githubUserResponse(id: 54321, login: "ghuser")
        )

        let service = ImperialFederatedLoginService(services: [.github: GitHub.self])
        let provider = Passage.FederatedLogin.Provider.github()

        let identity = try await service.fetchIdentity(
            from: GitHub.self,
            using: "token",
            for: provider,
            client: mockClient
        )

        #expect(identity.identifier.value == "54321")
        #expect(identity.provider == "Github")
    }

    @Test("fetchIdentity throws for unsupported provider")
    func fetchIdentityThrowsForUnsupportedProvider() async throws {
        let mockClient = MockHTTPClient()
        let service = ImperialFederatedLoginService(services: [:])
        let provider = Passage.FederatedLogin.Provider.custom(name: "unsupported")

        var didThrow = false
        do {
            _ = try await service.fetchIdentity(
                from: UnsupportedMockService.self,
                using: "token",
                for: provider,
                client: mockClient
            )
        } catch let error as PassageError {
            if case .unexpected(let message) = error {
                #expect(message.contains("Unsupported OAuth provider"))
                didThrow = true
            }
        }

        #expect(didThrow)
    }
}

// MARK: - Mock Federated Service (for unsupported provider test)

final class UnsupportedMockService: FederatedService {
    nonisolated(unsafe) static var tokens: FederatedServiceTokens?

    static func callback(_ request: Request) async throws -> String {
        return "mock-callback-token"
    }

    required init(
        routes: some RoutesBuilder,
        authenticate: String,
        authenticateCallback: (@Sendable (Request) async throws -> Void)?,
        callback: String,
        scope: [String],
        completion: @escaping @Sendable (Request, String) async throws -> some AsyncResponseEncodable
    ) throws {
        // Mock implementation
    }
}
