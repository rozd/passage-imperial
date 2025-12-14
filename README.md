# passage-imperial

[![Release](https://img.shields.io/github/v/release/rozd/passage-imperial)](https://github.com/rozd/passage-imperial/releases)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/github/license/rozd/passage-imperial)](LICENSE)
[![codecov](https://codecov.io/gh/rozd/passage-imperial/branch/main/graph/badge.svg)](https://codecov.io/gh/rozd/passage-imperial)

OAuth federated login implementation for [Passage](https://github.com/vapor-community/passage) authentication framework.

This package provides a bridge between Passage and [Imperial](https://github.com/vapor-community/Imperial), enabling OAuth-based authentication with providers like GitHub and Google.

> **Note:** This package cannot be used standalone. It requires both [Passage](https://github.com/vapor-community/passage) and [Imperial](https://github.com/vapor-community/Imperial) packages to function.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rozd/passage-imperial.git", from: "0.0.1"),
]
```

Then add `PassageImperial` to your target dependencies:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "PassageImperial", package: "passage-imperial"),
    ]
)
```

## Configuration

Configure `ImperialFederatedLoginService` with your OAuth providers:

```swift
import Passage
import PassageImperial
import ImperialGitHub
import ImperialGoogle

let federatedLoginService = ImperialFederatedLoginService(
    services: [
        .github: GitHub.self,
        .google: Google.self,
    ]
)
```

Then pass it to Passage during configuration:

```swift
app.passage.configure(
    services: .init(
        federatedLoginService: federatedLoginService,
        // ... other services
    ),
    configuration: .init(
        federatedLogin: .init(
            providers: [
                .init(
                    name: .github,
                    clientId: Environment.get("GITHUB_CLIENT_ID")!,
                    clientSecret: Environment.get("GITHUB_CLIENT_SECRET")!,
                    scope: ["user:email"]
                ),
                .init(
                    name: .google,
                    clientId: Environment.get("GOOGLE_CLIENT_ID")!,
                    clientSecret: Environment.get("GOOGLE_CLIENT_SECRET")!,
                    scope: ["profile", "email"]
                ),
            ]
        ),
        // ... other configuration
    )
)
```

## Supported Providers

| Provider | Imperial Type | Required Scopes |
|----------|--------------|-----------------|
| GitHub | `GitHub.self` | `user:email` (for verified emails) |
| Google | `Google.self` | `profile`, `email` |

## How It Works

1. User initiates OAuth flow via the login endpoint (e.g., `/auth/federated/github/login`)
2. Imperial handles the OAuth redirect and callback
3. PassageImperial fetches user identity from the provider's API
4. Passage creates or links the user account with the federated identity

## Fetched User Data

The service automatically fetches user information from OAuth providers:

**GitHub:**
- User ID (federated identifier)
- Verified email addresses
- Display name
- Avatar URL

**Google:**
- User ID (federated identifier)
- Email (if verified)
- Display name
- Profile picture URL

## Requirements

- Swift 6.0+
- macOS 13+ / Linux
- Vapor 4.119+
- Imperial 2.2+

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
