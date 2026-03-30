import Foundation

enum ProviderCatalog {
    static let managedZAIProviderName = "zai"

    /// OAuth provider keys used in config.yaml oauth-excluded-models.
    static let oauthProviderKeys: [String: String] = [
        "claude": "claude",
        "codex": "codex",
        "gemini": "gemini-cli",
        "github-copilot": "github-copilot",
        "antigravity": "antigravity",
        "qwen": "qwen"
    ]

    static let reservedCustomProviderKeys = Set(oauthProviderKeys.keys)
        .union(oauthProviderKeys.values)
        .union([managedZAIProviderName])

    /// Model name prefixes that identify OAuth passthrough providers for health tracking.
    static let oauthPassthroughPrefixes: [(prefix: String, providerID: String)] = [
        ("claude-", "claude"),
        ("gemini-", "gemini"),
        ("codex-", "codex"),
    ]
}
