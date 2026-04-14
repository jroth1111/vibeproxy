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

    public init(
        catalog: RouteCatalog = RouteCatalog(),
        modelPolicies: ModelPolicyRegistry = ModelPolicyRegistry(),
        providerPolicies: ProviderPolicyRegistry = ProviderPolicyRegistry(),
        credentials: CredentialPool = CredentialPool(),
        healthStore: RouteHealthStore = RouteHealthStore(),
        concurrencyLimiter: RouteConcurrencyLimiter = RouteConcurrencyLimiter(),
        telemetry: RouteTelemetryStore = RouteTelemetryStore(),
        transport: TransportFacade = TransportFacade()
    ) {
        self.catalog = catalog
        self.modelPolicies = modelPolicies
        self.providerPolicies = providerPolicies
        self.credentials = credentials
        self.healthStore = healthStore
        self.concurrencyLimiter = concurrencyLimiter
        self.telemetry = telemetry
        self.transport = transport
    }
}
