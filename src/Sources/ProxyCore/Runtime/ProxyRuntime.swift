import Foundation

public final class ProxyRuntime {
    public let catalog: RouteCatalog
    public let modelPolicies: ModelPolicyRegistry
    public let providerPolicies: ProviderPolicyRegistry
    public let credentials: CredentialPool
    public let healthStore: RouteHealthStore
    public let concurrencyLimiter: RouteConcurrencyLimiter
    public let telemetry: RouteTelemetryStore
    public let transport: TransportFacade
    public let factoryResolver: FactoryContractResolver

    public init(
        catalog: RouteCatalog = RouteCatalog(),
        modelPolicies: ModelPolicyRegistry = ModelPolicyRegistry(),
        providerPolicies: ProviderPolicyRegistry = ProviderPolicyRegistry(),
        credentials: CredentialPool = CredentialPool(),
        healthStore: RouteHealthStore = RouteHealthStore(),
        concurrencyLimiter: RouteConcurrencyLimiter = RouteConcurrencyLimiter(),
        telemetry: RouteTelemetryStore = RouteTelemetryStore(),
        transport: TransportFacade = TransportFacade(),
        factoryResolver: FactoryContractResolver = FactoryContractResolver()
    ) {
        self.catalog = catalog
        self.modelPolicies = modelPolicies
        self.providerPolicies = providerPolicies
        self.credentials = credentials
        self.healthStore = healthStore
        self.concurrencyLimiter = concurrencyLimiter
        self.telemetry = telemetry
        self.transport = transport
        self.factoryResolver = factoryResolver
    }

    /// Convenience factory that loads all services from ManagedRouteManifest defaults.
    public static func fromManifest() -> ProxyRuntime {
        let runtime = ProxyRuntime()
        runtime.modelPolicies.load(
            nvidiaPolicies: ManagedRouteManifest.nvidiaRoutePolicyEntries,
            nonNVIDIAMitigationPolicies: ManagedRouteManifest.nonNVIDIAMitigationPolicyEntries,
            modelTiers: ManagedRouteManifest.modelTierEntries,
            inputPrices: ManagedRouteManifest.inputPricePerMillionTokensEntries,
            legacyRewrites: ManagedRouteManifest.legacyRequestModelRewriteEntries,
            workerSmartRoutePolicy: ManagedRouteManifest.workerSmartRouteRequestPolicy
        )
        return runtime
    }
}
