import Foundation

public final class RouteCatalog {
    public struct ResolvedRoute {
        public let identity: RouteIdentity
        public let endpoint: ProviderEndpoint?
        public let smartAlias: SmartAliasDefinition?
        public let isNVIDIA: Bool

        public init(
            identity: RouteIdentity,
            endpoint: ProviderEndpoint? = nil,
            smartAlias: SmartAliasDefinition? = nil,
            isNVIDIA: Bool = false
        ) {
            self.identity = identity
            self.endpoint = endpoint
            self.smartAlias = smartAlias
            self.isNVIDIA = isNVIDIA
        }
    }

    private var routesByRequestModel: [String: RouteIdentity] = [:]
    private var nvidiaRoutesByRequestModel: [String: RouteIdentity] = [:]
    private var endpointsByProviderID: [String: ProviderEndpoint] = [:]
    private var smartAliasesByAlias: [String: SmartAliasDefinition] = [:]
    private var anthropicRequestModels: Set<String> = []

    public init() {}

    public func load(
        routesByRequestModel: [String: RouteIdentity],
        nvidiaRoutesByRequestModel: [String: RouteIdentity],
        endpointsByProviderID: [String: ProviderEndpoint],
        smartAliasesByAlias: [String: SmartAliasDefinition],
        anthropicRequestModels: Set<String>
    ) {
        self.routesByRequestModel = routesByRequestModel
        self.nvidiaRoutesByRequestModel = nvidiaRoutesByRequestModel
        self.endpointsByProviderID = endpointsByProviderID
        self.smartAliasesByAlias = smartAliasesByAlias
        self.anthropicRequestModels = anthropicRequestModels
    }

    // MARK: - Direct Route Resolution

    public func resolveDirectRoute(forRequestModel model: String) -> RouteIdentity? {
        routesByRequestModel[model]
    }

    public func resolveNVIDIARoute(forRequestModel model: String) -> RouteIdentity? {
        nvidiaRoutesByRequestModel[model]
    }

    public func resolveRouteForAnyProvider(forRequestModel model: String) -> RouteIdentity? {
        routesByRequestModel[model] ?? nvidiaRoutesByRequestModel[model]
    }

    // MARK: - Smart Alias Resolution

    public func resolveSmartAlias(forRequestModel model: String) -> SmartAliasDefinition? {
        smartAliasesByAlias[model]
    }

    public func allSmartAliases() -> [String: SmartAliasDefinition] {
        smartAliasesByAlias
    }

    // MARK: - Provider Endpoint Lookup

    public func providerEndpoint(forProviderID providerID: String) -> ProviderEndpoint? {
        endpointsByProviderID[providerID]
    }

    public func allEndpoints() -> [String: ProviderEndpoint] {
        endpointsByProviderID
    }

    // MARK: - Model Queries

    public func isAnthropicModel(_ model: String) -> Bool {
        anthropicRequestModels.contains(model)
    }

    public func allRequestModels() -> Set<String> {
        Set(routesByRequestModel.keys).union(nvidiaRoutesByRequestModel.keys)
    }

    // MARK: - Diagnostics

    public func routeDiagnostics() -> [String: ResolvedRoute] {
        var result: [String: ResolvedRoute] = [:]
        for (model, identity) in routesByRequestModel {
            result[model] = ResolvedRoute(
                identity: identity,
                endpoint: endpointsByProviderID[identity.providerID],
                isNVIDIA: identity.providerID.contains("nvidia")
            )
        }
        for (model, identity) in nvidiaRoutesByRequestModel {
            if result[model] == nil {
                result[model] = ResolvedRoute(
                    identity: identity,
                    endpoint: endpointsByProviderID[identity.providerID],
                    isNVIDIA: true
                )
            }
        }
        return result
    }
}
