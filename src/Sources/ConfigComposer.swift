import Foundation

struct ConfigProviderAuthRecord: Equatable {
    let providerID: String
    let apiKey: String
    let isDisabled: Bool
}

enum ConfigComposer {
    static let uiMetadataKeys: Set<String> = ["display-name", "help-text", "icon-system"]
    static let additiveUserConfigRootKeys: Set<String> = [
        "claude-api-key",
        "debug",
        "logging-to-file",
        "max-retry-credentials",
        "oauth-excluded-models",
        "openai-compatibility",
        "policies",
        "passthrough-headers",
        "proxy-url",
        "quota-exceeded",
        "request-retry",
        "request-timeout",
        "routing",
        "smart-aliases",
        "usage-statistics-enabled"
    ]

    static func applyManagedProviderPatches(to root: [String: Any]) -> [String: Any] {
        var patchedRoot = root

        if patchedRoot["max-retry-credentials"] == nil {
            patchedRoot["max-retry-credentials"] = 0
        }

        let patchedProviders = mergeManagedProviderEntries(
            base: stringKeyedDictionaryArray(patchedRoot["openai-compatibility"]),
            managed: temporaryManagedProviderEntries()
        )
        if !patchedProviders.isEmpty {
            patchedRoot["openai-compatibility"] = patchedProviders
        }

        let patchedSmartAliases = mergeManagedSmartAliasEntries(
            base: stringKeyedDictionary(patchedRoot["smart-aliases"] as Any) ?? [:],
            managed: defaultManagedSmartAliases()
        )
        if !patchedSmartAliases.isEmpty {
            patchedRoot["smart-aliases"] = patchedSmartAliases
        }

        return patchedRoot
    }
    
    static func composeAdditiveBaseConfig(bundledRoot: [String: Any], userRoot: [String: Any]?) -> [String: Any] {
        guard let userRoot else {
            return bundledRoot
        }
        return mergeDictionary(bundledRoot, overlaidWith: sanitizeAdditiveUserConfig(userRoot))
    }

    static func ignoredAdditiveUserConfigKeys(in root: [String: Any]) -> [String] {
        root.keys
            .filter { !isSupportedAdditiveUserConfigKey($0) }
            .sorted()
    }

    static func sanitizeAdditiveUserConfig(_ root: [String: Any]) -> [String: Any] {
        root.reduce(into: [String: Any]()) { sanitized, entry in
            guard isSupportedAdditiveUserConfigKey(entry.key) else {
                return
            }
            sanitized[entry.key] = entry.value
        }
    }
    
    static func parseCustomProviders(
        from root: [String: Any],
        reservedProviderIDs: Set<String>
    ) -> [CustomProviderDefinition] {
        stringKeyedDictionaryArray(root["openai-compatibility"])
            .compactMap { entry in
                guard let providerID = normalizedProviderID(from: entry),
                      !reservedProviderIDs.contains(providerID) else {
                    return nil
                }
                
                let modelAliases = stringKeyedDictionaryArray(entry["models"])
                    .compactMap { model in
                        (model["alias"] as? String) ?? (model["name"] as? String)
                    }
                return CustomProviderDefinition(
                    id: providerID,
                    title: (entry["display-name"] as? String) ?? CustomProviderDefinition.defaultTitle(for: providerID),
                    baseURL: normalizedString(entry["base-url"]) ?? "",
                    helpText: entry["help-text"] as? String,
                    iconSystemName: entry["icon-system"] as? String,
                    modelAliases: modelAliases,
                    inlineAPIKeys: deduplicatedAPIKeys(from: entry)
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func validateCustomProviders(
        in root: [String: Any],
        reservedProviderIDs: Set<String>
    ) -> [String] {
        guard let rawOpenAICompatibility = root["openai-compatibility"] else {
            return []
        }
        guard let entries = rawOpenAICompatibility as? [Any] else {
            return ["openai-compatibility must be an array of provider mappings."]
        }

        var errors: [String] = []
        var seenProviderIDs: Set<String> = []

        for (index, rawEntry) in entries.enumerated() {
            let path = "openai-compatibility[\(index)]"

            guard let entry = stringKeyedDictionary(rawEntry) else {
                errors.append("\(path) must be a mapping.")
                continue
            }

            guard let rawProviderName = entry["name"] as? String else {
                errors.append("\(path) must define a string name.")
                continue
            }

            guard let providerID = normalizedString(rawProviderName) else {
                errors.append("\(path) must define a non-empty name.")
                continue
            }

            guard rawProviderName == providerID else {
                errors.append("Provider name '\(rawProviderName)' must not include leading or trailing whitespace.")
                continue
            }

            if seenProviderIDs.contains(providerID) {
                errors.append("Duplicate openai-compatibility provider '\(providerID)' is not allowed.")
            } else {
                seenProviderIDs.insert(providerID)
            }

            if reservedProviderIDs.contains(providerID), providerID != ProviderCatalog.managedZAIProviderName {
                errors.append("Provider '\(providerID)' is reserved and cannot be declared under openai-compatibility.")
                continue
            }

            if let modelsValue = entry["models"] {
                errors.append(contentsOf: validateMappingArray(modelsValue, path: "\(path).models"))
            }

            if let apiKeyEntriesValue = entry["api-key-entries"] {
                if let apiKeyEntries = apiKeyEntriesValue as? [Any] {
                    for (apiKeyIndex, rawAPIKeyEntry) in apiKeyEntries.enumerated() {
                        let apiKeyPath = "\(path).api-key-entries[\(apiKeyIndex)]"
                        guard let apiKeyEntry = stringKeyedDictionary(rawAPIKeyEntry) else {
                            errors.append("\(apiKeyPath) must be a mapping.")
                            continue
                        }
                        guard normalizedString(apiKeyEntry["api-key"]) != nil else {
                            errors.append("\(apiKeyPath) must define a non-empty api-key.")
                            continue
                        }
                    }
                } else {
                    errors.append("\(path).api-key-entries must be an array of mappings.")
                }
            }

            if providerID == ProviderCatalog.managedZAIProviderName {
                continue
            }

            guard normalizedString(entry["base-url"]) != nil else {
                errors.append("Custom provider '\(providerID)' must define a non-empty base-url.")
                continue
            }
        }

        return errors
    }

    static func validateSmartAliases(in root: [String: Any]) -> [String] {
        guard let rawSmartAliases = root["smart-aliases"] else {
            return []
        }
        guard let entries = rawSmartAliases as? [String: Any] else {
            return ["smart-aliases must be a mapping of alias name to configuration."]
        }

        let knownRequestModelAliases = knownSmartAliasCandidateModels(in: root)
        var errors: [String] = []

        for aliasName in entries.keys.sorted() {
            let path = "smart-aliases.\(aliasName)"
            guard let rawEntry = entries[aliasName] else {
                errors.append("\(path) must be a mapping.")
                continue
            }
            guard let entry = stringKeyedDictionary(rawEntry) else {
                errors.append("\(path) must be a mapping.")
                continue
            }

            guard normalizedString(aliasName) == aliasName else {
                errors.append("Smart alias name '\(aliasName)' must not include leading or trailing whitespace.")
                continue
            }

            let requestClass = normalizedString(entry["request-class"])
            if requestClass != "plain-chat" {
                errors.append("\(path).request-class must be 'plain-chat'.")
            }

            let failover = normalizedString(entry["failover"])
            if failover != "silent" {
                errors.append("\(path).failover must be 'silent'.")
            }

            if let sensitivityValue = normalizedString(entry["health-sensitivity"]) {
                if sensitivityValue != "eager" && sensitivityValue != "balanced" && sensitivityValue != "conservative" {
                    errors.append("\(path).health-sensitivity must be 'eager', 'balanced', or 'conservative'.")
                }
            }

            guard let candidates = entry["candidates"] as? [Any] else {
                errors.append("\(path).candidates must be an array of model aliases.")
                continue
            }

            var normalizedCandidates: [String] = []
            for (candidateIndex, rawCandidate) in candidates.enumerated() {
                guard let rawCandidateString = rawCandidate as? String else {
                    errors.append("\(path).candidates[\(candidateIndex)] must be a string.")
                    continue
                }
                guard let candidate = normalizedString(rawCandidateString) else {
                    errors.append("\(path).candidates[\(candidateIndex)] must be a non-empty string.")
                    continue
                }
                if candidate != rawCandidateString {
                    errors.append("\(path).candidates[\(candidateIndex)] must not include leading or trailing whitespace.")
                    continue
                }
                normalizedCandidates.append(candidate)
            }

            if normalizedCandidates.isEmpty {
                errors.append("\(path).candidates must contain at least one model alias.")
            }

            if Set(normalizedCandidates).count != normalizedCandidates.count {
                errors.append("\(path).candidates must not contain duplicates.")
            }

            for candidate in normalizedCandidates {
                if entries[candidate] != nil {
                    errors.append("\(path).candidates must not reference another smart alias ('\(candidate)').")
                    continue
                }
                if !knownRequestModelAliases.contains(candidate) {
                    errors.append("\(path).candidates contains unknown model alias '\(candidate)'.")
                }
            }
        }

        return errors
    }
    
    static func composeRuntimeConfig(
        baseRoot: [String: Any],
        reservedCustomProviderKeys: Set<String>,
        disabledCustomProviderIDs: Set<String>,
        disabledOAuthProviderKeys: [String],
        zaiAPIKeys: [String],
        customProviderAuthRecords: [ConfigProviderAuthRecord],
        includeManagedZAIProvider: Bool,
        managedZAIProviderName: String = "zai"
    ) -> [String: Any] {
        var mergedRoot = baseRoot
        
        let oauthExcludedModels = buildOAuthExcludedModels(
            from: mergedRoot["oauth-excluded-models"],
            disabledOAuthProviderKeys: disabledOAuthProviderKeys
        )
        if let oauthExcludedModels {
            mergedRoot["oauth-excluded-models"] = oauthExcludedModels
        } else {
            mergedRoot.removeValue(forKey: "oauth-excluded-models")
        }
        
        let managedCustomProviderIDs = Set(
            parseCustomProviders(from: baseRoot, reservedProviderIDs: reservedCustomProviderKeys).map(\.id)
        )
        let authEntriesByProviderID = Dictionary(
            grouping: customProviderAuthRecords.filter { !$0.isDisabled },
            by: \.providerID
        ).mapValues { records in
            records.map { ["api-key": $0.apiKey] }
        }
        
        var mergedOpenAICompatibility: [[String: Any]] = []
        var mergedClaudeAPIKeyEntries: [[String: Any]] = []
        var managedZAIBaseEntry: [String: Any]?
        var managedZAIClaudeBaseEntry: [String: Any]?
        for entry in stringKeyedDictionaryArray(mergedRoot["openai-compatibility"]) {
            guard let providerName = normalizedProviderID(from: entry) else {
                continue
            }

            var sanitizedEntry = stripCustomProviderUIMetadata(from: entry)
            sanitizedEntry["name"] = providerName
            if providerName == managedZAIProviderName {
                managedZAIBaseEntry = sanitizedEntry
                continue
            }
            
            if managedCustomProviderIDs.contains(providerName) {
                if disabledCustomProviderIDs.contains(providerName) {
                    continue
                }

                let inlineEntries = apiKeys(from: entry).map { ["api-key": $0] }
                let authEntries = authEntriesByProviderID[providerName] ?? []
                let effectiveEntries = deduplicatedAPIKeyEntries(inlineEntries + authEntries)
                if effectiveEntries.isEmpty {
                    if managedProviderRequiresAPIKey(entry) {
                        continue
                    }
                    sanitizedEntry.removeValue(forKey: "api-key-entries")
                    sanitizedEntry.removeValue(forKey: "api-key")
                } else {
                    sanitizedEntry["api-key-entries"] = effectiveEntries
                    sanitizedEntry.removeValue(forKey: "api-key")
                }
            }
            
            mergedOpenAICompatibility.append(sanitizedEntry)
        }

        for entry in stringKeyedDictionaryArray(mergedRoot["claude-api-key"]) {
            if isManagedZAIClaudeEntry(entry) {
                managedZAIClaudeBaseEntry = entry
                continue
            }
            mergedClaudeAPIKeyEntries.append(entry)
        }
        
        if includeManagedZAIProvider {
            let managedZAIEntries = makeZAIClaudeProviderEntries(
                baseEntry: managedZAIClaudeBaseEntry ?? managedZAIBaseEntry,
                managedAPIKeys: zaiAPIKeys
            )
            if !managedZAIEntries.isEmpty {
                mergedClaudeAPIKeyEntries.append(contentsOf: managedZAIEntries)
            }
        }
        
        if mergedOpenAICompatibility.isEmpty {
            mergedRoot.removeValue(forKey: "openai-compatibility")
        } else {
            mergedRoot["openai-compatibility"] = mergedOpenAICompatibility
        }

        if mergedClaudeAPIKeyEntries.isEmpty {
            mergedRoot.removeValue(forKey: "claude-api-key")
        } else {
            mergedRoot["claude-api-key"] = mergedClaudeAPIKeyEntries
        }
        
        return mergedRoot
    }
    
    static func stringKeyedDictionary(_ value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? [AnyHashable: Any] {
            var stringDictionary: [String: Any] = [:]
            for (key, nestedValue) in dictionary {
                guard let stringKey = key as? String else {
                    continue
                }
                stringDictionary[stringKey] = nestedValue
            }
            return stringDictionary
        }
        return nil
    }
    
    static func stringKeyedDictionaryArray(_ value: Any?) -> [[String: Any]] {
        guard let array = value as? [Any] else {
            return []
        }
        return array.compactMap { stringKeyedDictionary($0) }
    }

    static func stringArray(_ value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }
        }
        return []
    }

    static func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isOAuthProviderWildcardExcluded(_ oauthProviderKey: String, in root: [String: Any]) -> Bool {
        let exclusions = stringKeyedDictionary(root["oauth-excluded-models"] ?? [:]) ?? [:]
        return stringArray(exclusions[oauthProviderKey]).contains("*")
    }
    
    private static func mergeDictionary(_ base: [String: Any], overlaidWith overlay: [String: Any]) -> [String: Any] {
        var merged = base
        
        for (key, overlayValue) in overlay {
            if key == "openai-compatibility" {
                if let overlayArray = overlayValue as? [Any] {
                    guard !overlayArray.isEmpty else {
                        continue
                    }

                    let overlayEntries = overlayArray.compactMap { stringKeyedDictionary($0) }
                    if overlayEntries.isEmpty {
                        merged[key] = overlayValue
                    } else {
                        let baseEntries = stringKeyedDictionaryArray(merged[key])
                        merged[key] = mergeNamedEntries(base: baseEntries, overlay: overlayEntries)
                    }
                } else {
                    merged[key] = overlayValue
                }
                continue
            }
            
            if let overlayDictionary = stringKeyedDictionary(overlayValue),
               let baseDictionary = merged[key].flatMap(stringKeyedDictionary) {
                merged[key] = mergeDictionary(baseDictionary, overlaidWith: overlayDictionary)
            } else {
                merged[key] = overlayValue
            }
        }
        
        return merged
    }

    private static func isSupportedAdditiveUserConfigKey(_ key: String) -> Bool {
        additiveUserConfigRootKeys.contains(key) || key.hasSuffix("-api-key")
    }
    
    private static func mergeNamedEntries(base: [[String: Any]], overlay: [[String: Any]]) -> [[String: Any]] {
        var mergedEntries = base
        var indexByName: [String: Int] = [:]
        
        for (index, entry) in base.enumerated() {
            if let name = normalizedProviderID(from: entry) {
                indexByName[name] = index
                if (mergedEntries[index]["name"] as? String) != name {
                    mergedEntries[index]["name"] = name
                }
            }
        }
        
        for overlayEntry in overlay {
            guard let name = normalizedProviderID(from: overlayEntry) else {
                mergedEntries.append(overlayEntry)
                continue
            }

            var canonicalOverlayEntry = overlayEntry
            canonicalOverlayEntry["name"] = name
            
            if let existingIndex = indexByName[name] {
                let existingEntry = mergedEntries[existingIndex]
                mergedEntries[existingIndex] = mergeDictionary(existingEntry, overlaidWith: canonicalOverlayEntry)
            } else {
                indexByName[name] = mergedEntries.count
                mergedEntries.append(canonicalOverlayEntry)
            }
        }
        
        return mergedEntries
    }

    private static func mergeManagedProviderEntries(base: [[String: Any]], managed: [[String: Any]]) -> [[String: Any]] {
        var mergedEntries = base
        let indexByName = Dictionary(
            uniqueKeysWithValues: base.enumerated().compactMap { index, entry in
                normalizedProviderID(from: entry).map { ($0, index) }
            }
        )

        for managedEntry in managed {
            guard let name = normalizedProviderID(from: managedEntry) else {
                mergedEntries.append(managedEntry)
                continue
            }

            if let existingIndex = indexByName[name] {
                let existingEntry = mergedEntries[existingIndex]
                var mergedEntry = mergeDictionary(managedEntry, overlaidWith: existingEntry)
                mergedEntry["name"] = name
                if let managedBaseURL = managedEntry["base-url"] {
                    mergedEntry["base-url"] = managedBaseURL
                }
                if let managedModels = managedEntry["models"] {
                    mergedEntry["models"] = managedModels
                }
                mergedEntries[existingIndex] = mergedEntry
            } else {
                mergedEntries.append(managedEntry)
            }
        }

        return mergedEntries
    }

    private static func mergeManagedSmartAliasEntries(base: [String: Any], managed: [String: Any]) -> [String: Any] {
        var merged = base
        for (key, value) in managed {
            let mergedValue: Any
            if let baseEntry = stringKeyedDictionary(merged[key] as Any),
               let managedEntry = stringKeyedDictionary(value) {
                mergedValue = mergeDictionary(baseEntry, overlaidWith: managedEntry)
            } else {
                mergedValue = value
            }
            merged[key] = mergedValue
        }
        return merged
    }

    private static func apiKeyEntries(from entry: [String: Any]) -> [[String: String]] {
        stringKeyedDictionaryArray(entry["api-key-entries"]).compactMap { keyEntry in
            guard let apiKey = normalizedString(keyEntry["api-key"]) else {
                return nil
            }
            return ["api-key": apiKey]
        }
    }

    private static func apiKeys(from entry: [String: Any]) -> [String] {
        var keys = deduplicatedAPIKeys(from: entry)
        if let inlineAPIKey = normalizedString(entry["api-key"]) {
            keys.append(inlineAPIKey)
        }
        return deduplicatedAPIKeys(keys)
    }

    private static func deduplicatedAPIKeys(from entry: [String: Any]) -> [String] {
        deduplicatedAPIKeyEntries(apiKeyEntries(from: entry)).compactMap { $0["api-key"] }
    }

    private static func deduplicatedAPIKeys(_ keys: [String]) -> [String] {
        var seen: Set<String> = []
        return keys.filter { key in
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }
    
    private static func deduplicatedAPIKeyEntries(_ entries: [[String: String]]) -> [[String: String]] {
        var seen: Set<String> = []
        return entries.filter { entry in
            guard let apiKey = entry["api-key"] else {
                return false
            }
            if seen.contains(apiKey) {
                return false
            }
            seen.insert(apiKey)
            return true
        }
    }
    
    private static func stripCustomProviderUIMetadata(from entry: [String: Any]) -> [String: Any] {
        var sanitized = entry
        for key in uiMetadataKeys {
            sanitized.removeValue(forKey: key)
        }
        return sanitized
    }
    
    private static func buildOAuthExcludedModels(
        from value: Any?,
        disabledOAuthProviderKeys: [String]
    ) -> [String: Any]? {
        var merged = stringKeyedDictionary(value ?? [:]) ?? [:]
        for providerKey in disabledOAuthProviderKeys.sorted() {
            merged[providerKey] = ["*"]
        }
        return merged.isEmpty ? nil : merged
    }
    
    private static func makeZAIClaudeProviderEntries(baseEntry: [String: Any]?, managedAPIKeys: [String]) -> [[String: Any]] {
        var entry = stripCustomProviderUIMetadata(from: baseEntry ?? [:])
        let preservedAPIKeys = apiKeys(from: entry)
        entry.removeValue(forKey: "name")
        entry.removeValue(forKey: "api-key")
        entry.removeValue(forKey: "api-key-entries")

        if normalizedString(entry["base-url"]) == nil {
            entry["base-url"] = "https://api.z.ai/api/anthropic"
        }

        let effectiveAPIKeys = deduplicatedAPIKeys(
            preservedAPIKeys + managedAPIKeys
        )

        entry["models"] = defaultZAIModels()

        return effectiveAPIKeys.map { apiKey in
            var keyedEntry = entry
            keyedEntry["api-key"] = apiKey
            return keyedEntry
        }
    }

    private static func normalizedProviderID(from entry: [String: Any]) -> String? {
        normalizedString(entry["name"])
    }

    private static func validateMappingArray(_ value: Any, path: String) -> [String] {
        guard let array = value as? [Any] else {
            return ["\(path) must be an array of mappings."]
        }

        var errors: [String] = []
        for (index, rawEntry) in array.enumerated() where stringKeyedDictionary(rawEntry) == nil {
            errors.append("\(path)[\(index)] must be a mapping.")
        }
        return errors
    }

    private static func knownSmartAliasCandidateModels(in root: [String: Any]) -> Set<String> {
        var aliases = Set(defaultZAIModels().compactMap { $0["alias"] })
        for entry in stringKeyedDictionaryArray(root["openai-compatibility"]) {
            for modelEntry in stringKeyedDictionaryArray(entry["models"]) {
                if let alias = normalizedString(modelEntry["alias"]) {
                    aliases.insert(alias)
                }
                if modelEntryExposesCanonicalName(modelEntry),
                   let name = normalizedString(modelEntry["name"]) {
                    aliases.insert(name)
                }
            }
        }
        for entry in stringKeyedDictionaryArray(root["claude-api-key"]) {
            for modelEntry in stringKeyedDictionaryArray(entry["models"]) {
                if let alias = normalizedString(modelEntry["alias"]) {
                    aliases.insert(alias)
                }
                if modelEntryExposesCanonicalName(modelEntry),
                   let name = normalizedString(modelEntry["name"]) {
                    aliases.insert(name)
                }
            }
        }
        return aliases
    }

    private static func modelEntryExposesCanonicalName(_ modelEntry: [String: Any]) -> Bool {
        if let raw = modelEntry["register-canonical-name"] {
            if let value = raw as? Bool {
                return value
            }
            if let string = normalizedString(raw)?.lowercased() {
                switch string {
                case "true":
                    return true
                case "false":
                    return false
                default:
                    break
                }
            }
        }
        return normalizedString(modelEntry["alias"]) == nil
    }

    private static func isManagedZAIClaudeEntry(_ entry: [String: Any]) -> Bool {
        guard let baseURL = normalizedString(entry["base-url"])?.lowercased() else {
            return false
        }
        return baseURL.contains("api.z.ai")
    }

    private static func managedProviderRequiresAPIKey(_ entry: [String: Any]) -> Bool {
        if let raw = entry["requires-api-key"] {
            if let value = raw as? Bool {
                return value
            }
            if let string = normalizedString(raw)?.lowercased() {
                switch string {
                case "true":
                    return true
                case "false":
                    return false
                default:
                    break
                }
            }
        }
        return true
    }

    private static func defaultZAIModels() -> [[String: String]] {
        [
            ["name": "glm-4.7", "alias": "glm-4.7"],
            ["name": "glm-5.1", "alias": "glm-5.1-zai"]
        ]
    }

    private static func temporaryManagedProviderEntries() -> [[String: Any]] {
        [
            [
                "name": "nvidia",
                "display-name": "NVIDIA",
                "help-text": "NVIDIA pool for GLM5 and Kimi K2.5 with automatic request shaping and response cleanup.",
                "icon-system": "bolt.fill",
                "base-url": "https://integrate.api.nvidia.com/v1",
                "models": [
                    ["name": "z-ai/glm5", "alias": "glm5"],
                    ["name": "z-ai/glm5", "alias": "glm5-nvidia"],
                    ["name": "moonshotai/kimi-k2.5", "alias": "kimi-k2.5-nvidia"]
                ]
            ],
            [
                "name": "nvidia-minimax",
                "display-name": "NVIDIA MiniMax",
                "help-text": "NVIDIA pool for minimax-m2.5 with automatic request shaping and response cleanup.",
                "icon-system": "bolt.fill",
                "base-url": "https://integrate.api.nvidia.com/v1",
                "models": [
                    ["name": "minimaxai/minimax-m2.5", "alias": "minimax-m2.5-nvidia"]
                ]
            ],
            [
                "name": "meta-web",
                "display-name": "Meta AI Web UI",
                "help-text": "HAR-backed Meta AI web session adapter for the muse-spark alias.",
                "icon-system": "bubble.left.and.bubble.right.fill",
                "base-url": "https://meta.ai/api/graphql",
                "requires-api-key": false,
                "models": [
                    ["name": "muse-spark", "alias": "muse-spark"]
                ]
            ]
        ]
    }

    private static func defaultManagedSmartAliases() -> [String: Any] {
        [
            "worker": [
                "request-class": "plain-chat",
                "failover": "silent",
                "candidates": ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "glm5-nvidia", "muse-spark"]
            ]
        ]
    }

}
